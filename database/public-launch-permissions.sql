-- Family owners can start reviewed production. Anonymous visitors cannot.
revoke execute on function public.enable_production(uuid) from anon;
