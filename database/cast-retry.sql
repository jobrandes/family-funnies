-- Durable cast recovery. A failed attempt never permanently abandons a saved revision.
alter table public.cast_jobs drop constraint cast_jobs_attempts_check;
alter table public.cast_jobs alter column attempts type integer;
alter table public.cast_jobs add constraint cast_jobs_attempts_check check(attempts>=0);
-- No new scheduler, image provider, production opt-in, or family permissions are introduced.
alter table public.cast_jobs add column if not exists updated_at timestamptz not null default now();
alter table public.cast_jobs add column if not exists next_retry_at timestamptz;
create or replace function family_private.cast_retry_delay(attempt integer) returns interval
language sql immutable set search_path='' as $$
 select make_interval(mins => case when attempt<=1 then 5 when attempt=2 then 15
 when attempt=3 then 60 when attempt=4 then 180 else 360 end)
$$;
revoke all on function family_private.cast_retry_delay(integer) from public,anon,authenticated;

create or replace function public.runner_command(command text, fid uuid, revision bigint, claim uuid default null, target_day date default null, object_path text default null, title text default null, script text default null, missing jsonb default '[]') returns jsonb language plpgsql security definer set search_path='' as $$
declare f public.families; j public.cast_jobs; e public.episode_jobs; newclaim uuid;
begin
 select * into f from public.families where id=fid for update;
 if f.id is null or f.deleted_at is not null then raise exception 'Family unavailable'; end if;
 if command='cast_fail' then
 update public.cast_jobs set state='failed',claim_id=null,claim_expires_at=null,
 last_error='Cast attempt failed; automatic retry scheduled',updated_at=now(),
 next_retry_at=now()+family_private.cast_retry_delay(attempts)
 where family_id=fid and visual_revision=revision and claim_id=claim and state='processing';
 if not found then raise exception 'Claim conflict'; end if;
 return jsonb_build_object('retryScheduled',true);
 end if;
 if command='episode_fail' then
 update public.episode_jobs set state='failed' where family_id=fid and day=target_day and claim_id=claim; return '{}'::jsonb;
 end if;
 if f.visual_revision<>revision then raise exception 'Revision conflict'; end if;
 if command='cast_claim' then
 select * into j from public.cast_jobs where family_id=fid and visual_revision=revision for update;
 if j.id is null or j.state='ready' or j.next_retry_at>now() or (j.state='processing' and j.claim_expires_at>now()) then raise exception 'Claim conflict'; end if;
 newclaim:=gen_random_uuid(); update public.cast_jobs set state='processing',attempts=attempts+1,claim_id=newclaim,claim_expires_at=now()+interval '30 minutes',updated_at=now(),next_retry_at=null where id=j.id;
 return jsonb_build_object('claimId',newclaim);
 elsif command='cast_complete' then
 if not exists(select 1 from public.cast_jobs where family_id=fid and visual_revision=revision and claim_id=claim and state='processing' and claim_expires_at>now()) then raise exception 'Claim conflict'; end if;
 if object_path not like fid::text||'/%' or jsonb_typeof(missing)<>'array' then raise exception 'Invalid asset'; end if;
 insert into public.cast_versions(family_id,visual_revision,object_path,missing) values(fid,revision,object_path,missing);
 update public.cast_jobs set state='ready',claim_id=null,claim_expires_at=null,last_error=null,next_retry_at=null,updated_at=now() where family_id=fid and visual_revision=revision;
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

-- Called at the start and end of each scheduled cast run. Expired claims are recovered
-- transactionally; the former claim can no longer publish. Queued work is never counted ready.
create or replace function public.runner_cast_queue() returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 update public.cast_jobs j set state='failed',claim_id=null,claim_expires_at=null,
 last_error='Worker claim expired; automatic retry scheduled',updated_at=now(),next_retry_at=now()
 from public.families f where j.family_id=f.id and j.visual_revision=f.visual_revision
 and f.deleted_at is null and j.state='processing' and j.claim_expires_at<=now();
 select jsonb_build_object(
 'pending',count(*) filter(where j.state<>'ready'),
 'due',coalesce(jsonb_agg(jsonb_build_object('familyId',j.family_id,'revision',j.visual_revision,
 'attempts',j.attempts,'queuedAt',j.created_at)) filter(where j.state in ('queued','failed')
 and (j.next_retry_at is null or j.next_retry_at<=now())),'[]'::jsonb),
 'retrying',count(*) filter(where j.state='failed' and j.next_retry_at>now()),
 'processing',count(*) filter(where j.state='processing'),
 'overdue',count(*) filter(where j.state<>'ready' and j.created_at<now()-interval '2 hours')
 ) into result from public.cast_jobs j join public.families f on f.id=j.family_id
 and f.visual_revision=j.visual_revision where f.deleted_at is null
 and f.id not in ('a558ec80-f1ee-4094-9bc2-689d0e54f063'::uuid,
 '94c3f471-bd68-4390-89fe-74b250b40754'::uuid,'e47f2cc4-c03b-4537-a08a-729c94fe41cf'::uuid);
 return result;
end $$;
revoke all on function public.runner_cast_queue() from public,anon,authenticated;
grant execute on function public.runner_cast_queue() to service_role;
