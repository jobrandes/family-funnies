-- Database integration test. All synthetic fixtures and issuer config roll back.
begin;
insert into family_private.identity_providers(issuer,audience) values('https://test.invalid','test-app');
select set_config('request.jwt.claims','{"sub":"owner-a","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
set local role authenticated;
select set_config('test.family_a',public.create_family('Synthetic A')::text,true);
select set_config('request.jwt.claims','{"sub":"owner-b","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
select set_config('test.family_b',public.create_family('Synthetic B')::text,true);
insert into public.people(family_id,name) values(current_setting('test.family_b')::uuid,'Synthetic B person');
select set_config('request.jwt.claims','{"sub":"owner-a","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
insert into public.people(family_id,name) values(current_setting('test.family_a')::uuid,'Synthetic A person');
do $$ declare n int; v bigint; begin
 select count(*) into n from public.families; if n<>1 then raise exception 'Cross-family read leaked'; end if;
 select count(*) into n from public.people; if n<>1 then raise exception 'Cross-family people leaked'; end if;
 begin
  insert into public.people(family_id,name) values(current_setting('test.family_b')::uuid,'Attack');
  raise exception 'Cross-family insert allowed';
 exception when insufficient_privilege then null; end;
 begin
  update public.families set production_enabled=true where id=current_setting('test.family_a')::uuid;
  raise exception 'Direct production enable allowed';
 exception when insufficient_privilege then null; end;
 select visual_revision into v from public.families where id=current_setting('test.family_a')::uuid;
 update public.people set personality='Changed personality';
 if (select visual_revision from public.families where id=current_setting('test.family_a')::uuid)<>v then
  raise exception 'Personality incorrectly invalidated cast'; end if;
 update public.people set appearance='Changed appearance';
 if (select visual_revision from public.families where id=current_setting('test.family_a')::uuid)<>v+1 then
  raise exception 'Appearance did not invalidate cast'; end if;
 if not exists(select 1 from public.cast_jobs where family_id=current_setting('test.family_a')::uuid and visual_revision=v+1) then
  raise exception 'Appearance did not queue cast'; end if;
end $$;
reset role;
insert into public.family_memberships(family_id,actor_id,role) values
 (current_setting('test.family_a')::uuid,'https://test.invalid|reader','reader'),
 (current_setting('test.family_a')::uuid,'https://test.invalid|editor','contributor');
insert into public.episodes(family_id,day,title,script,object_path) values
 (current_setting('test.family_a')::uuid,'2000-01-01','Synthetic comic','Test only',current_setting('test.family_a')||'/test.png');
do $$ begin
 begin
  insert into public.episodes(family_id,day,title,script,object_path) values
  (current_setting('test.family_a')::uuid,'2000-01-01','Duplicate','Test',current_setting('test.family_a')||'/other.png');
  raise exception 'Duplicate daily comic allowed';
 exception when unique_violation then null; end;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"reader","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
do $$ declare n int; begin
 select count(*) into n from public.episodes; if n<>1 then raise exception 'Reader cannot read family comic'; end if;
 select count(*) into n from public.people; if n<>0 then raise exception 'Reader can read private profiles'; end if;
 select count(*) into n from public.cast_jobs; if n<>0 then raise exception 'Reader can read production jobs'; end if;
 begin
  insert into public.people(family_id,name) values(current_setting('test.family_a')::uuid,'Attack');
  raise exception 'Reader can create person';
 exception when insufficient_privilege then null; end;
 begin
  update public.family_memberships set role='owner' where actor_id='https://test.invalid|reader';
  raise exception 'Reader role escalation allowed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"editor","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
do $$ begin
 if (select count(*) from public.people)<>1 then raise exception 'Contributor missing own people'; end if;
 begin
  insert into public.family_memberships(family_id,actor_id,role) values(current_setting('test.family_a')::uuid,'attacker','owner');
  raise exception 'Contributor can manage members';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"owner-a","iss":"https://evil.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
do $$ begin
 if exists(select 1 from public.families) then raise exception 'Untrusted issuer allowed'; end if;
 begin perform public.create_family('Attack'); raise exception 'Untrusted creator allowed';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"owner-a","iss":"https://test.invalid","aud":"test-app","email_verified":false,"role":"authenticated"}',true);
do $$ begin
 if exists(select 1 from public.families) then raise exception 'Unverified email allowed'; end if;
end $$;
reset role;
set local role anon;
-- Since instant-verified-access.sql, Firebase tokens without a `role` claim run
-- as `anon`, so that role holds table grants. A visitor with no token must still
-- see and change nothing: every policy requires a verified actor().
select set_config('request.jwt.claims','',true);
do $$ declare n bigint; begin
 select (select count(*) from public.families)+(select count(*) from public.family_memberships)+(select count(*) from public.people)
  +(select count(*) from public.reference_photos)+(select count(*) from public.story_moments)+(select count(*) from public.cast_versions)
  +(select count(*) from public.cast_jobs)+(select count(*) from public.episodes)+(select count(*) from public.family_audit) into n;
 if n<>0 then raise exception 'Anonymous visitor can read % family rows',n; end if;
 begin insert into public.people(family_id,name) values(current_setting('test.family_a')::uuid,'Intruder'); raise exception 'Anonymous profile write allowed';
 exception when insufficient_privilege then null; end;
 update public.families set name='Defaced'; get diagnostics n=row_count; if n<>0 then raise exception 'Anonymous family edit allowed'; end if;
 delete from public.story_moments; get diagnostics n=row_count; if n<>0 then raise exception 'Anonymous delete allowed'; end if;
 begin perform public.create_family('Attack'); raise exception 'Anonymous creator allowed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: tenant isolation, cross-family writes, reader privacy, role escalation, contributor restrictions, visual invalidation, job queue, daily uniqueness, trusted issuer, verified email, anonymous denial' as result;
rollback;
