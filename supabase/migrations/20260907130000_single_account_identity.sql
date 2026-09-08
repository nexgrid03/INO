-- ============================================================================
-- One account, two identifiers.
--
-- Supabase Auth keys an account by email OR phone. Until now the app called
-- signInWithOtp(..., shouldCreateUser: true) on both channels, so signing up
-- with an email and later "logging in" with a phone silently MINTED A SECOND
-- ACCOUNT - two auth.users rows, two public.users rows, two separate vaults.
--
-- Signup now asks which channel to verify - email or mobile - and confirms that
-- one. It becomes the account's login credential, and the app says so plainly
-- before the code is sent. The other identifier is stored on the profile as
-- contact detail only; it is NOT a login, because an unconfirmed identifier
-- would be a credential anyone who claimed that address or number could use.
-- Login passes shouldCreateUser:false, so it can never create anything - typing
-- the unverified identifier gets "no account, sign up first" rather than a new
-- empty account. This migration is the database half.
--
-- NON-DESTRUCTIVE. It deletes nothing and rewrites no existing row. Existing
-- accounts keep working through whichever identifier their auth user already
-- carries; see the note at the bottom for what they can and cannot do.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Does an account already exist for this identifier?   [REQUIRED]
--
-- This is the one piece the login screen actually calls. Without it every
-- login attempt fails before it reaches Supabase Auth.
--
-- Reads auth.users, not public.users: auth.users is what actually decides
-- whether Supabase can send a code with shouldCreateUser:false, and it stays
-- correct even if a signup was interrupted before its profile row was written.
-- Answering from public.users would be worse than useless - it would report
-- "yes" for a phone that is only contact info, and the OTP send would then fail
-- with "user not found".
--
-- SECURITY DEFINER because anon must be able to call it from the login screen,
-- and anon cannot read auth.users. It deliberately returns ONLY a boolean - no
-- name, no masked address, nothing that turns a probe into a data leak.
--
-- Privacy note: this is, by design, a user-enumeration oracle - "does this
-- number have an INO account" is answerable by anyone who can reach the API.
-- That is inherent to the requested UX (tell people to sign up first rather
-- than silently creating an account). Supabase's per-IP API rate limits are
-- the mitigation; if that ever proves too weak, gate this behind a captcha or
-- a short-lived signed token from the app.
-- ----------------------------------------------------------------------------
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
         and u.email_confirmed_at is not null
    ) into v_found;
  else
    -- Compare digits only, so "+91 98765 43210", "+919876543210" and
    -- "919876543210" all resolve to the same account.
    v_digits := regexp_replace(v_input, '[^0-9]', '', 'g');
    if length(v_digits) < 6 then
      return false;
    end if;
    select exists (
      select 1
        from auth.users u
       where regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') = v_digits
         and u.phone_confirmed_at is not null
    ) into v_found;
  end if;

  return v_found;
end;
$$;

revoke all on function public.account_exists(text) from public;
grant execute on function public.account_exists(text) to anon, authenticated;

comment on function public.account_exists(text) is
  'Login pre-flight: true when a confirmed auth user already owns this email or '
  'phone. Returns a bare boolean by design - never echoes account details.';

-- ----------------------------------------------------------------------------
-- 1b. Is this identifier already spoken for by ANY account?   [REQUIRED]
--
-- Deliberately a different question from account_exists(), and the difference
-- is the whole reason both exist:
--
--   account_exists()    - "can Supabase send a code here?"  Reads auth.users
--                         only, because that is what decides whether an OTP
--                         with shouldCreateUser:false will work. Used by LOGIN.
--   identifier_taken()  - "is this already someone's?"  Reads auth.users AND
--                         public.users. Used by SIGNUP.
--
-- Signup picks ONE channel to verify, so the other identifier is written to
-- public.users and never reaches auth.users. Asking account_exists() about it
-- would answer "free" for an address that is already on someone's profile - and
-- public.users has a unique index on email, so the duplicate would surface as a
-- failed INSERT *after* the code was verified and the auth user created. That
-- leaves a real account with no profile row, which is the worst possible place
-- for a signup to break.
--
-- Never use this one for the login pre-flight: it says yes for identifiers
-- Supabase cannot actually deliver a code to.
-- ----------------------------------------------------------------------------
create or replace function public.identifier_taken(p_identifier text)
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

  -- An identifier that can already receive a code is certainly taken.
  if public.account_exists(v_input) then
    return true;
  end if;

  if position('@' in v_input) > 0 then
    select exists (
      select 1 from public.users u
       where lower(u.email) = v_input
    ) into v_found;
  else
    v_digits := regexp_replace(v_input, '[^0-9]', '', 'g');
    if length(v_digits) < 6 then
      return false;
    end if;
    select exists (
      select 1 from public.users u
       where regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') = v_digits
    ) into v_found;
  end if;

  return v_found;
end;
$$;

revoke all on function public.identifier_taken(text) from public;
grant execute on function public.identifier_taken(text) to anon, authenticated;

comment on function public.identifier_taken(text) is
  'Signup pre-flight: true when this email or phone is already on any account, '
  'in auth.users OR public.users. Not a substitute for account_exists() - this '
  'says yes for identifiers that cannot receive a login code.';

-- ----------------------------------------------------------------------------
-- 2. One profile row per identifier.   [SAFETY NET]
--
-- A hard guarantee that the split-account bug cannot come back. Not required
-- for login to work.
--
-- Existing data may already violate it - that is exactly what the old bug
-- produced - and a plain CREATE UNIQUE INDEX would abort the whole script on
-- the first duplicate. So each index is attempted only when the column is
-- already clean, and otherwise raises a WARNING naming the duplicates. Running
-- this file can therefore never fail on legacy data; re-run it after resolving
-- any duplicates and the index will be created then.
-- ----------------------------------------------------------------------------
do $$
declare
  v_dupes text;
begin
  select string_agg(lower(email) || ' (x' || n || ')', ', ')
    into v_dupes
    from (
      select lower(email) as email, count(*) as n
        from public.users
       where email is not null and email <> ''
       group by lower(email)
      having count(*) > 1
    ) d;

  if v_dupes is null then
    create unique index if not exists users_email_unique_idx
      on public.users (lower(email))
      where email is not null and email <> '';
  else
    raise warning
      'users_email_unique_idx NOT created - these emails appear on more than '
      'one profile row: %. Resolve them, then re-run this migration.', v_dupes;
  end if;
end
$$;

do $$
declare
  v_dupes text;
begin
  select string_agg(digits || ' (x' || n || ')', ', ')
    into v_dupes
    from (
      select regexp_replace(phone, '[^0-9]', '', 'g') as digits, count(*) as n
        from public.users
       where phone is not null and phone <> ''
       group by regexp_replace(phone, '[^0-9]', '', 'g')
      having count(*) > 1
    ) d;

  if v_dupes is null then
    create unique index if not exists users_phone_unique_idx
      on public.users (regexp_replace(phone, '[^0-9]', '', 'g'))
      where phone is not null and phone <> '';
  else
    raise warning
      'users_phone_unique_idx NOT created - these numbers appear on more than '
      'one profile row: %. Resolve them, then re-run this migration.', v_dupes;
  end if;
end
$$;

-- ============================================================================
-- What this means for accounts that already exist
--
-- An account created before this change has only ONE identifier attached to its
-- auth user - whichever channel it signed up through. So:
--
--   • Logging in with that identifier works exactly as before.
--   • Logging in with the other one is told "no account found, create one
--     first" - correct, because Supabase genuinely cannot send a code to an
--     identifier its auth user does not carry.
--   • Trying to sign up again is refused ("that email already has an INO
--     account"), so the old duplicate-account path stays closed.
--
-- Accounts created from now on confirm both identifiers and can use either.
-- To retrofit an existing account, the owner has to prove the second
-- identifier with an OTP - there is no safe way to attach an unverified one,
-- because attaching it would hand anyone who claims that address or number a
-- working login credential.
-- ============================================================================
