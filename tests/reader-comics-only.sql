-- Database integration test for database/reader-comics-only.sql. Run with an
-- administrative connection; all synthetic fixtures roll back.
begin;
insert into family_private.identity_providers(issuer,audience) values('https://reader-test.invalid','reader-test');
create function pg_temp.sign_in(who text) returns void language sql as $$
 select set_config('request.jwt.claims',json_build_object('sub',who,'iss','https://reader-test.invalid','aud','reader-test','email_verified',true)::text,true) $$;
select pg_temp.sign_in('owner');
set local role anon;
select set_config('test.family',public.begin_family('Reader fixture')::text,true);
select set_config('test.other',public.begin_family('Unshared fixture')::text,true);
update public.families set boundaries='PRIVATE boundary',relationships='PRIVATE relationships',cast_notes='PRIVATE cast notes',tone='PRIVATE tone' where id=current_setting('test.family')::uuid;
insert into public.people(family_id,name) values(current_setting('test.family')::uuid,'Hidden person');
insert into public.story_moments(family_id,text) values(current_setting('test.family')::uuid,'Hidden moment');
reset role;
insert into public.family_memberships(family_id,actor_id,role) values
 (current_setting('test.family')::uuid,'https://reader-test.invalid|reader','reader'),
 (current_setting('test.family')::uuid,'https://reader-test.invalid|contributor','contributor');
insert into public.episodes(family_id,day,title,script,object_path) values
 (current_setting('test.family')::uuid,current_date-1,'Old strip','PRIVATE script',current_setting('test.family')||'/old.png'),
 (current_setting('test.family')::uuid,current_date,'New strip','PRIVATE script',current_setting('test.family')||'/new.png'),
 (current_setting('test.other')::uuid,current_date,'Other strip','PRIVATE script',current_setting('test.other')||'/x.png');
insert into storage.objects(bucket_id,name) values('family-comics',current_setting('test.family')||'/old.png'),('family-comics',current_setting('test.other')||'/x.png'),('family-references',current_setting('test.family')||'/ref');
set local role anon;

select pg_temp.sign_in('reader');
do $$ declare r record; n bigint; begin
 -- Sees the family on the shelf, by name, and only that family.
 if (select array_agg(name) from public.reader_families()) is distinct from array['Reader fixture'] then raise exception 'Reader shelf wrong'; end if;
 -- Reads every comic in the family, old and new, and nothing from other families.
 if (select array_agg(title order by day) from public.episodes) is distinct from array['Old strip','New strip'] then raise exception 'Reader comic archive wrong'; end if;
 if (select array_agg(name) from storage.objects) is distinct from array[current_setting('test.family')||'/old.png'] then raise exception 'Reader file access wrong'; end if;
 -- Cannot fetch private notes or scripts by any direct query.
 if (select count(*) from public.families)<>0 then raise exception 'Reader can read the family record and its notes'; end if;
 begin perform script from public.episodes; raise exception 'Reader can read comic scripts';
 exception when insufficient_privilege then null; end;
 begin perform * from public.episodes; raise exception 'Reader can select every comic column';
 exception when insufficient_privilege then null; end;
 if (select count(*) from public.people)+(select count(*) from public.story_moments)+(select count(*) from public.reference_photos)
   +(select count(*) from public.cast_versions)+(select count(*) from public.cast_jobs)+(select count(*) from public.family_audit)<>0 then raise exception 'Reader sees non-comic records'; end if;
 if (select count(*) from public.family_memberships)<>1 then raise exception 'Reader sees other members'; end if;
 -- Cannot change anything.
 update public.families set name='Defaced',boundaries='x'; get diagnostics n=row_count; if n<>0 then raise exception 'Reader edited the family'; end if;
 begin insert into public.people(family_id,name) values(current_setting('test.family')::uuid,'Intruder'); raise exception 'Reader added a person';
 exception when insufficient_privilege then null; end;
 begin insert into public.story_moments(family_id,text) values(current_setting('test.family')::uuid,'Intruder'); raise exception 'Reader added a story';
 exception when insufficient_privilege then null; end;
 begin insert into public.episodes(family_id,day,title,script,object_path) values(current_setting('test.family')::uuid,current_date+1,'Fake','x',current_setting('test.family')||'/f.png'); raise exception 'Reader added a comic';
 exception when insufficient_privilege then null; end;
 begin delete from public.episodes; raise exception 'Reader deleted comics';
 exception when insufficient_privilege then null; end;
 begin perform public.trash_family(current_setting('test.family')::uuid,'Reader fixture'); raise exception 'Reader trashed the family';
 exception when insufficient_privilege then null; end;
end $$;

-- Owner and contributor keep full access to the notes; scripts stay closed to every signed-in role.
select pg_temp.sign_in('contributor');
do $$ begin
 if (select boundaries from public.families)<>'PRIVATE boundary' then raise exception 'Contributor lost the family notes'; end if;
 if (select count(*) from public.reader_families())<>0 then raise exception 'Contributor listed as reader'; end if;
end $$;
select pg_temp.sign_in('owner');
do $$ begin
 if (select count(*) from public.families)<>2 or (select cast_notes from public.families where id=current_setting('test.family')::uuid)<>'PRIVATE cast notes' then raise exception 'Owner lost family access'; end if;
 if (select count(*) from (select id,family_id,day,title,object_path from public.episodes) e)<>3 then raise exception 'Owner lost comics'; end if;
 begin perform script from public.episodes; raise exception 'Scripts readable by a signed-in role';
 exception when insufficient_privilege then null; end;
end $$;
select pg_temp.sign_in('stranger');
do $$ begin if (select count(*) from public.reader_families())+(select count(*) from public.families)
 +(select count(*) from (select id from public.episodes) e)<>0 then raise exception 'Stranger sees something'; end if; end $$;
-- A trashed family leaves the reader's shelf.
select pg_temp.sign_in('owner');
select public.trash_family(current_setting('test.family')::uuid,'Reader fixture');
select pg_temp.sign_in('reader');
do $$ begin if (select count(*) from public.reader_families())+(select count(*) from (select id from public.episodes) e)<>0 then raise exception 'Trashed family still visible to reader'; end if; end $$;
select 'PASS: reader sees family name and full comic archive only; no notes, scripts, profiles or edits; owner and contributor unaffected' as result;
rollback;
