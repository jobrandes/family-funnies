create table family_private.media_permits (
 token_hash text primary key check(length(token_hash)=64),
 bucket text not null check(bucket in ('family-references','family-comics')),
 object_path text not null,
 operation text not null check(operation in ('upload','download')),
 expires_at timestamptz not null check(expires_at <= now()+interval '35 minutes'),
 used_at timestamptz,
 check(object_path ~ '^[0-9a-f-]{36}/')
);
alter table family_private.media_permits enable row level security;
revoke all on family_private.media_permits from public,anon,authenticated;
create function public.consume_media_permit(token text, requested_operation text) returns jsonb language plpgsql security definer set search_path='' as $$
declare p family_private.media_permits;
begin
 update family_private.media_permits set used_at=now()
 where token_hash=encode(sha256(convert_to(token,'UTF8')),'hex') and operation=requested_operation and used_at is null and expires_at>now()
 returning * into p;
 if p.token_hash is null then raise exception 'Invalid or expired transfer permission'; end if;
 return jsonb_build_object('bucket',p.bucket,'path',p.object_path);
end $$;
revoke all on function public.consume_media_permit(text,text) from public,anon,authenticated;
grant execute on function public.consume_media_permit(text,text) to service_role;
