-- Readers get comics and nothing else. Before this, a reader's own session
-- could still fetch the family's private notes (humor boundaries, relationship
-- notes, tone, cast notes) and every comic's script straight from the Data API,
-- even though no screen showed them. Depends on foundation.sql,
-- instant-verified-access.sql and family-management.sql.
--
-- Deploy the app first, then apply this. App versions from before this change
-- stop listing reader families until the page is reloaded.
begin;
-- The family record carries private notes, so only people who may edit the
-- family's content can read it.
alter policy families_read on public.families
 using(family_private.member_role(id) in ('owner','contributor'));

-- What a reader needs to list a family on their shelf, and no more.
create function family_private.reader_families()
 returns table(id uuid,name text,visual_revision bigint,production_enabled boolean,onboarding_step smallint,timezone text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select f.id,f.name,f.visual_revision,f.production_enabled,f.onboarding_step,f.timezone,f.created_at
 from public.families f join public.family_memberships m on m.family_id=f.id
 where m.actor_id=family_private.actor() and m.role='reader' and f.deleted_at is null
$$;
create function public.reader_families()
 returns table(id uuid,name text,visual_revision bigint,production_enabled boolean,onboarding_step smallint,timezone text,created_at timestamptz)
language sql security invoker set search_path='' as $$ select * from family_private.reader_families() $$;
revoke all on function family_private.reader_families(),public.reader_families() from public;
grant execute on function family_private.reader_families(),public.reader_families() to anon,authenticated;

-- A comic's script is production input, not part of the finished comic. No
-- screen reads it, so no signed-in role may fetch it. The production worker
-- uses the service role and is unaffected.
revoke select on public.episodes from anon,authenticated;
grant select(id,family_id,day,title,object_path,created_at) on public.episodes to anon,authenticated;
commit;
