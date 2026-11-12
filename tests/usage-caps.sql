-- Database integration test for database/usage-caps.sql. Run with an
-- administrative connection; all synthetic fixtures roll back.
begin;
insert into family_private.identity_providers(issuer,audience) values('https://caps-test.invalid','caps-test');
select set_config('request.jwt.claims','{"sub":"owner","iss":"https://caps-test.invalid","aud":"caps-test","email_verified":true}',true);
set local role anon;
select set_config('test.family',public.begin_family('Caps fixture')::text,true);
select set_config('test.other',public.begin_family('Other fixture')::text,true);
insert into public.people(family_id,name) select current_setting('test.family')::uuid,'Person '||n from generate_series(1,30) n;
insert into public.story_moments(family_id,text) select current_setting('test.family')::uuid,'Moment '||n from generate_series(1,500) n;
insert into storage.objects(bucket_id,name) select 'family-references',current_setting('test.family')||'/file-'||n from generate_series(1,200) n;
do $$ begin
 begin insert into public.people(family_id,name) values(current_setting('test.family')::uuid,'One too many'); raise exception 'People cap not enforced';
 exception when check_violation then if sqlerrm<>'This family has reached its limit of 30 people and pets.' then raise; end if; end;
 begin insert into public.story_moments(family_id,text) values(current_setting('test.family')::uuid,'One too many'); raise exception 'Story cap not enforced';
 exception when check_violation then if sqlerrm not like 'The story jar is full%' then raise; end if; end;
 begin insert into storage.objects(bucket_id,name) values('family-references',current_setting('test.family')||'/one-too-many'); raise exception 'Storage cap not enforced';
 exception when insufficient_privilege then null; end;
end $$;
-- Caps are per family, and removing something frees room again.
insert into public.people(family_id,name) values(current_setting('test.other')::uuid,'Unaffected');
insert into public.story_moments(family_id,text) values(current_setting('test.other')::uuid,'Unaffected');
insert into storage.objects(bucket_id,name) values('family-references',current_setting('test.other')||'/unaffected');
delete from public.story_moments where family_id=current_setting('test.family')::uuid and text='Moment 1';
insert into public.story_moments(family_id,text) values(current_setting('test.family')::uuid,'Fits again');
delete from storage.objects where name=current_setting('test.family')||'/file-1';
insert into storage.objects(bucket_id,name) values('family-references',current_setting('test.family')||'/fits-again');
-- The cap does not open uploads to non-members.
select set_config('request.jwt.claims','{"sub":"stranger","iss":"https://caps-test.invalid","aud":"caps-test","email_verified":true}',true);
do $$ begin
 begin insert into storage.objects(bucket_id,name) values('family-references',current_setting('test.other')||'/intruder'); raise exception 'Stranger upload allowed';
 exception when insufficient_privilege then null; end;
 begin insert into storage.objects(bucket_id,name) values('family-references','not-a-family/intruder'); raise exception 'Malformed path upload allowed';
 exception when insufficient_privilege then null; end;
end $$;
select 'PASS: people, story and stored-file caps; per-family scope; room freed on removal; non-members still denied' as result;
rollback;
