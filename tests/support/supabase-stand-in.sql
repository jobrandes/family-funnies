-- Minimal stand-in for the parts of Supabase the migrations rely on (roles, auth.jwt(),
-- storage tables). For disposable test databases only; never run against a real project.
create schema auth; create schema storage;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
grant usage on schema auth,storage to anon,authenticated,service_role; grant execute on function auth.jwt() to anon,authenticated,service_role;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets,name text,created_at timestamptz default now(),unique(bucket_id,name));
alter table storage.objects enable row level security;
grant select,insert,delete on storage.objects to anon,authenticated; grant all on storage.objects to service_role;
