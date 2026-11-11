-- Complete standalone workflow under real RLS. All synthetic data rolls back.
begin;
insert into family_private.identity_providers(issuer,audience) values('https://public-flow-test.invalid','public-flow-test');
select set_config('request.jwt.claims','{"sub":"owner","iss":"https://public-flow-test.invalid","aud":"public-flow-test","email_verified":true,"role":"authenticated"}',true);
set local role authenticated;
select set_config('test.family',public.create_family('Public flow test')::text,true);
with p as(insert into public.people(family_id,name) values(current_setting('test.family')::uuid,'Test cast member') returning id)
select set_config('test.person',id::text,true) from p;
insert into public.reference_photos(family_id,person_id,object_path,position)
values(current_setting('test.family')::uuid,current_setting('test.person')::uuid,current_setting('test.family')||'/test-reference.png',0);
do $$begin
 begin perform public.enable_production(current_setting('test.family')::uuid);raise exception 'Unreviewed cast allowed';
 exception when raise_exception then if sqlerrm<>'Approve the current complete cast first' then raise;end if;end;
end$$;
reset role;
select set_config('test.revision',(select visual_revision::text from public.families where id=current_setting('test.family')::uuid),true);
select set_config('test.claim',(public.runner_command('cast_claim',current_setting('test.family')::uuid,current_setting('test.revision')::bigint)->>'claimId'),true);
select public.runner_command(command=>'cast_complete',fid=>current_setting('test.family')::uuid,revision=>current_setting('test.revision')::bigint,claim=>current_setting('test.claim')::uuid,object_path=>current_setting('test.family')||'/test-cast.png');
select set_config('test.cast',(select id::text from public.cast_versions where family_id=current_setting('test.family')::uuid),true);
set local role authenticated;
select public.approve_cast(current_setting('test.cast')::uuid);
select public.enable_production(current_setting('test.family')::uuid);
reset role;
select set_config('test.episode_claim',(public.runner_command(command=>'episode_claim',fid=>current_setting('test.family')::uuid,revision=>current_setting('test.revision')::bigint,target_day=>(now() at time zone 'America/Los_Angeles')::date)->>'claimId'),true);
select public.runner_command(command=>'episode_complete',fid=>current_setting('test.family')::uuid,revision=>current_setting('test.revision')::bigint,claim=>current_setting('test.episode_claim')::uuid,target_day=>(now() at time zone 'America/Los_Angeles')::date,object_path=>current_setting('test.family')||'/test-episode.png',title=>'Synthetic flow test',script=>'Synthetic fixture; no comic generated.');
do $$begin
 if (select count(*) from public.episodes where family_id=current_setting('test.family')::uuid)<>1 then raise exception 'Episode missing';end if;
 begin perform public.runner_command(command=>'episode_claim',fid=>current_setting('test.family')::uuid,revision=>current_setting('test.revision')::bigint,target_day=>(now() at time zone 'America/Los_Angeles')::date);raise exception 'Duplicate allowed';
 exception when raise_exception then if sqlerrm<>'Episode exists' then raise;end if;end;
end$$;
select set_config('request.jwt.claims','{"sub":"outsider","iss":"https://public-flow-test.invalid","aud":"public-flow-test","email_verified":true,"role":"authenticated"}',true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.families where id=current_setting('test.family')::uuid) or exists(select 1 from public.episodes where family_id=current_setting('test.family')::uuid) or exists(select 1 from public.people where family_id=current_setting('test.family')::uuid) then raise exception 'Family privacy violated';end if;
 begin perform public.enable_production(current_setting('test.family')::uuid);raise exception 'Outsider started production';
 exception when raise_exception then if sqlerrm<>'Owner required' then raise;end if;end;
end$$;
reset role;
select 'PASS: signup identity, family creation, people, reference queue, review gate, cast claim/completion, owner approval/start, episode claim/completion, duplicate prevention, outsider isolation' result;
rollback;
