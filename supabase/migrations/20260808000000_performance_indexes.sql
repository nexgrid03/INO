-- ============================================================================
-- INO Migration: 20260808000000_performance_indexes.sql
-- Production Scale Indexing & Query Acceleration
-- ============================================================================

BEGIN;

-- 1. Reminders Table Indexes
CREATE INDEX IF NOT EXISTS idx_reminders_user_created 
  ON public.reminders (auth_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reminders_user_completed_due 
  ON public.reminders (auth_user_id, completed, due_date);

CREATE INDEX IF NOT EXISTS idx_reminders_user_category 
  ON public.reminders (auth_user_id, category);

-- 2. Notes Table Indexes
CREATE INDEX IF NOT EXISTS idx_notes_user_created 
  ON public.notes (auth_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notes_user_category 
  ON public.notes (auth_user_id, category);

-- 3. Expenses Table Indexes
CREATE INDEX IF NOT EXISTS idx_expenses_user_date 
  ON public.expenses (auth_user_id, expense_date DESC);

CREATE INDEX IF NOT EXISTS idx_expenses_user_category 
  ON public.expenses (auth_user_id, category);

-- 4. Shares & View-Once Token Lookup Indexes
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'document_shares' AND table_schema = 'public') THEN
    CREATE INDEX IF NOT EXISTS idx_document_shares_share_id ON public.document_shares (share_id);
    CREATE INDEX IF NOT EXISTS idx_document_shares_owner_created ON public.document_shares (owner_id, created_at DESC);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'view_once_shares' AND table_schema = 'public') THEN
    CREATE INDEX IF NOT EXISTS idx_view_once_token ON public.view_once_shares (token);
    CREATE INDEX IF NOT EXISTS idx_view_once_owner_created ON public.view_once_shares (owner_id, created_at DESC);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'user_qr_codes' AND table_schema = 'public') THEN
    CREATE INDEX IF NOT EXISTS idx_user_qr_codes_user ON public.user_qr_codes (auth_user_id);
  END IF;
END $$;

-- 5. Family Vaults Indexes
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'family_members' AND table_schema = 'public') THEN
    CREATE INDEX IF NOT EXISTS idx_family_members_vault_user ON public.family_members (vault_id, auth_user_id);
    CREATE INDEX IF NOT EXISTS idx_family_members_user ON public.family_members (auth_user_id);
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'family_documents' AND table_schema = 'public') THEN
    CREATE INDEX IF NOT EXISTS idx_family_documents_vault_created ON public.family_documents (vault_id, created_at DESC);
  END IF;
END $$;

-- 6. Built-in Wallet Tables Indexes (Compound User + Category / Created)
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
    'w_cards_wallet',
    'w_password_vault'
  ];
BEGIN
  FOREACH w_table IN ARRAY w_tables LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = w_table AND table_schema = 'public') THEN
      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = w_table AND table_schema = 'public' AND column_name = 'created_at') THEN
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I (auth_user_id, created_at DESC);', w_table || '_usr_crt_idx', w_table);
      END IF;
      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = w_table AND table_schema = 'public' AND column_name = 'category') THEN
        EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I (auth_user_id, category);', w_table || '_usr_cat_idx', w_table);
      END IF;
    END IF;
  END LOOP;
END $$;

COMMIT;
