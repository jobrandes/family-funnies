-- Permanent deletion for trashed families, and a retry path for stored photo
-- files that a browser failed to remove. Depends on foundation.sql and
-- family-management.sql only. Apply once, as a single transaction.
--
-- Stored files can only be removed through the Storage API, never by SQL, so
-- deletion is two-phase: the owner's browser empties the family's folder, then
-- purge_family() refuses to drop the family while any stored file remains.
begin;

-- Ownership that still holds while a family is in the Trash. member_role()
-- deliberately returns nothing for trashed families.
create function family_private.owns_trashed(fid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.family_memberships m join public.families f on f.id=m.family_id
  where m.family_id=fid and m.actor_id=family_private.actor() and m.role='owner' and f.deleted_at is not null)
$$;

-- Owners may read and remove stored files of their own trashed family. Live
-- families keep the existing, narrower policies.
create policy trashed_family_files_read on storage.objects for select to anon,authenticated
 using(bucket_id in ('family-references','family-comics') and family_private.owns_trashed(family_private.path_family(name)));
create policy trashed_family_files_delete on storage.objects for delete to anon,authenticated
 using(bucket_id in ('family-references','family-comics') and family_private.owns_trashed(family_private.path_family(name)));

create function family_private.list_trash_files(fid uuid) returns table(bucket text,path text)
language plpgsql stable security definer set search_path='' as $$ begin
 if fid is null or not family_private.owns_trashed(fid) then raise exception 'Owner required' using errcode='42501';end if;
 return query select o.bucket_id::text,o.name::text from storage.objects o
  where o.bucket_id in ('family-references','family-comics') and o.name like fid::text||'/%' order by o.name limit 500;
end $$;

create function family_private.purge_family(fid uuid,confirmation text) returns void
language plpgsql security definer set search_path='' as $$
declare f public.families;
begin
 select * into f from public.families where id=fid for update;
 if f.id is null or not family_private.owns_trashed(fid) then raise exception 'Owner required' using errcode='42501';end if;
 if confirmation is distinct from f.name then raise exception 'Type the family name to confirm';end if;
 if exists(select 1 from storage.objects o where o.bucket_id in ('family-references','family-comics') and o.name like fid::text||'/%') then
  raise exception 'Stored files remain. Try again.';end if;
 -- Every family-scoped table references families with on delete cascade.
 delete from public.families where id=fid;
end $$;

-- Stored reference files no profile points to: left behind when a browser
-- closed or lost its connection between removing a profile and its files.
-- The age floor protects an upload whose database row is about to be written.
create function family_private.orphan_reference_files(fid uuid) returns table(path text)
language plpgsql stable security definer set search_path='' as $$ begin
 if fid is null or family_private.member_role(fid) is null or family_private.member_role(fid) not in ('owner','contributor') then
  raise exception 'Contributor required' using errcode='42501';end if;
 return query select o.name::text from storage.objects o
  where o.bucket_id='family-references' and o.name like fid::text||'/%' and o.created_at<now()-interval '1 hour'
   and not exists(select 1 from public.reference_photos r where r.object_path=o.name) order by o.name limit 200;
end $$;

create function public.list_trash_files(fid uuid) returns table(bucket text,path text) language sql security invoker set search_path='' as $$ select * from family_private.list_trash_files(fid) $$;
create function public.purge_family(fid uuid,confirmation text) returns void language sql security invoker set search_path='' as $$ select family_private.purge_family(fid,confirmation) $$;
create function public.orphan_reference_files(fid uuid) returns table(path text) language sql security invoker set search_path='' as $$ select * from family_private.orphan_reference_files(fid) $$;

revoke all on function family_private.owns_trashed(uuid),family_private.list_trash_files(uuid),family_private.purge_family(uuid,text),family_private.orphan_reference_files(uuid) from public;
revoke all on function public.list_trash_files(uuid),public.purge_family(uuid,text),public.orphan_reference_files(uuid) from public;
grant execute on function family_private.owns_trashed(uuid),family_private.list_trash_files(uuid),family_private.purge_family(uuid,text),family_private.orphan_reference_files(uuid) to anon,authenticated;
grant execute on function public.list_trash_files(uuid),public.purge_family(uuid,text),public.orphan_reference_files(uuid) to anon,authenticated;
commit;
