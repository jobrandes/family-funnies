-- Database integration test for database/trash-purge.sql. Run with an
-- administrative connection; all synthetic fixtures roll back.
begin;
insert into family_private.identity_providers(issuer,audience) values('https://purge-test.invalid','purge-test');
create function pg_temp.sign_in(who text) returns void language sql as $$
 select set_config('request.jwt.claims',json_build_object('sub',who,'iss','https://purge-test.invalid','aud','purge-test','email_verified',true)::text,true) $$;
create function pg_temp.expect_error(statement text,expected text) returns void language plpgsql as $$ begin
 begin execute statement; exception when others then
  if sqlerrm<>expected then raise exception 'Expected "%" but got "%" for: %',expected,sqlerrm,statement; end if; return; end;
 raise exception 'No error raised for: %',statement;
end $$;
select pg_temp.sign_in('owner');
set local role anon;
select set_config('test.family',public.begin_family('Purge fixture')::text,true);
select set_config('test.keep',public.begin_family('Keep fixture')::text,true);
with p as(insert into public.people(family_id,name) values(current_setting('test.family')::uuid,'Sample') returning id) select set_config('test.person',id::text,true) from p;
insert into public.reference_photos(family_id,person_id,object_path,position) values(current_setting('test.family')::uuid,current_setting('test.person')::uuid,current_setting('test.family')||'/ref-one',0);
insert into public.story_moments(family_id,text) values(current_setting('test.family')::uuid,'Synthetic moment');
insert into public.people(family_id,name) values(current_setting('test.keep')::uuid,'Keeper');
reset role;
-- Stored files: one referenced, one old orphan, one fresh orphan, one comic, one in the other family.
insert into storage.objects(bucket_id,name,created_at) values
 ('family-references',current_setting('test.family')||'/ref-one',now()-interval '2 hours'),
 ('family-references',current_setting('test.family')||'/old-orphan',now()-interval '2 hours'),
 ('family-references',current_setting('test.family')||'/fresh-upload',now()),
 ('family-comics',current_setting('test.family')||'/comic.png',now()-interval '2 hours'),
 ('family-references',current_setting('test.keep')||'/keep-orphan',now()-interval '2 hours');
insert into public.family_memberships(family_id,actor_id,role) values
 (current_setting('test.family')::uuid,'https://purge-test.invalid|contributor','contributor'),
 (current_setting('test.family')::uuid,'https://purge-test.invalid|reader','reader');
set local role anon;

-- Orphan listing: only the old unreferenced file, only for owner/contributor, only this family.
do $$ declare found text[]; begin
 select array_agg(path) into found from public.orphan_reference_files(current_setting('test.family')::uuid);
 if found is distinct from array[current_setting('test.family')||'/old-orphan'] then raise exception 'Wrong orphan list: %',found; end if;
end $$;
select pg_temp.sign_in('contributor');
do $$ begin if (select count(*) from public.orphan_reference_files(current_setting('test.family')::uuid))<>1 then raise exception 'Contributor orphan list wrong'; end if; end $$;
select pg_temp.expect_error(format('select * from public.orphan_reference_files(%L)',current_setting('test.keep')),'Contributor required');
select pg_temp.sign_in('reader');
select pg_temp.expect_error(format('select * from public.orphan_reference_files(%L)',current_setting('test.family')),'Contributor required');
select pg_temp.sign_in('stranger');
select pg_temp.expect_error(format('select * from public.orphan_reference_files(%L)',current_setting('test.family')),'Contributor required');

-- A live family cannot be purged or have its files listed through the trash path.
select pg_temp.sign_in('owner');
select pg_temp.expect_error(format('select * from public.list_trash_files(%L)',current_setting('test.family')),'Owner required');
select pg_temp.expect_error(format('select public.purge_family(%L,%L)',current_setting('test.family'),'Purge fixture'),'Owner required');

select public.trash_family(current_setting('test.family')::uuid,'Purge fixture');
-- Only the owner reaches a trashed family's files.
select pg_temp.sign_in('contributor');
select pg_temp.expect_error(format('select * from public.list_trash_files(%L)',current_setting('test.family')),'Owner required');
select pg_temp.expect_error(format('select public.purge_family(%L,%L)',current_setting('test.family'),'Purge fixture'),'Owner required');
do $$ begin if exists(select 1 from storage.objects) then raise exception 'Contributor can read trashed files'; end if; end $$;
select pg_temp.sign_in('stranger');
select pg_temp.expect_error(format('select public.purge_family(%L,%L)',current_setting('test.family'),'Purge fixture'),'Owner required');
do $$ declare n int; begin delete from storage.objects; get diagnostics n=row_count; if n<>0 then raise exception 'Stranger deleted % stored files',n; end if; end $$;

select pg_temp.sign_in('owner');
do $$ begin if (select count(*) from public.list_trash_files(current_setting('test.family')::uuid))<>4 then raise exception 'Trash file list wrong'; end if; end $$;
select pg_temp.expect_error(format('select public.purge_family(%L,%L)',current_setting('test.family'),'wrong name'),'Type the family name to confirm');
select pg_temp.expect_error(format('select public.purge_family(%L,%L)',current_setting('test.family'),'Purge fixture'),'Stored files remain. Try again.');
do $$ begin if not exists(select 1 from public.family_memberships where family_id=current_setting('test.family')::uuid) then raise exception 'Refused purge still deleted data'; end if; end $$;
-- The owner's own delete policy clears exactly the trashed family's files.
do $$ declare n int; begin delete from storage.objects where name like current_setting('test.family')||'/%'; get diagnostics n=row_count; if n<>4 then raise exception 'Owner removed % stored files, expected 4',n; end if; end $$;
select public.purge_family(current_setting('test.family')::uuid,'Purge fixture');
reset role;
do $$ declare fid uuid:=current_setting('test.family')::uuid; begin
 if exists(select 1 from public.families where id=fid) or exists(select 1 from public.family_memberships where family_id=fid)
  or exists(select 1 from public.people where family_id=fid) or exists(select 1 from public.reference_photos where family_id=fid)
  or exists(select 1 from public.story_moments where family_id=fid) or exists(select 1 from public.cast_jobs where family_id=fid)
  or exists(select 1 from public.family_audit where family_id=fid) then raise exception 'Purge left family records behind'; end if;
 if (select count(*) from public.people where family_id=current_setting('test.keep')::uuid)<>1
  or (select count(*) from storage.objects where name=current_setting('test.keep')||'/keep-orphan')<>1 then raise exception 'Purge touched another family'; end if;
end $$;
set local role anon;
do $$ begin if (select count(*) from public.list_family_trash())<>0 then raise exception 'Purged family still in Trash'; end if; end $$;
select pg_temp.expect_error(format('select public.purge_family(%L,%L)',current_setting('test.family'),'Purge fixture'),'Owner required');
rollback;
