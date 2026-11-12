-- Firebase signs and Supabase verifies each JWT before Postgres sees it.
-- Tokens without an optional `role` claim run as `anon`; that name does NOT
-- mean an unauthenticated visitor is allowed through these membership checks.
-- Access still requires actor(): trusted issuer + audience + verified email,
-- and the same per-family owner/contributor/reader predicates as before.
begin;
grant usage on schema family_private to anon;
grant execute on function family_private.actor(),family_private.member_role(uuid),family_private.path_family(text) to anon;
grant select on public.families,public.family_memberships,public.people,public.reference_photos,
 public.story_moments,public.cast_versions,public.cast_jobs,public.episodes,public.family_audit to anon;
grant insert,update,delete on public.people,public.reference_photos,public.story_moments to anon;
grant update(name,boundaries,relationships,tone,cast_notes) on public.families to anon;

alter policy families_read on public.families to anon,authenticated;
alter policy families_edit on public.families to anon,authenticated;
alter policy memberships_read on public.family_memberships to anon,authenticated;
alter policy people_read on public.people to anon,authenticated;
alter policy people_edit on public.people to anon,authenticated;
alter policy photos_read on public.reference_photos to anon,authenticated;
alter policy photos_edit on public.reference_photos to anon,authenticated;
alter policy moments_read on public.story_moments to anon,authenticated;
alter policy moments_edit on public.story_moments to anon,authenticated;
alter policy casts_read on public.cast_versions to anon,authenticated;
alter policy jobs_read on public.cast_jobs to anon,authenticated;
alter policy episodes_read on public.episodes to anon,authenticated;
alter policy audit_read on public.family_audit to anon,authenticated;
alter policy reference_download on storage.objects to anon,authenticated;
alter policy reference_upload on storage.objects to anon,authenticated;
alter policy reference_delete on storage.objects to anon,authenticated;
alter policy comic_download on storage.objects to anon,authenticated;

-- These private routines validate actor and family role before any mutation.
grant execute on function family_private.create_family(text),
 family_private.create_invitation(uuid,text,text),family_private.accept_invitation(text),
 family_private.revoke_invitation(uuid),family_private.list_invitations(uuid),
 family_private.approve_cast(uuid),family_private.pause_production(uuid) to anon;
grant execute on function public.create_family(text),
 public.create_invitation(uuid,text,text),public.accept_invitation(text),
 public.revoke_invitation(uuid),public.list_invitations(uuid),
 public.approve_cast(uuid),public.pause_production(uuid),public.enable_production(uuid) to anon;
-- No grants on private records, runner commands, episode jobs, permit records,
-- cast/episode writes, membership writes, or privileged production operations.
-- Keep the owner-checked privileged operation in the private schema; expose
-- only an invoker wrapper, consistent with the other guarded client RPCs.
alter function public.enable_production(uuid) set schema family_private;
create function public.enable_production(fid uuid) returns void
language sql security invoker set search_path='' as $$
 select family_private.enable_production(fid)
$$;
revoke all on function public.enable_production(uuid) from public;
grant execute on function public.enable_production(uuid) to anon,authenticated,service_role;
commit;
