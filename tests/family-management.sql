begin;
insert into family_private.identity_providers(issuer,audience) values('https://management-test.invalid','management-test');
select set_config('request.jwt.claims','{"sub":"owner","iss":"https://management-test.invalid","aud":"management-test","email_verified":true}',true);
set local role anon;
select set_config('test.family',public.begin_family('Management fixture')::text,true);
do $$begin
 begin perform public.save_setup(current_setting('test.family')::uuid,3::smallint);raise exception 'Empty step allowed';exception when raise_exception then if sqlerrm<>'Add at least one person or pet' then raise;end if;end;
end$$;
with p as(insert into public.people(family_id,name) values(current_setting('test.family')::uuid,'Sample') returning id)select set_config('test.person',id::text,true) from p;
select public.save_setup(current_setting('test.family')::uuid,3::smallint);
do $$begin
 begin perform public.save_setup(current_setting('test.family')::uuid,4::smallint);raise exception 'Missing photos allowed';exception when raise_exception then if sqlerrm<>'Add a photo for every cast member' then raise;end if;end;
end$$;
insert into public.reference_photos(family_id,person_id,object_path,position)values(current_setting('test.family')::uuid,current_setting('test.person')::uuid,current_setting('test.family')||'/one',0),(current_setting('test.family')::uuid,current_setting('test.person')::uuid,current_setting('test.family')||'/two',1);
select public.save_setup(current_setting('test.family')::uuid,5::smallint);
reset role;
insert into public.cast_versions(family_id,visual_revision,object_path,approved_at,approved_by) select id,visual_revision,id::text||'/cast.png',now(),family_private.actor() from public.families where id=current_setting('test.family')::uuid;
select set_config('test.rev',(select visual_revision::text from public.families where id=current_setting('test.family')::uuid),true);
set local role anon;
select public.enable_production(current_setting('test.family')::uuid);
delete from public.reference_photos where family_id=current_setting('test.family')::uuid and position=1;
do $$begin if not exists(select 1 from public.families where id=current_setting('test.family')::uuid and visual_revision=current_setting('test.rev')::bigint and production_enabled) then raise exception 'Extra photo invalidated approval';end if;end$$;
select public.trash_family(current_setting('test.family')::uuid,'Management fixture');
do $$begin
 if exists(select 1 from public.families where id=current_setting('test.family')::uuid) or exists(select 1 from public.people where family_id=current_setting('test.family')::uuid) then raise exception 'Trash still visible';end if;
 if (select count(*) from public.list_family_trash())<>1 then raise exception 'Own trash missing';end if;
end$$;
select set_config('request.jwt.claims','{"sub":"outsider","iss":"https://management-test.invalid","aud":"management-test","email_verified":true}',true);
do $$begin
 if exists(select 1 from public.list_family_trash()) then raise exception 'Outsider sees trash';end if;
 begin perform public.restore_family(current_setting('test.family')::uuid);raise exception 'Outsider restored';exception when insufficient_privilege then null;end;
 begin perform public.remove_cast_member(current_setting('test.person')::uuid,'Sample');raise exception 'Outsider removed member';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claims','{"sub":"owner","iss":"https://management-test.invalid","aud":"management-test","email_verified":true}',true);
select public.restore_family(current_setting('test.family')::uuid);
do $$begin if not exists(select 1 from public.families where id=current_setting('test.family')::uuid and not production_enabled and onboarding_step=5) then raise exception 'Restore lost setup or started production';end if;end$$;
select public.remove_cast_member(current_setting('test.person')::uuid,'Sample');
do $$begin if exists(select 1 from public.people where id=current_setting('test.person')::uuid) then raise exception 'Member not removed';end if;end$$;
reset role;
select 'PASS: setup checkpoints, missing-photo gates, approved extra-photo removal, owner Trash/restore, outsider denial, member removal, no automatic production opt-in' as result;
rollback;
