-- Keep the last approved cast running while additive/photo updates await review.
-- Explicit pause and sensitive cast removals/name/kind/memorial changes still stop production.
alter table public.episode_jobs add column approved_cast_id uuid references public.cast_versions(id);
CREATE OR REPLACE FUNCTION family_private.visual_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare fid uuid; must_pause boolean:=false;
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
 if tg_table_name='people' then
  if tg_op='DELETE' then must_pause:=true;
  elsif tg_op='UPDATE' then must_pause:=(new.name,new.kind,new.memorial) is distinct from (old.name,old.kind,old.memorial);
  end if;
 end if;
 update public.families set visual_revision=visual_revision+1,
 production_enabled=case when must_pause then false else production_enabled end where id=fid;
 insert into public.cast_jobs(family_id,visual_revision) select id,visual_revision from public.families where id=fid on conflict do nothing;
 return null;
end $function$;

CREATE OR REPLACE FUNCTION family_private.cast_notes_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin
 if new.cast_notes is distinct from old.cast_notes then
   new.visual_revision:=old.visual_revision+1;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.runner_command(command text, fid uuid, revision bigint, claim uuid DEFAULT NULL::uuid, target_day date DEFAULT NULL::date, object_path text DEFAULT NULL::text, title text DEFAULT NULL::text, script text DEFAULT NULL::text, missing jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f public.families; j public.cast_jobs; e public.episode_jobs; newclaim uuid; active_cast uuid;
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
 select c.id into active_cast from public.cast_versions c where c.family_id=fid
 and c.approved_at is not null and c.missing='[]'::jsonb order by c.approved_at desc,c.created_at desc limit 1;
 if not f.production_enabled or active_cast is null then raise exception 'Production paused or cast review pending'; end if;
 if target_day<>(now() at time zone 'America/Los_Angeles')::date then raise exception 'Wrong production date'; end if;
 if exists(select 1 from public.episodes where family_id=fid and day=target_day) then raise exception 'Episode exists'; end if;
 if command='episode_claim' then
 select * into e from public.episode_jobs where family_id=fid and day=target_day for update;
 if e.id is not null and e.state='processing' and e.expires_at>now() then raise exception 'Claim conflict'; end if;
 newclaim:=gen_random_uuid(); insert into public.episode_jobs(family_id,day,visual_revision,claim_id,approved_cast_id) values(fid,target_day,revision,newclaim,active_cast) on conflict(family_id,day) do update set visual_revision=revision,claim_id=newclaim,approved_cast_id=active_cast,state='processing',expires_at=now()+interval '30 minutes';
 return jsonb_build_object('claimId',newclaim,'approvedCastId',active_cast);
 elsif command='episode_complete' then
 if not exists(select 1 from public.episode_jobs where family_id=fid and day=target_day and claim_id=claim and visual_revision=revision and state='processing' and expires_at>now() and approved_cast_id=active_cast) then raise exception 'Claim conflict'; end if;
 if object_path not like fid::text||'/%' then raise exception 'Invalid asset'; end if;
 insert into public.episodes(family_id,day,title,script,object_path) values(fid,target_day,title,script,object_path);
 update public.episode_jobs set state='ready' where family_id=fid and day=target_day;
 return '{}'::jsonb;
 else raise exception 'Unknown command'; end if;
end $function$;

revoke all on function public.runner_command(text,uuid,bigint,uuid,date,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.runner_command(text,uuid,bigint,uuid,date,text,text,text,jsonb) to service_role;
