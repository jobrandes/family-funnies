begin;
alter table public.families add column deleted_at timestamptz;
alter table public.families add column onboarding_step smallint not null default 0 check(onboarding_step between 0 and 5);
create or replace function family_private.member_role(fid uuid) returns text
language sql stable security definer set search_path='' as $$
 select m.role from public.family_memberships m join public.families f on f.id=m.family_id
 where m.family_id=fid and m.actor_id=family_private.actor() and f.deleted_at is null
$$;

create function family_private.begin_family(family_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare fid uuid;
begin
 fid:=family_private.create_family(family_name);
 update public.families set onboarding_step=2 where id=fid;
 return fid;
end $$;
create function family_private.save_setup(fid uuid,next_step smallint) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.families where id=fid for update;
 if family_private.member_role(fid) is distinct from 'owner' then raise exception 'Owner required' using errcode='42501';end if;
 if next_step not between 1 and 5 then raise exception 'Invalid setup step';end if;
 if next_step>=3 and not exists(select 1 from public.people where family_id=fid) then raise exception 'Add at least one person or pet';end if;
 if next_step>=4 and exists(select 1 from public.people p where p.family_id=fid and not exists(select 1 from public.reference_photos r where r.person_id=p.id and r.family_id=fid)) then raise exception 'Add a photo for every cast member';end if;
 update public.families set onboarding_step=next_step where id=fid;
end $$;
create function family_private.trash_family(fid uuid,confirmation text) returns void
language plpgsql security definer set search_path='' as $$
declare f public.families;
begin
 select * into f from public.families where id=fid for update;
 if family_private.actor() is null or not exists(select 1 from public.family_memberships where family_id=fid and actor_id=family_private.actor() and role='owner') then raise exception 'Owner required' using errcode='42501';end if;
 if confirmation is distinct from f.name then raise exception 'Type the family name to confirm';end if;
 update public.families set deleted_at=coalesce(deleted_at,now()),production_enabled=false where id=fid;
 update public.cast_jobs set state='ready',claim_id=null,claim_expires_at=null where family_id=fid;
 update public.episode_jobs set state='failed' where family_id=fid and state='processing';
 insert into public.family_audit(family_id,actor_id,action) values(fid,family_private.actor(),'family.trashed');
end $$;
create function family_private.list_family_trash() returns table(id uuid,name text,deleted_at timestamptz)
language sql stable security definer set search_path='' as $$
 select f.id,f.name,f.deleted_at from public.families f join public.family_memberships m on m.family_id=f.id
 where m.actor_id=family_private.actor() and m.role='owner' and f.deleted_at is not null order by f.deleted_at desc
$$;
create function family_private.restore_family(fid uuid) returns void
language plpgsql security definer set search_path='' as $$
declare rev bigint;
begin
 perform 1 from public.families where id=fid for update;
 if family_private.actor() is null or not exists(select 1 from public.family_memberships where family_id=fid and actor_id=family_private.actor() and role='owner') then raise exception 'Owner required' using errcode='42501';end if;
 update public.families set deleted_at=null,production_enabled=false where id=fid returning visual_revision into rev;
 update public.cast_jobs set state='queued' where family_id=fid and visual_revision=rev and attempts<3 and not exists(select 1 from public.cast_versions where family_id=fid and visual_revision=rev);
 insert into public.family_audit(family_id,actor_id,action) values(fid,family_private.actor(),'family.restored');
end $$;
create function family_private.remove_cast_member(person_id uuid,confirmation text) returns void
language plpgsql security definer set search_path='' as $$
declare p public.people;
begin
 select * into p from public.people where id=person_id for update;
 if p.id is null or family_private.member_role(p.family_id) is distinct from 'owner' then raise exception 'Owner required' using errcode='42501';end if;
 if confirmation is distinct from p.name then raise exception 'Type the member name to confirm';end if;
 delete from public.people where id=person_id;
 insert into public.family_audit(family_id,actor_id,action) values(p.family_id,family_private.actor(),'cast.member_removed');
end $$;
-- Removing a redundant photo does not change an already-approved appearance.
create or replace function family_private.visual_changed() returns trigger
language plpgsql security definer set search_path='' as $$
declare fid uuid;
begin
 if tg_table_name='people' and tg_op='UPDATE' then
  if (new.name,new.kind,new.appearance,new.memorial,new.memorial_caption) is not distinct from (old.name,old.kind,old.appearance,old.memorial,old.memorial_caption) then return new;end if;
 end if;
 if tg_table_name='reference_photos' and tg_op='UPDATE' then
  if (new.object_path,new.person_id,new.subject_notes) is not distinct from (old.object_path,old.person_id,old.subject_notes) then return new;end if;
 end if;
 if tg_table_name='reference_photos' then
  if tg_op='DELETE' then
   if exists(select 1 from public.reference_photos where person_id=old.person_id and family_id=old.family_id) and exists(select 1 from public.families f join public.cast_versions c on c.family_id=f.id and c.visual_revision=f.visual_revision where f.id=old.family_id and c.approved_at is not null and c.missing='[]'::jsonb) then return old;end if;
  end if;
 end if;
 if tg_op='DELETE' then fid:=old.family_id;else fid:=new.family_id;end if;
 update public.families set visual_revision=visual_revision+1,production_enabled=false where id=fid;
 insert into public.cast_jobs(family_id,visual_revision) select id,visual_revision from public.families where id=fid on conflict do nothing;
 return null;
end $$;
-- Contributors can add/update profiles; only managers can remove them.
drop policy people_edit on public.people;
create policy people_insert on public.people for insert to anon,authenticated with check(family_private.member_role(family_id) in ('owner','contributor'));
create policy people_update on public.people for update to anon,authenticated using(family_private.member_role(family_id) in ('owner','contributor')) with check(family_private.member_role(family_id) in ('owner','contributor'));
revoke delete on public.people from anon,authenticated;

create function public.begin_family(family_name text) returns uuid language sql security invoker set search_path='' as $$ select family_private.begin_family(family_name) $$;
create function public.save_setup(fid uuid,next_step smallint) returns void language sql security invoker set search_path='' as $$ select family_private.save_setup(fid,next_step) $$;
create function public.trash_family(fid uuid,confirmation text) returns void language sql security invoker set search_path='' as $$ select family_private.trash_family(fid,confirmation) $$;
create function public.list_family_trash() returns table(id uuid,name text,deleted_at timestamptz) language sql security invoker set search_path='' as $$ select * from family_private.list_family_trash() $$;
create function public.restore_family(fid uuid) returns void language sql security invoker set search_path='' as $$ select family_private.restore_family(fid) $$;
create function public.remove_cast_member(person_id uuid,confirmation text) returns void language sql security invoker set search_path='' as $$ select family_private.remove_cast_member(person_id,confirmation) $$;
revoke all on function family_private.begin_family(text),family_private.save_setup(uuid,smallint),family_private.trash_family(uuid,text),family_private.list_family_trash(),family_private.restore_family(uuid),family_private.remove_cast_member(uuid,text) from public;
revoke all on function public.begin_family(text),public.save_setup(uuid,smallint),public.trash_family(uuid,text),public.list_family_trash(),public.restore_family(uuid),public.remove_cast_member(uuid,text) from public;
grant execute on function family_private.begin_family(text),family_private.save_setup(uuid,smallint),family_private.trash_family(uuid,text),family_private.list_family_trash(),family_private.restore_family(uuid),family_private.remove_cast_member(uuid,text) to anon,authenticated;
grant execute on function public.begin_family(text),public.save_setup(uuid,smallint),public.trash_family(uuid,text),public.list_family_trash(),public.restore_family(uuid),public.remove_cast_member(uuid,text) to anon,authenticated;
commit;
