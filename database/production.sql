-- Trusted runner commands are service-role only. Family managers enable production via RLS-aware RPC.
create table public.episode_jobs (
 id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families on delete cascade,
 day date not null, visual_revision bigint not null, claim_id uuid not null default gen_random_uuid(),
 expires_at timestamptz not null default now()+interval '30 minutes', state text not null default 'processing' check(state in ('processing','ready','failed')),
 unique(family_id,day)
);
alter table public.episode_jobs enable row level security;
revoke all on public.episode_jobs from anon,authenticated;
create function public.enable_production(fid uuid) returns void language plpgsql security definer set search_path='' as $$
declare rev bigint;
begin
 if family_private.member_role(fid) is distinct from 'owner' then raise exception 'Owner required'; end if;
 select visual_revision into rev from public.families where id=fid for update;
 if not exists(select 1 from public.people where family_id=fid) or not exists(select 1 from public.cast_versions where family_id=fid and visual_revision=rev and approved_at is not null and missing='[]'::jsonb) then raise exception 'Approve the current complete cast first'; end if;
 update public.families set production_enabled=true where id=fid;
end $$;
revoke all on function public.enable_production(uuid) from public;
grant execute on function public.enable_production(uuid) to authenticated;
create function public.runner_command(command text, fid uuid, revision bigint, claim uuid default null, target_day date default null, object_path text default null, title text default null, script text default null, missing jsonb default '[]') returns jsonb language plpgsql security definer set search_path='' as $$
declare f public.families; j public.cast_jobs; e public.episode_jobs; newclaim uuid;
begin
 select * into f from public.families where id=fid for update;
 if f.id is null then raise exception 'Family unavailable'; end if;
 if command='cast_fail' then
 update public.cast_jobs set state='failed',claim_id=null,claim_expires_at=null where family_id=fid and visual_revision=revision and claim_id=claim; return '{}'::jsonb;
 end if;
 if command='episode_fail' then
 update public.episode_jobs set state='failed' where family_id=fid and day=target_day and claim_id=claim; return '{}'::jsonb;
 end if;
 if f.visual_revision<>revision then raise exception 'Revision conflict'; end if;
 if command='cast_claim' then
 select * into j from public.cast_jobs where family_id=fid and visual_revision=revision for update;
 if j.id is null or j.attempts>=3 or j.state='ready' or (j.state='processing' and j.claim_expires_at>now()) then raise exception 'Claim conflict'; end if;
 newclaim:=gen_random_uuid(); update public.cast_jobs set state='processing',attempts=attempts+1,claim_id=newclaim,claim_expires_at=now()+interval '30 minutes' where id=j.id;
 return jsonb_build_object('claimId',newclaim);
 elsif command='cast_complete' then
 if not exists(select 1 from public.cast_jobs where family_id=fid and visual_revision=revision and claim_id=claim and state='processing' and claim_expires_at>now()) then raise exception 'Claim conflict'; end if;
 if object_path not like fid::text||'/%' or jsonb_typeof(missing)<>'array' then raise exception 'Invalid asset'; end if;
 insert into public.cast_versions(family_id,visual_revision,object_path,missing) values(fid,revision,object_path,missing);
 update public.cast_jobs set state='ready',claim_id=null,claim_expires_at=null where family_id=fid and visual_revision=revision;
 return '{}'::jsonb;
 end if;
 if not f.production_enabled or not exists(select 1 from public.cast_versions c where c.family_id=fid and c.visual_revision=revision and c.approved_at is not null and c.missing='[]') then raise exception 'Production paused or cast review pending'; end if;
 if target_day<>(now() at time zone 'America/Los_Angeles')::date then raise exception 'Wrong production date'; end if;
 if exists(select 1 from public.episodes where family_id=fid and day=target_day) then raise exception 'Episode exists'; end if;
 if command='episode_claim' then
 select * into e from public.episode_jobs where family_id=fid and day=target_day for update;
 if e.id is not null and e.state='processing' and e.expires_at>now() then raise exception 'Claim conflict'; end if;
 newclaim:=gen_random_uuid(); insert into public.episode_jobs(family_id,day,visual_revision,claim_id) values(fid,target_day,revision,newclaim) on conflict(family_id,day) do update set visual_revision=revision,claim_id=newclaim,state='processing',expires_at=now()+interval '30 minutes';
 return jsonb_build_object('claimId',newclaim);
 elsif command='episode_complete' then
 if not exists(select 1 from public.episode_jobs where family_id=fid and day=target_day and claim_id=claim and visual_revision=revision and state='processing' and expires_at>now()) then raise exception 'Claim conflict'; end if;
 if object_path not like fid::text||'/%' then raise exception 'Invalid asset'; end if;
 insert into public.episodes(family_id,day,title,script,object_path) values(fid,target_day,title,script,object_path);
 update public.episode_jobs set state='ready' where family_id=fid and day=target_day;
 return '{}'::jsonb;
 else raise exception 'Unknown command'; end if;
end $$;
revoke all on function public.runner_command(text,uuid,bigint,uuid,date,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.runner_command(text,uuid,bigint,uuid,date,text,text,text,jsonb) to service_role;
