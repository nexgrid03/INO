-- Signup duplicate checks must follow confirmed Auth identifiers only.
--
-- identifier_taken() used to return true when the email or phone appeared on
-- public.users, even if that value was never confirmed in auth.users. Signup
-- stores the unverified contact channel on the profile, so the next attempt
-- to register it was rejected as "already registered" even though login could
-- not send a code there.
--
-- account_exists() is unchanged. It remains the definition of a verified
-- login identifier: confirmed email or confirmed phone on auth.users.

create or replace function public.identifier_taken(p_identifier text)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  return public.account_exists(p_identifier);
end;
$$;

revoke all on function public.identifier_taken(text) from public;
grant execute on function public.identifier_taken(text) to anon, authenticated;

comment on function public.identifier_taken(text) is
  'Signup pre-flight: true only when a confirmed auth user already owns this '
  'email or phone. Unverified contact values on public.users do not count.';
