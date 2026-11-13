-- Synthetic fixtures and every mutation are rolled back by the surrounding transaction.
begin;
do $$
declare fid uuid; rev bigint; c uuid; old_c uuid; q jsonb; i integer;
begin
 insert into public.families(name) values('Synthetic retry test') returning id,visual_revision into fid,rev;
 insert into public.cast_jobs(family_id,visual_revision) values(fid,rev);
 c:=(public.runner_command('cast_claim',fid,rev)->>'claimId')::uuid;
 perform public.runner_command('cast_fail',fid,rev,c);
 if not exists(select 1 from public.cast_jobs where family_id=fid and state='failed' and next_retry_at>now()) then raise exception 'Retry not scheduled';end if;
 begin perform public.runner_command('cast_claim',fid,rev);raise exception 'Early retry allowed';
 exception when raise_exception then if sqlerrm<>'Claim conflict' then raise;end if;end;
 for i in 1..4 loop
  update public.cast_jobs set next_retry_at=now()-interval '1 second' where family_id=fid;
  c:=(public.runner_command('cast_claim',fid,rev)->>'claimId')::uuid;
  perform public.runner_command('cast_fail',fid,rev,c);
 end loop;
 if (select attempts from public.cast_jobs where family_id=fid)<>5 then raise exception 'Retries stopped at three';end if;
 update public.cast_jobs set next_retry_at=null where family_id=fid;
 old_c:=(public.runner_command('cast_claim',fid,rev)->>'claimId')::uuid;
 update public.cast_jobs set claim_expires_at=now()-interval '1 second' where family_id=fid;
 q:=public.runner_cast_queue();
 if not exists(select 1 from jsonb_array_elements(q->'due') d where d->>'familyId'=fid::text) then raise exception 'Expired claim lost';end if;
 c:=(public.runner_command('cast_claim',fid,rev)->>'claimId')::uuid;
 begin perform public.runner_command(command=>'cast_complete',fid=>fid,revision=>rev,claim=>old_c,object_path=>fid||'/fake.png');raise exception 'Expired worker published';
 exception when raise_exception then if sqlerrm<>'Claim conflict' then raise;end if;end;
 perform public.runner_command(command=>'cast_complete',fid=>fid,revision=>rev,claim=>c,object_path=>fid||'/synthetic.png');
 if not exists(select 1 from public.cast_jobs where family_id=fid and state='ready' and next_retry_at is null and last_error is null) then raise exception 'Completion not clean';end if;
 begin perform public.runner_command('cast_claim',fid,rev);raise exception 'Ready job repeated';
 exception when raise_exception then if sqlerrm<>'Claim conflict' then raise;end if;end;
 if has_function_privilege('anon','public.runner_cast_queue()','execute') or has_function_privilege('authenticated','public.runner_cast_queue()','execute') then raise exception 'Queue exposed';end if;
 if exists(select 1 from public.cast_versions where family_id=fid and approved_at is not null) or (select production_enabled from public.families where id=fid) then raise exception 'Review bypassed';end if;
end $$;
select 'PASS: backoff, >3 retries, expired recovery, stale claim rejection, completion, duplicate and privacy guards' result;
rollback;
