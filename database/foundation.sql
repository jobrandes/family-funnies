-- Standalone Family Funnies. No current Site data is imported by this migration.
create schema if not exists family_private;
revoke all on schema family_private from public;
grant usage on schema family_private to authenticated;

-- Only server configuration may add trusted identity issuers. Empty = fail closed.
create table family_private.identity_providers (
  issuer text primary key,
  audience text not null
);
create function family_private.actor() returns text
language sql stable security definer set search_path = '' as $$
  select case when length(auth.jwt()->>'sub') between 1 and 200
    and auth.jwt()->>'email_verified' = 'true'
    and exists(select 1 from family_private.identity_providers p
      where p.issuer = auth.jwt()->>'iss' and p.audience = auth.jwt()->>'aud')
  then (auth.jwt()->>'iss') || '|' || (auth.jwt()->>'sub') end
$$;
revoke all on function family_private.actor() from public;
grant execute on function family_private.actor() to authenticated;

create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check(length(trim(name)) between 1 and 100),
  boundaries text not null default '',
  relationships text not null default '',
  tone text not null default 'Warm and affectionate',
  cast_notes text not null default '',
  visual_revision bigint not null default 1,
  production_enabled boolean not null default false,
  timezone text not null default 'America/Los_Angeles',
  created_at timestamptz not null default now()
);
create table public.family_memberships (
  family_id uuid not null references public.families on delete cascade,
  actor_id text not null,
  role text not null check(role in ('owner','contributor','reader')),
  created_at timestamptz not null default now(),
  primary key(family_id,actor_id)
);
create index memberships_actor on public.family_memberships(actor_id,family_id);
create function family_private.member_role(fid uuid) returns text
language sql stable security definer set search_path = '' as $$
  select m.role from public.family_memberships m
  where m.family_id=fid and m.actor_id=family_private.actor()
$$;
revoke all on function family_private.member_role(uuid) from public;
grant execute on function family_private.member_role(uuid) to authenticated;

create table public.people (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families on delete cascade,
  name text not null check(length(trim(name)) between 1 and 100),
  kind text not null default 'person' check(kind in ('person','pet')),
  relationship text not null default '',
  appearance text not null default '',
  personality text not null default '',
  interests text not null default '',
  habits text not null default '',
  boundaries text not null default '',
  memorial boolean not null default false,
  memorial_caption text not null default '',
  created_at timestamptz not null default now(),
  unique(family_id,id)
);
create index people_family on public.people(family_id);
create table public.reference_photos (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families on delete cascade,
  person_id uuid not null,
  object_path text not null unique,
  position smallint not null check(position between 0 and 5),
  subject_notes text not null default '',
  foreign key(family_id,person_id) references public.people(family_id,id) on delete cascade,
  unique(person_id,position),
  check(object_path like family_id::text || '/%')
);
create index reference_photos_family on public.reference_photos(family_id);
create table public.story_moments (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families on delete cascade,
  text text not null check(length(trim(text)) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index moments_family on public.story_moments(family_id);
create table public.cast_versions (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families on delete cascade,
  visual_revision bigint not null,
  object_path text not null,
  missing jsonb not null default '[]' check(jsonb_typeof(missing)='array'),
  approved_at timestamptz,
  approved_by text,
  created_at timestamptz not null default now(),
  check(object_path like family_id::text || '/%'),
  check((approved_at is null)=(approved_by is null))
);
create index cast_family_revision on public.cast_versions(family_id,visual_revision);
create table public.cast_jobs (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families on delete cascade,
  visual_revision bigint not null,
  state text not null default 'queued' check(state in ('queued','processing','ready','failed')),
  attempts smallint not null default 0 check(attempts between 0 and 3),
  claim_id uuid,
  claim_expires_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique(family_id,visual_revision)
);
create table public.episodes (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families on delete cascade,
  day date not null,
  title text not null check(length(trim(title)) between 1 and 200),
  script text not null,
  object_path text not null,
  created_at timestamptz not null default now(),
  unique(family_id,day),
  check(object_path like family_id::text || '/%')
);
-- Secret-bearing records are never exposed through the Data API.
create table family_private.invitations (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families on delete cascade,
  token_hash text not null unique,
  role text not null check(role in ('contributor','reader')),
  expires_at timestamptz not null default now()+interval '7 days',
  used_at timestamptz,
  revoked_at timestamptz,
  created_by text not null
);
create index invitations_family on family_private.invitations(family_id);
create table family_private.comic_shares (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families on delete cascade,
  token_hash text not null unique,
  created_by text not null,
  expires_at timestamptz not null default now()+interval '180 days',
  revoked_at timestamptz
);
create index shares_family on family_private.comic_shares(family_id);
create table public.family_audit (
  id bigint generated always as identity primary key,
  family_id uuid not null references public.families on delete cascade,
  actor_id text not null,
  action text not null,
  created_at timestamptz not null default now()
);
create index audit_family on public.family_audit(family_id);

alter table public.families enable row level security;
alter table public.family_memberships enable row level security;
alter table public.people enable row level security;
alter table public.reference_photos enable row level security;
alter table public.story_moments enable row level security;
alter table public.cast_versions enable row level security;
alter table public.cast_jobs enable row level security;
alter table public.episodes enable row level security;
alter table public.family_audit enable row level security;
alter table family_private.identity_providers enable row level security;
alter table family_private.invitations enable row level security;
alter table family_private.comic_shares enable row level security;

revoke all on public.families,public.family_memberships,public.people,
 public.reference_photos,public.story_moments,public.cast_versions,
 public.cast_jobs,public.episodes,public.family_audit from anon,authenticated;
grant select on public.families,public.family_memberships,public.people,
 public.reference_photos,public.story_moments,public.cast_versions,
 public.cast_jobs,public.episodes,public.family_audit to authenticated;
grant insert,update,delete on public.people,public.reference_photos,public.story_moments to authenticated;
grant update(name,boundaries,relationships,tone,cast_notes) on public.families to authenticated;

create policy families_read on public.families for select to authenticated
 using(family_private.member_role(id) is not null);
create policy families_edit on public.families for update to authenticated
 using(family_private.member_role(id)='owner') with check(family_private.member_role(id)='owner');
create policy memberships_read on public.family_memberships for select to authenticated
 using(actor_id=family_private.actor() or family_private.member_role(family_id)='owner');
create policy people_read on public.people for select to authenticated
 using(family_private.member_role(family_id) in ('owner','contributor'));
create policy people_edit on public.people for all to authenticated
 using(family_private.member_role(family_id) in ('owner','contributor'))
 with check(family_private.member_role(family_id) in ('owner','contributor'));
create policy photos_read on public.reference_photos for select to authenticated
 using(family_private.member_role(family_id) in ('owner','contributor'));
create policy photos_edit on public.reference_photos for all to authenticated
 using(family_private.member_role(family_id) in ('owner','contributor'))
 with check(family_private.member_role(family_id) in ('owner','contributor'));
create policy moments_read on public.story_moments for select to authenticated
 using(family_private.member_role(family_id) in ('owner','contributor'));
create policy moments_edit on public.story_moments for all to authenticated
 using(family_private.member_role(family_id) in ('owner','contributor'))
 with check(family_private.member_role(family_id) in ('owner','contributor'));
create policy casts_read on public.cast_versions for select to authenticated
 using(family_private.member_role(family_id) in ('owner','contributor'));
create policy jobs_read on public.cast_jobs for select to authenticated
 using(family_private.member_role(family_id) in ('owner','contributor'));
create policy episodes_read on public.episodes for select to authenticated
 using(family_private.member_role(family_id) is not null);
create policy audit_read on public.family_audit for select to authenticated
 using(family_private.member_role(family_id)='owner');

-- Immutable tenant keys, even for a person belonging to both families.
create function family_private.immutable_family() returns trigger
language plpgsql set search_path='' as $$ begin
 if new.family_id<>old.family_id then raise exception 'Family cannot be reassigned'; end if;
 return new;
end $$;
create trigger people_family_fixed before update on public.people
 for each row execute function family_private.immutable_family();
create trigger photos_family_fixed before update on public.reference_photos
 for each row execute function family_private.immutable_family();
create trigger moments_family_fixed before update on public.story_moments
 for each row execute function family_private.immutable_family();

create function family_private.visual_changed() returns trigger
language plpgsql security definer set search_path='' as $$
declare fid uuid;
begin
 if tg_table_name='people' and tg_op='UPDATE' then
   if (new.name,new.kind,new.appearance,new.memorial,new.memorial_caption)
     is not distinct from (old.name,old.kind,old.appearance,old.memorial,old.memorial_caption) then return new; end if;
 end if;
 if tg_op='DELETE' then fid:=old.family_id; else fid:=new.family_id; end if;
 update public.families set visual_revision=visual_revision+1,production_enabled=false where id=fid;
 insert into public.cast_jobs(family_id,visual_revision)
 select id,visual_revision from public.families where id=fid on conflict do nothing;
 return null;
end $$;
revoke all on function family_private.visual_changed() from public;
create trigger people_visual after insert or update or delete on public.people
 for each row execute function family_private.visual_changed();
create trigger photos_visual after insert or update or delete on public.reference_photos
 for each row execute function family_private.visual_changed();
create function family_private.cast_notes_changed() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if new.cast_notes is distinct from old.cast_notes then
   new.visual_revision:=old.visual_revision+1; new.production_enabled:=false;
 end if;
 return new;
end $$;
revoke all on function family_private.cast_notes_changed() from public;
create trigger notes_revision before update on public.families
 for each row execute function family_private.cast_notes_changed();
create function family_private.queue_notes() returns trigger
language plpgsql security definer set search_path='' as $$ begin
 if new.visual_revision<>old.visual_revision then
  insert into public.cast_jobs(family_id,visual_revision) values(new.id,new.visual_revision) on conflict do nothing;
 end if; return null;
end $$;
revoke all on function family_private.queue_notes() from public;
create trigger notes_queue after update on public.families
 for each row execute function family_private.queue_notes();

-- Privileged transactions have private implementations and small invoker RPC wrappers.
create function family_private.create_family(family_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare actor text:=family_private.actor(); fid uuid;
begin
 if actor is null then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 if (select count(*) from public.family_memberships where actor_id=actor and role='owner')>=10 then
  raise exception 'Family limit reached'; end if;
 insert into public.families(name) values(trim(family_name)) returning id into fid;
 insert into public.family_memberships(family_id,actor_id,role) values(fid,actor,'owner');
 insert into public.family_audit(family_id,actor_id,action) values(fid,actor,'family.created');
 return fid;
end $$;
revoke all on function family_private.create_family(text) from public;
grant execute on function family_private.create_family(text) to authenticated;
create function public.create_family(family_name text) returns uuid
language sql security invoker set search_path='' as $$ select family_private.create_family(family_name) $$;
revoke all on function public.create_family(text) from public;
grant execute on function public.create_family(text) to authenticated;

-- No generation worker is connected by this migration. Production remains disabled.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('family-references','family-references',false,5242880,array['image/jpeg','image/png','image/webp']),
 ('family-comics','family-comics',false,12582912,array['image/png','image/webp','image/jpeg']);
create function family_private.path_family(path text) returns uuid
language plpgsql immutable set search_path='' as $$ begin
 return split_part(path,'/',1)::uuid;
 exception when invalid_text_representation then return null;
end $$;
revoke all on function family_private.path_family(text) from public;
grant execute on function family_private.path_family(text) to authenticated;
create policy reference_download on storage.objects for select to authenticated
 using(bucket_id='family-references' and family_private.member_role(family_private.path_family(name)) in ('owner','contributor'));
create policy reference_upload on storage.objects for insert to authenticated
 with check(bucket_id='family-references' and family_private.member_role(family_private.path_family(name)) in ('owner','contributor'));
create policy reference_delete on storage.objects for delete to authenticated
 using(bucket_id='family-references' and family_private.member_role(family_private.path_family(name)) in ('owner','contributor'));
create policy comic_download on storage.objects for select to authenticated
 using(bucket_id='family-comics' and family_private.member_role(family_private.path_family(name)) is not null);
