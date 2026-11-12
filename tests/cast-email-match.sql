-- Database integration test for database/cast-email-match.sql. Run with an
-- administrative connection; all synthetic fixtures roll back.
begin;
insert into family_private.identity_providers(issuer,audience) values('https://match-test.invalid','match-test');
create function pg_temp.sign_in(who text,email text,verified boolean default true) returns void language sql as $$
 select set_config('request.jwt.claims',json_build_object('sub',who,'iss','https://match-test.invalid','aud','match-test','email',email,'email_verified',verified)::text,true) $$;
create function pg_temp.expect_error(statement text,expected text) returns void language plpgsql as $$ begin
 begin execute statement; exception when others then
  if sqlerrm<>expected then raise exception 'Expected "%" but got "%" for: %',expected,sqlerrm,statement; end if; return; end;
 raise exception 'No error raised for: %',statement;
end $$;
create function pg_temp.pending() returns bigint language sql as $$ select count(*) from public.my_family_matches() $$;
select pg_temp.sign_in('owner','owner@match-test.invalid');
set local role anon;
select set_config('test.family',public.begin_family('Shared fixture')::text,true);
select set_config('test.private',public.begin_family('Private fixture')::text,true);
with p as(insert into public.people(family_id,name) values(current_setting('test.family')::uuid,'Dad') returning id) select set_config('test.dad',id::text,true) from p;
with p as(insert into public.people(family_id,name) values(current_setting('test.family')::uuid,'Aunt') returning id) select set_config('test.aunt',id::text,true) from p;
with p as(insert into public.people(family_id,name,kind) values(current_setting('test.family')::uuid,'Rex','pet') returning id) select set_config('test.pet',id::text,true) from p;
insert into public.people(family_id,name) values(current_setting('test.private')::uuid,'Secret person');

-- Validation and ownership.
select pg_temp.expect_error(format('select public.set_member_email(%L,%L)',current_setting('test.dad'),'not-an-email'),'Enter a valid email address');
select pg_temp.expect_error(format('select public.set_member_email(%L,%L)',current_setting('test.pet'),'rex@match-test.invalid'),'Only people can be matched to an account');
select public.set_member_email(current_setting('test.dad')::uuid,'  Dad@Match-Test.Invalid ');
select pg_temp.expect_error(format('select public.set_member_email(%L,%L)',current_setting('test.aunt'),'dad@match-test.invalid'),'That email is already on another cast member in this family');
do $$ declare r record; begin
 select * into r from public.list_member_emails(current_setting('test.family')::uuid);
 if r.email<>'dad@match-test.invalid' or r.status<>'waiting' then raise exception 'Owner list wrong: %',r; end if;
 if pg_temp.pending()<>0 then raise exception 'Owner offered their own family'; end if;
end $$;

-- Nobody but the matching verified email sees or can use the match.
reset role;
select set_config('test.match',(select id::text from family_private.member_matches),true);
set local role anon;
select pg_temp.sign_in('stranger','stranger@match-test.invalid');
do $$ begin if pg_temp.pending()<>0 then raise exception 'Stranger sees a match'; end if; end $$;
select pg_temp.expect_error(format('select public.accept_family_match(%L)',current_setting('test.match')),'Invitation unavailable');
select pg_temp.expect_error(format('select public.decline_family_match(%L)',current_setting('test.match')),'Invitation unavailable');
select pg_temp.expect_error(format('select * from public.list_member_emails(%L)',current_setting('test.family')),'Owner required');
select pg_temp.expect_error(format('select public.set_member_email(%L,%L)',current_setting('test.dad'),'stranger@match-test.invalid'),'Owner required');
do $$ begin
 begin perform 1 from family_private.member_matches; raise exception 'Private match table readable';
 exception when insufficient_privilege then null; end;
end $$;
-- An unverified account claiming Dad's email gets nothing.
select pg_temp.sign_in('impostor','dad@match-test.invalid',false);
do $$ begin if pg_temp.pending()<>0 then raise exception 'Unverified email matched'; end if; end $$;
select pg_temp.expect_error(format('select public.accept_family_match(%L)',current_setting('test.match')),'Verified sign-in required');

-- Dad: offered exactly the one family, joins as a reader, sees comics only.
select pg_temp.sign_in('dad','DAD@match-test.invalid');
do $$ declare r record; begin
 if pg_temp.pending()<>1 then raise exception 'Dad not offered his family'; end if;
 select * into r from public.my_family_matches();
 if r.family_name<>'Shared fixture' or r.cast_name<>'Dad' then raise exception 'Wrong offer: %',r; end if;
 if (select count(*) from public.families)<>0 then raise exception 'Family visible before accepting'; end if;
end $$;
select public.accept_family_match(current_setting('test.match')::uuid);
do $$ begin
 if (select array_agg(name) from public.reader_families()) is distinct from array['Shared fixture'] then raise exception 'Dad sees the wrong families'; end if;
 if (select count(*) from public.families)<>0 then raise exception 'Reader can read family notes'; end if;
 if (select role from public.family_memberships where actor_id like '%|dad')<>'reader' then raise exception 'Dad is not a reader'; end if;
 if (select count(*) from public.people)<>0 then raise exception 'Reader can see profiles'; end if;
 if pg_temp.pending()<>0 then raise exception 'Accepted match still offered'; end if;
end $$;
select pg_temp.expect_error(format('select public.accept_family_match(%L)',current_setting('test.match')),'Invitation unavailable');
select pg_temp.sign_in('owner','owner@match-test.invalid');
do $$ begin if (select status from public.list_member_emails(current_setting('test.family')::uuid))<>'joined' then raise exception 'Owner does not see joined'; end if; end $$;

-- Decline: remembered across remove and re-add, and hidden from the owner.
select public.set_member_email(current_setting('test.aunt')::uuid,'aunt@match-test.invalid');
reset role;
select set_config('test.aunt_match',(select id::text from family_private.member_matches where email='aunt@match-test.invalid'),true);
set local role anon;
select pg_temp.sign_in('aunt','aunt@match-test.invalid');
select public.decline_family_match(current_setting('test.aunt_match')::uuid);
do $$ begin if pg_temp.pending()<>0 then raise exception 'Declined match still offered'; end if; end $$;
select pg_temp.expect_error(format('select public.accept_family_match(%L)',current_setting('test.aunt_match')),'Invitation unavailable');
select pg_temp.sign_in('owner','owner@match-test.invalid');
do $$ begin if (select status from public.list_member_emails(current_setting('test.family')::uuid) where email like 'aunt%')<>'waiting' then raise exception 'Decline leaked to owner'; end if; end $$;
select public.set_member_email(current_setting('test.aunt')::uuid,'');
select public.set_member_email(current_setting('test.aunt')::uuid,'aunt@match-test.invalid');
select pg_temp.sign_in('aunt','aunt@match-test.invalid');
do $$ begin if pg_temp.pending()<>0 then raise exception 'Re-adding an email nags after a decline'; end if; end $$;

-- Trashed families offer nothing; removing the cast member removes the match.
select pg_temp.sign_in('owner','owner@match-test.invalid');
with p as(insert into public.people(family_id,name) values(current_setting('test.private')::uuid,'Cousin') returning id) select set_config('test.cousin',id::text,true) from p;
select public.set_member_email(current_setting('test.cousin')::uuid,'cousin@match-test.invalid');
select public.trash_family(current_setting('test.private')::uuid,'Private fixture');
select pg_temp.sign_in('cousin','cousin@match-test.invalid');
do $$ begin if pg_temp.pending()<>0 then raise exception 'Trashed family offered'; end if; end $$;
select pg_temp.sign_in('owner','owner@match-test.invalid');
select public.restore_family(current_setting('test.private')::uuid);
select public.remove_cast_member(current_setting('test.cousin')::uuid,'Cousin');
select pg_temp.sign_in('cousin','cousin@match-test.invalid');
do $$ begin if pg_temp.pending()<>0 then raise exception 'Match outlived its cast member'; end if; end $$;
select 'PASS: owner-only email, verified-email matching, reader-only join, one family only, private declines, no nagging, trash and removal' as result;
rollback;
