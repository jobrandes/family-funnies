-- Per-family ceilings so one family cannot exhaust the free database or storage
-- allowance. Generous for real households; they exist to stop runaway or abusive
-- use. Depends on foundation.sql and family-management.sql. Apply once.
begin;
create function family_private.enforce_family_cap() returns trigger
language plpgsql security definer set search_path='' as $$
declare cap int:=tg_argv[0]::int; total bigint;
begin
 -- Serialise inserts per family so two simultaneous requests cannot both pass.
 perform 1 from public.families where id=new.family_id for update;
 execute format('select count(*) from public.%I where family_id=$1',tg_table_name) into total using new.family_id;
 if total>=cap then raise exception '%',tg_argv[1] using errcode='23514'; end if;
 return new;
end $$;
revoke all on function family_private.enforce_family_cap() from public;
create trigger people_cap before insert on public.people for each row
 execute function family_private.enforce_family_cap('30','This family has reached its limit of 30 people and pets.');
create trigger moments_cap before insert on public.story_moments for each row
 execute function family_private.enforce_family_cap('500','The story jar is full (500 moments). Remove some older ones to add more.');

-- Stored reference files: 30 cast members x 6 photos, plus headroom for files
-- awaiting cleanup. Counted in storage itself, so uploads that never get a
-- profile row are limited too.
create function family_private.reference_room(fid uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select fid is not null and (select count(*) from storage.objects o
  where o.bucket_id='family-references' and o.name like fid::text||'/%')<200
$$;
revoke all on function family_private.reference_room(uuid) from public;
grant execute on function family_private.reference_room(uuid) to anon,authenticated;
alter policy reference_upload on storage.objects
 with check(bucket_id='family-references'
  and family_private.member_role(family_private.path_family(name)) in ('owner','contributor')
  and family_private.reference_room(family_private.path_family(name)));
commit;
