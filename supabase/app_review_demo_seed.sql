-- ============================================================================
-- INO - App Store review demo account: sample data
-- ----------------------------------------------------------------------------
-- Fills the App Review demo account with realistic sample data so the reviewer
-- lands in a lived-in app instead of empty screens.
--
-- PREREQUISITES - this script does NOT create the login:
--   1. Supabase Dashboard -> Authentication -> Sign In / Providers -> Phone ->
--      "Test Phone Numbers and OTPs":   919000012345=482915
--      and set "Test OTPs Valid Until" at least a year out. No SMS is sent for
--      a test number; the code is always 482915.
--   2. The demo account exists in the app, and its auth user carries phone
--      919000012345 with profile name "INO Demo" - either signed up with
--      "Mobile OTP", or signed up with "Email OTP" and then given the phone by
--      the attach-phone step of the review runbook.
--
-- The auth user is created by the app on purpose. A hand-written INSERT into
-- auth.users / auth.identities depends on GoTrue internals and is the usual
-- cause of "Database error querying schema" at login; the in-app sign-up also
-- writes the profile row and the terms consent exactly as a real user gets.
--
-- RE-RUNNABLE - a "reset to demo state" to run before every submission. Each
-- run DELETES this account's reminders, notes, transactions, Password Vault
-- (back to first-time setup) and the file-less wallet rows, then re-inserts
-- the sample set. Wallet documents with a real uploaded file are kept. The
-- name guard refuses any account whose profile is not called v_demo_name, so
-- a typo in the number can never wipe a real user.
--
-- Dates are relative to today (IST), so the data never looks stale.
-- Paste into the Supabase SQL editor and Run.
-- ============================================================================

do $$
declare
  v_phone     text := '919000012345';  -- country code + number, digits only
  v_demo_name text := 'INO Demo';      -- must match the name used at sign-up
  v_uid       uuid;
  v_day       timestamp := date_trunc('day', now() at time zone 'Asia/Kolkata'); -- today 00:00 IST
begin
  select u.id into v_uid
    from auth.users u
   where regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') = v_phone;

  if v_uid is null then
    raise exception 'No account with phone +%. Sign up in the app with this number first.', v_phone;
  end if;

  if not exists (
    select 1 from public.users p
     where p.auth_user_id = v_uid and p.full_name = v_demo_name
  ) then
    raise exception 'Account +% is not named "%" - refusing to reset it.', v_phone, v_demo_name;
  end if;

  -- --------------------------------------------------------------------------
  -- Reset
  -- --------------------------------------------------------------------------
  delete from public.reminders where auth_user_id = v_uid;
  delete from public.notes     where auth_user_id = v_uid;
  delete from public.expenses  where auth_user_id = v_uid;

  -- Vault entries are encrypted on the device, so they cannot be seeded here.
  -- Clearing the key puts the vault back to "set up a passphrase", which the
  -- reviewer can complete themselves - no passphrase to hand over.
  delete from public.w_password_vault where auth_user_id = v_uid;
  delete from public.vault_keys       where auth_user_id = v_uid;

  delete from public.w_document_wallet  where auth_user_id = v_uid and file_path is null;
  delete from public.w_insurance_wallet where auth_user_id = v_uid and file_path is null;
  delete from public.w_health_wallet    where auth_user_id = v_uid and file_path is null;

  -- --------------------------------------------------------------------------
  -- Reminders (due_at is the exact moment; the trigger derives due_date)
  -- --------------------------------------------------------------------------
  insert into public.reminders
    (auth_user_id, title, subtitle, category, priority, due_at)
  values
    (v_uid, 'Annual health check-up',  'Full body check-up at City Hospital',  'health',    'normal',
       (v_day + interval '7 days 10 hours')  at time zone 'Asia/Kolkata'),
    (v_uid, 'Renew car insurance',     'Policy MTR-DEMO-771045 expires',       'insurance', 'important',
       (v_day + interval '12 days 11 hours') at time zone 'Asia/Kolkata'),
    (v_uid, 'Mom''s birthday',         'Order cake and flowers',               'birthdays', 'normal',
       (v_day + interval '20 days 9 hours')  at time zone 'Asia/Kolkata'),
    (v_uid, 'Pay property tax',        'Half-yearly municipal tax',            'property',  'important',
       (v_day + interval '30 days 10 hours') at time zone 'Asia/Kolkata'),
    (v_uid, 'Passport renewal',        'Book appointment at Passport Seva Kendra', 'documents', 'critical',
       (v_day + interval '45 days 10 hours') at time zone 'Asia/Kolkata');

  -- One finished item so the "completed" state is visible too. notified_at is
  -- stamped so the per-minute push job never fires for it.
  insert into public.reminders
    (auth_user_id, title, subtitle, category, priority, due_at, completed, completed_at, notified_at)
  values
    (v_uid, 'Pay electricity bill', 'Paid via UPI', 'custom', 'normal',
       (v_day - interval '3 days' + interval '10 hours') at time zone 'Asia/Kolkata',
       true, now() - interval '3 days', now());

  -- --------------------------------------------------------------------------
  -- Notes
  -- --------------------------------------------------------------------------
  insert into public.notes
    (auth_user_id, title, content, category, tags, is_pinned, is_favorite, created_at, updated_at)
  values
    (v_uid, 'Tax saving plan FY 2026-27',
       E'80C: PPF Rs 1,50,000 (deposit before March)\n80D: Health insurance premium Rs 25,000\nHRA: Collect rent receipts every quarter',
       'tax', '{tax,planning}', true, true, now() - interval '20 days', now() - interval '2 days'),
    (v_uid, 'Home loan documents checklist',
       E'- Sale deed copy\n- Encumbrance certificate\n- Last 6 months salary slips\n- Form 16 (2 years)',
       'property', '{loan}', false, false, now() - interval '15 days', now() - interval '15 days'),
    (v_uid, 'Family insurance summary',
       E'Health: Family floater, Rs 10 lakh cover, renews in 45 days\nCar: Comprehensive, renews in 12 days',
       'insurance', '{family}', false, true, now() - interval '10 days', now() - interval '5 days'),
    (v_uid, 'Doctor''s advice',
       E'Walk 30 minutes daily. Repeat blood test after 3 months.',
       'health', '{}', false, false, now() - interval '6 days', now() - interval '6 days');

  -- --------------------------------------------------------------------------
  -- Transactions (Transaction Vault)
  -- --------------------------------------------------------------------------
  insert into public.expenses
    (auth_user_id, title, amount, type, direction, category, payment_method, expense_date, vendor_name, gst_amount, reference)
  values
    (v_uid, 'Salary',                   85000.00, 'income',  'credited', 'salary',    'netBanking',
       (v_day - interval '12 days' + interval '9 hours')  at time zone 'Asia/Kolkata', 'Demo Technologies Pvt Ltd', null, null),
    (v_uid, 'House rent',               22000.00, 'expense', 'debited',  'rent',      'upi',
       (v_day - interval '11 days' + interval '10 hours') at time zone 'Asia/Kolkata', 'Landlord', null, null),
    (v_uid, 'Car loan EMI',             12500.00, 'expense', 'debited',  'loanEmi',   'netBanking',
       (v_day - interval '10 days' + interval '8 hours')  at time zone 'Asia/Kolkata', 'Demo Bank', null, 'EMI 14/60'),
    (v_uid, 'Health insurance premium', 18500.00, 'expense', 'debited',  'insurance', 'card',
       (v_day - interval '8 days' + interval '15 hours')  at time zone 'Asia/Kolkata', 'Demo Health Insurance', 2822.03, 'HLT-DEMO-482193'),
    (v_uid, 'Groceries',                 3450.50, 'expense', 'debited',  'food',      'upi',
       (v_day - interval '5 days' + interval '19 hours')  at time zone 'Asia/Kolkata', 'Fresh Mart', null, null),
    (v_uid, 'Electricity bill',          1840.00, 'expense', 'debited',  'utilities', 'upi',
       (v_day - interval '3 days' + interval '10 hours')  at time zone 'Asia/Kolkata', 'State Electricity Board', null, null),
    (v_uid, 'Flight tickets',            7600.00, 'expense', 'debited',  'travel',    'card',
       (v_day - interval '1 day' + interval '21 hours')   at time zone 'Asia/Kolkata', 'Demo Airlines', 365.00, null);

  -- --------------------------------------------------------------------------
  -- Wallet records (no file attached; consent = true as the app writes it)
  -- --------------------------------------------------------------------------
  insert into public.w_document_wallet
    (auth_user_id, name, category, record_number, expires_at, is_favorite, consent)
  values
    (v_uid, 'Rental Agreement - Flat 302', 'Agreement', 'RA-2026-0412', (v_day + interval '300 days')::date, true,  true),
    (v_uid, 'Vehicle RC - Car',            'Vehicle',   'TS09-DEMO-1234', null,                             false, true);

  insert into public.w_insurance_wallet
    (auth_user_id, name, category, record_number, expires_at, is_favorite, consent)
  values
    (v_uid, 'Family Health Insurance', 'Health', 'HLT-DEMO-482193', (v_day + interval '45 days')::date, true,  true),
    (v_uid, 'Car Insurance',           'Motor',  'MTR-DEMO-771045', (v_day + interval '12 days')::date, false, true);

  insert into public.w_health_wallet
    (auth_user_id, name, category, doctor_name, is_favorite, consent)
  values
    (v_uid, 'Blood Test Report',     'Lab Report',   'Dr. Ananya Rao',  false, true),
    (v_uid, 'Prescription - Fever',  'Prescription', 'Dr. Vikram Shah', false, true);

  raise notice 'Demo data loaded for account % (+%).', v_uid, v_phone;
end $$;

-- ----------------------------------------------------------------------------
-- Pre-submission check: the demo account still exists and is confirmed.
-- Run on its own before each App Store submission. Zero rows = re-do the
-- in-app sign-up (a reviewer may have tested Delete Account).
-- ----------------------------------------------------------------------------
-- select u.id, u.phone, u.phone_confirmed_at, p.full_name
--   from auth.users u
--   left join public.users p on p.auth_user_id = u.id
--  where regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g') = '919000012345';
