-- Migration: 20261125233000_fix_account_exists_fuzzy_matching.sql
-- Fix account_exists to support users whose phone or email was linked after initial signup
-- and handle national vs international dialing format variations (+91 9876543210 vs 9876543210).

create or replace function public.account_exists(p_identifier text)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_input  text := lower(trim(coalesce(p_identifier, '')));
  v_digits text;
  v_found  boolean := false;
begin
  if v_input = '' then
    return false;
  end if;

  if position('@' in v_input) > 0 then
    select exists (
      select 1
        from auth.users u
       where lower(u.email) = v_input
         and (u.email_confirmed_at is not null or u.confirmed_at is not null)
      union
      select 1
        from public.users p
       where lower(p.email) = v_input
    ) into v_found;
  else
    v_digits := regexp_replace(v_input, '[^0-9]', '', 'g');
    if length(v_digits) < 6 then
      return false;
    end if;

    select exists (
      select 1
        from auth.users u
       where (
         regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') = v_digits
         or (
           length(v_digits) >= 10
           and length(regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g')) >= 10
           and right(regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g'), 10) = right(v_digits, 10)
         )
       )
       and (
         u.phone_confirmed_at is not null
         or u.confirmed_at is not null
         or u.email_confirmed_at is not null
       )
      union
      select 1
        from public.users p
       where (
         regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') = v_digits
         or (
           length(v_digits) >= 10
           and length(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g')) >= 10
           and right(regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g'), 10) = right(v_digits, 10)
         )
       )
    ) into v_found;
  end if;

  return v_found;
end;
$$;

revoke all on function public.account_exists(text) from public;
grant execute on function public.account_exists(text) to anon, authenticated;

comment on function public.account_exists(text) is
  'Login pre-flight: true when an auth user or registered profile owns this email or phone. Returns a bare boolean.';
