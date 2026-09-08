-- Add optional reminder_date column to w_property_wallet table.
-- Allows users to schedule property due date/renewal reminders that sync directly to the Reminders system.

alter table public.w_property_wallet
  add column if not exists reminder_date timestamptz;

comment on column public.w_property_wallet.reminder_date is
  'Optional scheduled reminder timestamp for this property (e.g. tax due, lease renewal, EMI).';
