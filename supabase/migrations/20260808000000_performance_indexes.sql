-- ============================================================================
-- INO Migration: 20260808000000_performance_indexes.sql
-- Production Scale Indexing & Query Acceleration
-- ============================================================================

BEGIN;

-- 1. Reminders Table Indexes
CREATE INDEX IF NOT EXISTS idx_reminders_user_created 
  ON public.reminders (auth_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reminders_user_status_due 
  ON public.reminders (auth_user_id, status, due_date);

CREATE INDEX IF NOT EXISTS idx_reminders_user_category 
  ON public.reminders (auth_user_id, category);

-- 2. Notes Table Indexes
CREATE INDEX IF NOT EXISTS idx_notes_user_created 
  ON public.notes (auth_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notes_user_category 
  ON public.notes (auth_user_id, category);

-- 3. Expenses Table Indexes
CREATE INDEX IF NOT EXISTS idx_expenses_user_date 
  ON public.expenses (auth_user_id, date DESC);

CREATE INDEX IF NOT EXISTS idx_expenses_user_category 
  ON public.expenses (auth_user_id, category);

-- 4. Shares & View-Once Token Lookup Indexes
CREATE INDEX IF NOT EXISTS idx_shares_token 
  ON public.shares (token);

CREATE INDEX IF NOT EXISTS idx_shares_user_created 
  ON public.shares (auth_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_view_once_token 
  ON public.view_once_shares (token);

CREATE INDEX IF NOT EXISTS idx_view_once_user_created 
  ON public.view_once_shares (auth_user_id, created_at DESC);

-- 5. Family Vaults Indexes
CREATE INDEX IF NOT EXISTS idx_family_members_vault_user 
  ON public.family_members (vault_id, auth_user_id);

CREATE INDEX IF NOT EXISTS idx_family_members_user 
  ON public.family_members (auth_user_id);

CREATE INDEX IF NOT EXISTS idx_family_documents_vault_created 
  ON public.family_documents (vault_id, created_at DESC);

-- 6. QR Codes Indexes
CREATE INDEX IF NOT EXISTS idx_qr_codes_user_created 
  ON public.qr_codes (auth_user_id, created_at DESC);

-- 7. Built-in Wallet Tables Indexes (Compound User + Category / Expiry / Created)
DO $$
DECLARE
  w_table text;
  w_tables text[] := ARRAY[
    'w_identity_wallet',
    'w_document_wallet',
    'w_property_wallet',
    'w_insurance_wallet',
    'w_health_wallet',
    'w_investment_wallet',
    'w_banking_wallet',
    'w_password_vault'
  ];
BEGIN
  FOREACH w_table IN ARRAY w_tables LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = w_table AND table_schema = 'public') THEN
      EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I (auth_user_id, created_at DESC);', w_table || '_usr_crt_idx', w_table);
      EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I (auth_user_id, category);', w_table || '_usr_cat_idx', w_table);
    END IF;
  END LOOP;
END $$;

COMMIT;
