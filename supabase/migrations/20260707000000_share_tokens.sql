-- ============================================================================
-- INO — Short public share tokens (Google-Drive-style /s/{token} links)
-- ----------------------------------------------------------------------------
-- Adds a short, unguessable `token` to document_shares so public links can look
-- like  https://share.inoapp.in/s/a8f9x2k40b1c  instead of exposing the internal
-- share_id. 12 hex chars ≈ 48 bits of entropy; the token is what the QR/web use,
-- while share_id stays internal (used by RLS + the analytics FKs).
--
-- create_document_share() already does `returning *`, so it returns the new
-- token automatically — no function change needed.
--
-- Run with: supabase db push  (or paste into the SQL editor). Idempotent.
-- ============================================================================

alter table public.document_shares
  add column if not exists token text
  default substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);

-- Backfill any rows that predate the column (safety — the volatile default
-- already fills existing rows on most PG versions).
update public.document_shares
  set token = substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)
  where token is null;

alter table public.document_shares alter column token set not null;

-- Unique + fast lookup by token.
create unique index if not exists document_shares_token_key
  on public.document_shares (token);

notify pgrst, 'reload schema';
