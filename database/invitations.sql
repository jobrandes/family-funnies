-- Single-use contributor/reader invites. Token plaintext is never stored.
create function family_private.create_invitation(fid uuid,member_role text,token text) returns uuid
language plpgsql security definer set search_path='' as $$
declare invitation_id uuid;
begin
 if family_private.actor() is null or family_private.member_role(fid) is distinct from 'owner' then
  raise exception 'Owner access required' using errcode='42501'; end if;
 if member_role not in ('reader','contributor') or member_role is null then raise exception 'Invalid invitation role'; end if;
 if token is null or token !~ '^[a-f0-9]{64}$' then raise exception 'Invalid invitation token'; end if;
 insert into family_private.invitations(family_id,role,token_hash,created_by)
 values(fid,member_role,encode(sha256(convert_to(token,'UTF8')),'hex'),family_private.actor()) returning id into invitation_id;
 insert into public.family_audit(family_id,actor_id,action) values(fid,family_private.actor(),'invitation.created');
 return invitation_id;
end $$;
create function family_private.accept_invitation(token text) returns uuid
language plpgsql security definer set search_path='' as $$
declare invitation family_private.invitations; actor text:=family_private.actor();
begin
 if actor is null then raise exception 'Verified sign-in required' using errcode='42501'; end if;
 if token is null or token !~ '^[a-f0-9]{64}$' then raise exception 'Invitation unavailable'; end if;
 select * into invitation from family_private.invitations
 where token_hash=encode(sha256(convert_to(token,'UTF8')),'hex') for update;
 if not found or invitation.used_at is not null or invitation.revoked_at is not null or invitation.expires_at<=now() then
  raise exception 'Invitation unavailable'; end if;
 if exists(select 1 from public.family_memberships where family_id=invitation.family_id and actor_id=actor) then
  raise exception 'You already belong to this family'; end if;
 insert into public.family_memberships(family_id,actor_id,role) values(invitation.family_id,actor,invitation.role);
 update family_private.invitations set used_at=now() where id=invitation.id;
 insert into public.family_audit(family_id,actor_id,action) values(invitation.family_id,actor,'invitation.accepted');
 return invitation.family_id;
end $$;
create function family_private.revoke_invitation(invitation_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare fid uuid;
begin
 select family_id into fid from family_private.invitations where id=invitation_id for update;
 if family_private.actor() is null or family_private.member_role(fid) is distinct from 'owner' then
  raise exception 'Owner access required' using errcode='42501'; end if;
 update family_private.invitations set revoked_at=now() where id=invitation_id;
 insert into public.family_audit(family_id,actor_id,action) values(fid,family_private.actor(),'invitation.revoked');
end $$;
create function family_private.list_invitations(fid uuid)
returns table(id uuid,role text,expires_at timestamptz,used_at timestamptz,revoked_at timestamptz)
language plpgsql security definer set search_path='' as $$ begin
 if family_private.actor() is null or family_private.member_role(fid) is distinct from 'owner' then
  raise exception 'Owner access required' using errcode='42501'; end if;
 return query select i.id,i.role,i.expires_at,i.used_at,i.revoked_at from family_private.invitations i where i.family_id=fid;
end $$;
create function family_private.approve_cast(cast_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare cast_row public.cast_versions; family_row public.families;
begin
 select * into cast_row from public.cast_versions where id=cast_id;
 if not found then raise exception 'Cast unavailable'; end if;
 select * into family_row from public.families where id=cast_row.family_id for update;
 if family_private.actor() is null or family_private.member_role(family_row.id) is distinct from 'owner' then
  raise exception 'Owner access required' using errcode='42501'; end if;
 if cast_row.visual_revision<>family_row.visual_revision or cast_row.missing<>'[]'::jsonb then
  raise exception 'Cast needs an update before approval'; end if;
 update public.cast_versions set approved_at=now(),approved_by=family_private.actor() where id=cast_id;
 insert into public.family_audit(family_id,actor_id,action) values(family_row.id,family_private.actor(),'cast.approved');
end $$;
-- Pause only until a trusted production runner is installed. No fake enabled state.
create function family_private.pause_production(fid uuid) returns void
language plpgsql security definer set search_path='' as $$ begin
 if family_private.actor() is null or family_private.member_role(fid) is distinct from 'owner' then
  raise exception 'Owner access required' using errcode='42501'; end if;
 update public.families set production_enabled=false where id=fid;
end $$;

revoke all on function family_private.create_invitation(uuid,text,text),family_private.accept_invitation(text),
 family_private.revoke_invitation(uuid),family_private.list_invitations(uuid),family_private.approve_cast(uuid),family_private.pause_production(uuid) from public;
grant execute on function family_private.create_invitation(uuid,text,text),family_private.accept_invitation(text),
 family_private.revoke_invitation(uuid),family_private.list_invitations(uuid),family_private.approve_cast(uuid),family_private.pause_production(uuid) to authenticated;
create function public.create_invitation(fid uuid,member_role text,token text) returns uuid language sql security invoker set search_path='' as $$ select family_private.create_invitation(fid,member_role,token) $$;
create function public.accept_invitation(token text) returns uuid language sql security invoker set search_path='' as $$ select family_private.accept_invitation(token) $$;
create function public.revoke_invitation(invitation_id uuid) returns void language sql security invoker set search_path='' as $$ select family_private.revoke_invitation(invitation_id) $$;
create function public.list_invitations(fid uuid) returns table(id uuid,role text,expires_at timestamptz,used_at timestamptz,revoked_at timestamptz) language sql security invoker set search_path='' as $$ select * from family_private.list_invitations(fid) $$;
create function public.approve_cast(cast_id uuid) returns void language sql security invoker set search_path='' as $$ select family_private.approve_cast(cast_id) $$;
create function public.pause_production(fid uuid) returns void language sql security invoker set search_path='' as $$ select family_private.pause_production(fid) $$;
revoke all on function public.create_invitation(uuid,text,text),public.accept_invitation(text),public.revoke_invitation(uuid),public.list_invitations(uuid),public.approve_cast(uuid),public.pause_production(uuid) from public;
grant execute on function public.create_invitation(uuid,text,text),public.accept_invitation(text),public.revoke_invitation(uuid),public.list_invitations(uuid),public.approve_cast(uuid),public.pause_production(uuid) to authenticated;
