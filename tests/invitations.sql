-- Run after foundation.sql and invitations.sql; all fixtures roll back.
begin;
insert into family_private.identity_providers(issuer,audience) values('https://test.invalid','test-app');
select set_config('request.jwt.claims','{"sub":"owner","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
set local role authenticated;
select set_config('test.family',public.create_family('Invitation test')::text,true);
select set_config('test.invite',public.create_invitation(current_setting('test.family')::uuid,'contributor',repeat('a',64))::text,true);
do $$ begin
 begin perform public.create_invitation(current_setting('test.family')::uuid,'owner',repeat('b',64));raise exception 'Owner invitation allowed';exception when raise_exception then if sqlerrm<>'Invalid invitation role' then raise;end if;end;
end $$;
select set_config('request.jwt.claims','{"sub":"new-member","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
select public.accept_invitation(repeat('a',64));
do $$ begin
 if family_private.member_role(current_setting('test.family')::uuid)<>'contributor' then raise exception 'Wrong role assigned';end if;
 begin perform public.create_invitation(current_setting('test.family')::uuid,'reader',repeat('b',64));raise exception 'Contributor can invite';exception when insufficient_privilege then null;end;
 begin perform public.revoke_invitation(current_setting('test.invite')::uuid);raise exception 'Contributor can revoke';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims','{"sub":"another-member","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
do $$ begin
 begin perform public.accept_invitation(repeat('a',64));raise exception 'Replay allowed';exception when raise_exception then if sqlerrm<>'Invitation unavailable' then raise;end if;end;
 begin perform public.list_invitations(current_setting('test.family')::uuid);raise exception 'Outsider sees invites';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims','{"sub":"owner","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
select public.create_invitation(current_setting('test.family')::uuid,'reader',repeat('b',64));
select public.create_invitation(current_setting('test.family')::uuid,'reader',repeat('c',64));
select public.revoke_invitation((select id from public.list_invitations(current_setting('test.family')::uuid) where id<>current_setting('test.invite')::uuid order by id limit 1));
reset role;
update family_private.invitations set expires_at=now()-interval '1 second' where token_hash=encode(sha256(convert_to(repeat('b',64),'UTF8')),'hex');
update family_private.invitations set revoked_at=now() where token_hash=encode(sha256(convert_to(repeat('c',64),'UTF8')),'hex');
select set_config('request.jwt.claims','{"sub":"another-member","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.accept_invitation(repeat('b',64));raise exception 'Expired invite accepted';exception when raise_exception then if sqlerrm<>'Invitation unavailable' then raise;end if;end;
 begin perform public.accept_invitation(repeat('c',64));raise exception 'Revoked invite accepted';exception when raise_exception then if sqlerrm<>'Invitation unavailable' then raise;end if;end;
end $$;
reset role;
-- Check owner-only review, missing members and stale revisions.
insert into public.cast_versions(family_id,visual_revision,object_path) select id,visual_revision,id::text||'/cast.png' from public.families where id=current_setting('test.family')::uuid;
select set_config('test.cast',(select id::text from public.cast_versions where family_id=current_setting('test.family')::uuid),true);
select set_config('request.jwt.claims','{"sub":"new-member","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.approve_cast(current_setting('test.cast')::uuid);raise exception 'Contributor can approve';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claims','{"sub":"owner","iss":"https://test.invalid","aud":"test-app","email_verified":true,"role":"authenticated"}',true);
select public.approve_cast(current_setting('test.cast')::uuid);
insert into public.people(family_id,name) values(current_setting('test.family')::uuid,'Changed visual');
do $$ begin
 begin perform public.approve_cast(current_setting('test.cast')::uuid);raise exception 'Stale cast approved';exception when raise_exception then if sqlerrm<>'Cast needs an update before approval' then raise;end if;end;
end $$;
reset role;
select 'PASS: invite role restrictions, acceptance, replay denial, contributor denial, outsider privacy, expired/revoked denial, owner-only cast approval, stale cast denial' as result;
rollback;
