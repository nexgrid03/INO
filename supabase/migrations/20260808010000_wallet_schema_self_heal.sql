-- ============================================================================
-- INO Migration: 20260808010000_wallet_schema_self_heal.sql
-- Production Self-Healing & Wallet Core Schema Synchronization
-- ============================================================================

BEGIN;

-- 1. Redefine ino_create_wallet_table to guarantee all 13 core columns on existing tables
CREATE OR REPLACE FUNCTION public.ino_create_wallet_table(p_table text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  -- 1) Create table skeleton if it does not exist
  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS public.%1$I (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid()
    )
  $ddl$, p_table);

  -- 2) Guarantee all 13 core columns exist (self-healing for pre-existing or partially created tables)
  EXECUTE format($ddl$
    ALTER TABLE public.%1$I
      ADD COLUMN IF NOT EXISTS auth_user_id  uuid DEFAULT auth.uid()
                                            REFERENCES auth.users (id) ON DELETE CASCADE,
      ADD COLUMN IF NOT EXISTS name          text,
      ADD COLUMN IF NOT EXISTS category      text,
      ADD COLUMN IF NOT EXISTS record_number text,
      ADD COLUMN IF NOT EXISTS status        text DEFAULT 'active',
      ADD COLUMN IF NOT EXISTS tags          text[] DEFAULT '{}',
      ADD COLUMN IF NOT EXISTS notes         text,
      ADD COLUMN IF NOT EXISTS is_favorite   boolean DEFAULT false,
      ADD COLUMN IF NOT EXISTS expires_at    date,
      ADD COLUMN IF NOT EXISTS file_path     text,
      ADD COLUMN IF NOT EXISTS created_at    timestamptz DEFAULT now(),
      ADD COLUMN IF NOT EXISTS updated_at    timestamptz DEFAULT now();
  $ddl$, p_table);

  -- Ensure column defaults align cleanly
  EXECUTE format($ddl$
    ALTER TABLE public.%1$I
      ALTER COLUMN status SET DEFAULT 'active',
      ALTER COLUMN tags SET DEFAULT '{}',
      ALTER COLUMN is_favorite SET DEFAULT false,
      ALTER COLUMN created_at SET DEFAULT now(),
      ALTER COLUMN updated_at SET DEFAULT now();
  $ddl$, p_table);

  -- 3) Create indexes on guaranteed core columns
  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS %1$I ON public.%2$I (auth_user_id, created_at DESC)',
    p_table || '_owner_created_idx', p_table);
  EXECUTE format(
    'CREATE INDEX IF NOT EXISTS %1$I ON public.%2$I (auth_user_id, expires_at) WHERE expires_at IS NOT NULL',
    p_table || '_owner_expiry_idx', p_table);

  -- 4) Enable RLS & recreate owner policies idempotently
  EXECUTE format('ALTER TABLE public.%1$I ENABLE ROW LEVEL SECURITY', p_table);

  EXECUTE format('DROP POLICY IF EXISTS %1$I ON public.%2$I', p_table || ': owner reads own',   p_table);
  EXECUTE format('DROP POLICY IF EXISTS %1$I ON public.%2$I', p_table || ': owner inserts own', p_table);
  EXECUTE format('DROP POLICY IF EXISTS %1$I ON public.%2$I', p_table || ': owner updates own', p_table);
  EXECUTE format('DROP POLICY IF EXISTS %1$I ON public.%2$I', p_table || ': owner deletes own', p_table);

  EXECUTE format(
    'CREATE POLICY %1$I ON public.%2$I FOR SELECT USING (auth_user_id = auth.uid())',
    p_table || ': owner reads own', p_table);
  EXECUTE format(
    'CREATE POLICY %1$I ON public.%2$I FOR INSERT WITH CHECK (auth_user_id = auth.uid())',
    p_table || ': owner inserts own', p_table);
  EXECUTE format(
    'CREATE POLICY %1$I ON public.%2$I FOR UPDATE USING (auth_user_id = auth.uid()) WITH CHECK (auth_user_id = auth.uid())',
    p_table || ': owner updates own', p_table);
  EXECUTE format(
    'CREATE POLICY %1$I ON public.%2$I FOR DELETE USING (auth_user_id = auth.uid())',
    p_table || ': owner deletes own', p_table);

  -- 5) Trigger for set_updated_at
  EXECUTE format('DROP TRIGGER IF EXISTS set_updated_at ON public.%1$I', p_table);
  EXECUTE format(
    'CREATE TRIGGER set_updated_at BEFORE UPDATE ON public.%1$I
       FOR EACH ROW EXECUTE FUNCTION public.tg_set_updated_at()',
    p_table);

  -- 6) Permissions
  EXECUTE format(
    'GRANT SELECT, INSERT, UPDATE, DELETE ON public.%1$I TO authenticated',
    p_table);
END;
$fn$;

-- 2. Redefine ino_rebuild_documents_view to guarantee all core columns exist before constructing view
CREATE OR REPLACE FUNCTION public.ino_rebuild_documents_view()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_rec record;
  v_sql text;
BEGIN
  -- Sweep all registered wallet tables and guarantee all 13 core columns exist
  FOR v_rec IN SELECT slug FROM public.wallets LOOP
    PERFORM public.ino_create_wallet_table(v_rec.slug);
  END LOOP;

  SELECT string_agg(
           format(
             'SELECT id, auth_user_id, %1$L::text AS wallet, name, category, '
             'record_number, status, tags, notes, is_favorite, expires_at, '
             'file_path, created_at, updated_at FROM public.%2$I',
             label, slug),
           E'\nUNION ALL\n' ORDER BY slug)
    INTO v_sql
  FROM public.wallets;

  IF v_sql IS NULL THEN
    RETURN;
  END IF;

  EXECUTE 'DROP VIEW IF EXISTS public.documents';
  EXECUTE 'CREATE VIEW public.documents WITH (security_invoker = on) AS ' || v_sql;
  EXECUTE 'GRANT SELECT ON public.documents TO authenticated, service_role';
END;
$fn$;

REVOKE ALL ON FUNCTION public.ino_rebuild_documents_view() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ino_rebuild_documents_view() TO service_role;

-- 3. Execute self-healing sweep across all existing wallets
DO $$
DECLARE
  v_rec record;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'wallets' AND table_schema = 'public') THEN
    FOR v_rec IN SELECT slug FROM public.wallets LOOP
      PERFORM public.ino_create_wallet_table(v_rec.slug);
    END LOOP;
  END IF;
END $$;

-- 4. Rebuild public.documents compatibility view
SELECT public.ino_rebuild_documents_view();

-- 5. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
