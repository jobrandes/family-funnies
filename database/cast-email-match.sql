-- Lets a family manager attach an email to a cast member. When an account with
-- that VERIFIED email signs in, it is offered (never forced) a place in the
-- family as a reader. Depends on foundation.sql and family-management.sql.
--
-- Privacy rules built in:
--  * emails live in the private schema and are readable only by that family's owner
--  * the owner learns that an account exists only if its holder accepts
--  * a decline is remembered per family and email, so removing and re-adding
--    the same email cannot be used to nag someone
begin;
create table family_private.member_matches (
 id uuid primary key default gen_random_uuid(),
 family_id uuid not null references public.families on delete cascade,
 person_id uuid not null unique,
 email text not null check(email=lower(email) and length(email) between 3 and 254),
 created_by text not null,
 created_at timestamptz not null default now(),
 accepted_at timestamptz,
 accepted_by text,
 foreign key(family_id,person_id) references public.people(family_id,id) on delete cascade,
 unique(family_id,email)
);
create index member_matches_email on family_private.member_matches(email);
create table family_private.match_declines (
 family_id uuid not null references public.families on delete cascade,
 email text not null,
 declined_at timestamptz not null default now(),
 primary key(family_id,email)
);
alter table family_private.member_matches enable row level security;
alter table family_private.match_declines enable row level security;
revoke all on family_private.member_matches,family_private.match_declines from public,anon,authenticated;

-- The caller's own verified email, or null. actor() already requires a trusted
-- issuer, audience and email_verified=true.
create function family_private.actor_email() returns text
language sql stable security definer set search_path='' as $$
 select case when family_private.actor() is not null and length(auth.jwt()->>'email') between 3 and 254
  then lower(trim(auth.jwt()->>'email')) end
$$;

create function family_private.set_member_email(target_person uuid,new_email text) returns void
language plpgsql security definer set search_path='' as $$
declare p public.people; cleaned text:=nullif(lower(trim(coalesce(new_email,''))),'');
begin
 select * into p from public.people where id=target_person for update;
 if p.id is null or family_private.member_role(p.family_id) is distinct from 'owner' then raise exception 'Owner required' using errcode='42501';end if;
 if cleaned is null then delete from family_private.member_matches where person_id=target_person; return; end if;
 if p.kind<>'person' then raise exception 'Only people can be matched to an account';end if;
 if length(cleaned)>254 or cleaned !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then raise exception 'Enter a valid email address';end if;
 if exists(select 1 from family_private.member_matches m where m.family_id=p.family_id and m.email=cleaned and m.person_id<>target_person) then
  raise exception 'That email is already on another cast member in this family';end if;
 insert into family_private.member_matches(family_id,person_id,email,created_by) values(p.family_id,target_person,cleaned,family_private.actor())
 on conflict(person_id) do update set email=excluded.email,created_by=excluded.created_by,created_at=now(),
  accepted_at=case when family_private.member_matches.email=excluded.email then family_private.member_matches.accepted_at end,
  accepted_by=case when family_private.member_matches.email=excluded.email then family_private.member_matches.accepted_by end;
 insert into public.family_audit(family_id,actor_id,action) values(p.family_id,family_private.actor(),'match.email_set');
end $$;

-- Declines are deliberately reported as 'waiting'.
create function family_private.list_member_emails(fid uuid) returns table(person_id uuid,email text,status text)
language plpgsql stable security definer set search_path='' as $$ begin
 if family_private.member_role(fid) is distinct from 'owner' then raise exception 'Owner required' using errcode='42501';end if;
 return query select m.person_id,m.email,case when m.accepted_at is not null then 'joined' else 'waiting' end
  from family_private.member_matches m where m.family_id=fid;
end $$;

create function family_private.my_family_matches() returns table(match_id uuid,family_id uuid,family_name text,cast_name text)
language sql stable security definer set search_path='' as $$
 select m.id,f.id,f.name,p.name from family_private.member_matches m
  join public.families f on f.id=m.family_id and f.deleted_at is null
  join public.people p on p.id=m.person_id
 where family_private.actor_email() is not null and m.email=family_private.actor_email() and m.accepted_at is null
  and not exists(select 1 from family_private.match_declines d where d.family_id=m.family_id and d.email=m.email)
  and not exists(select 1 from public.family_memberships x where x.family_id=m.family_id and x.actor_id=family_private.actor())
 order by m.created_at limit 20
$$;

create function family_private.accept_family_match(target_match uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare m family_private.member_matches; me text:=family_private.actor(); mine text:=family_private.actor_email();
begin
 if me is null or mine is null then raise exception 'Verified sign-in required' using errcode='42501';end if;
 select * into m from family_private.member_matches where id=target_match for update;
 if m.id is null or m.email<>mine or m.accepted_at is not null
  or exists(select 1 from public.families f where f.id=m.family_id and f.deleted_at is not null)
  or exists(select 1 from family_private.match_declines d where d.family_id=m.family_id and d.email=m.email) then
  raise exception 'Invitation unavailable';end if;
 if exists(select 1 from public.family_memberships x where x.family_id=m.family_id and x.actor_id=me) then
  raise exception 'You already belong to this family';end if;
 insert into public.family_memberships(family_id,actor_id,role) values(m.family_id,me,'reader');
 update family_private.member_matches set accepted_at=now(),accepted_by=me where id=m.id;
 insert into public.family_audit(family_id,actor_id,action) values(m.family_id,me,'match.accepted');
 return m.family_id;
end $$;

create function family_private.decline_family_match(target_match uuid) returns void
language plpgsql security definer set search_path='' as $$
declare m family_private.member_matches; mine text:=family_private.actor_email();
begin
 if mine is null then raise exception 'Verified sign-in required' using errcode='42501';end if;
 select * into m from family_private.member_matches where id=target_match for update;
 if m.id is null or m.email<>mine or m.accepted_at is not null then raise exception 'Invitation unavailable';end if;
 insert into family_private.match_declines(family_id,email) values(m.family_id,m.email) on conflict do nothing;
end $$;

create function public.set_member_email(target_person uuid,new_email text) returns void language sql security invoker set search_path='' as $$ select family_private.set_member_email(target_person,new_email) $$;
create function public.list_member_emails(fid uuid) returns table(person_id uuid,email text,status text) language sql security invoker set search_path='' as $$ select * from family_private.list_member_emails(fid) $$;
create function public.my_family_matches() returns table(match_id uuid,family_id uuid,family_name text,cast_name text) language sql security invoker set search_path='' as $$ select * from family_private.my_family_matches() $$;
create function public.accept_family_match(target_match uuid) returns uuid language sql security invoker set search_path='' as $$ select family_private.accept_family_match(target_match) $$;
create function public.decline_family_match(target_match uuid) returns void language sql security invoker set search_path='' as $$ select family_private.decline_family_match(target_match) $$;

revoke all on function family_private.actor_email(),family_private.set_member_email(uuid,text),family_private.list_member_emails(uuid),family_private.my_family_matches(),family_private.accept_family_match(uuid),family_private.decline_family_match(uuid) from public;
revoke all on function public.set_member_email(uuid,text),public.list_member_emails(uuid),public.my_family_matches(),public.accept_family_match(uuid),public.decline_family_match(uuid) from public;
grant execute on function family_private.actor_email(),family_private.set_member_email(uuid,text),family_private.list_member_emails(uuid),family_private.my_family_matches(),family_private.accept_family_match(uuid),family_private.decline_family_match(uuid) to anon,authenticated;
grant execute on function public.set_member_email(uuid,text),public.list_member_emails(uuid),public.my_family_matches(),public.accept_family_match(uuid),public.decline_family_match(uuid) to anon,authenticated;
commit;
