-- Synthetic identities only, transaction rolled back. The gateway's signature
-- verification is separate; these tests exercise Postgres after verification.
begin;
insert into family_private.identity_providers(issuer,audience) values('https://instant-access-test.invalid','instant-access-test');
select set_config('request.jwt.claims','{"sub":"new-owner","iss":"https://instant-access-test.invalid","aud":"instant-access-test","email_verified":true}',true);
set local role anon;
select set_config('test.family',public.create_family('Instant access fixture')::text,true);
with p as(insert into public.people(family_id,name) values(current_setting('test.family')::uuid,'Synthetic person') returning id)
select set_config('test.person',id::text,true) from p;
insert into public.reference_photos(family_id,person_id,object_path,position) values(current_setting('test.family')::uuid,current_setting('test.person')::uuid,current_setting('test.family')||'/fixture.png',0);
do $$begin
 if (select count(*) from public.families where id=current_setting('test.family')::uuid)<>1 then raise exception 'Verified user cannot read own family';end if;
 if family_private.member_role(current_setting('test.family')::uuid)<>'owner' then raise exception 'Owner missing';end if;
 if has_function_privilege('anon','public.runner_command(text,uuid,bigint,uuid,date,text,text,text,jsonb)','EXECUTE') then raise exception 'Runner exposed';end if;
 if has_table_privilege('anon','family_private.media_permits','SELECT') then raise exception 'Permits exposed';end if;
end$$;
select set_config('request.jwt.claims','{"sub":"outsider","iss":"https://instant-access-test.invalid","aud":"instant-access-test","email_verified":true}',true);
do $$begin
 if exists(select 1 from public.families) or exists(select 1 from public.people) or exists(select 1 from public.reference_photos) or exists(select 1 from public.episodes) then raise exception 'Cross-family access';end if;
 if exists(select 1 from storage.objects where bucket_id in ('family-comics','family-references')) then raise exception 'Cross-family storage';end if;
 begin perform public.enable_production(current_setting('test.family')::uuid);raise exception 'Outsider enabled production';exception when raise_exception then if sqlerrm<>'Owner required' then raise;end if;end;
end$$;
select set_config('request.jwt.claims','{"sub":"new-owner","iss":"https://instant-access-test.invalid","aud":"instant-access-test","email_verified":false}',true);
do $$begin
 if family_private.actor() is not null or exists(select 1 from public.families) then raise exception 'Unverified access';end if;
 begin perform public.create_family('Must fail');raise exception 'Unverified created family';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claims','{"sub":"new-owner","iss":"https://untrusted.invalid","aud":"instant-access-test","email_verified":true}',true);
do $$begin if family_private.actor() is not null or exists(select 1 from public.families) then raise exception 'Wrong issuer access';end if;end$$;
select set_config('request.jwt.claims','{"sub":"new-owner","iss":"https://instant-access-test.invalid","aud":"wrong-audience","email_verified":true}',true);
do $$begin if family_private.actor() is not null then raise exception 'Wrong audience access';end if;end$$;
select set_config('request.jwt.claims','{}',true);
do $$begin
 if family_private.actor() is not null or exists(select 1 from public.families) then raise exception 'Anonymous access';end if;
 begin perform public.create_family('Must fail');raise exception 'Anonymous created family';exception when insufficient_privilege then null;end;
end$$;
reset role;
select 'PASS: verified account without role claim, create/read family, people/photos, outsider isolation, storage isolation, unverified/anonymous/wrong issuer/audience denied, runner/permit access denied' as result;
rollback;
