-- ============================================================================
-- INO Migration: 20260906010000_round7_security_remediation.sql
-- Critical Security Remediation - Round 7:
-- 1. Issue #1 (High): Prevent MFA Enforcement Self-Destruction on Wallet Rebuilds
--    - Exclude w_password_vault from generic wallet table factory and documents view
--    - Enforce CHECK constraint on public.wallets preventing w_password_vault registration
--    - Create idempotent public.ino_apply_password_vault_mfa_policies()
--    - Ensure ino_create_wallet_table, create_custom_wallet, and ino_rebuild_documents_view
--      never overwrite or degrade Password Vault MFA (AAL2) RLS policies
-- 2. Issue #2 (Critical): Prevent Unauthenticated Document Deletion
--    - Revoke execution on remove_vault_document & share_document_to_vault from PUBLIC and anon
--    - Grant execute strictly to authenticated, service_role
--    - Implement fail-closed authentication and caller validation in remove_vault_document
--    - Fix 3-valued logic (3VL) bypass: ensure auth.uid() is not null before comparison
-- ============================================================================

BEGIN;

-- ============================================================================
-- PART 1: ISSUE #1 - MFA ENFORCEMENT PROTECTION ACROSS ALL WALLET LIFECYCLES
-- ============================================================================

-- 1.1 Dedicated idempotent function to enforce MFA (AAL2) policies on w_password_vault
CREATE OR REPLACE FUNCTION public.ino_apply_password_vault_mfa_policies()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $fn$
BEGIN
  IF to_regclass('public.w_password_vault') IS NOT NULL THEN
    ALTER TABLE public.w_password_vault ENABLE ROW LEVEL SECURITY;

    -- Drop any permissive or legacy policies
    DROP POLICY IF EXISTS "w_password_vault: owner reads own" ON public.w_password_vault;
    DROP POLICY IF EXISTS "w_password_vault: owner inserts own" ON public.w_password_vault;
    DROP POLICY IF EXISTS "w_password_vault: owner updates own" ON public.w_password_vault;
    DROP POLICY IF EXISTS "w_password_vault: owner deletes own" ON public.w_password_vault;
    DROP POLICY IF EXISTS "w_password_vault: owner select" ON public.w_password_vault;
    DROP POLICY IF EXISTS "w_password_vault: owner insert" ON public.w_password_vault;
    DROP POLICY IF EXISTS "w_password_vault: owner update" ON public.w_password_vault;
    DROP POLICY IF EXISTS "w_password_vault: owner delete" ON public.w_password_vault;

    -- Recreate single unified policies enforcing ownership AND verified MFA (AAL2)
    CREATE POLICY "w_password_vault: owner reads own" ON public.w_password_vault
      FOR SELECT TO authenticated
      USING (auth.uid() = auth_user_id AND public.ino_is_aal2_satisfied());

    CREATE POLICY "w_password_vault: owner inserts own" ON public.w_password_vault
      FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = auth_user_id AND public.ino_is_aal2_satisfied());

    CREATE POLICY "w_password_vault: owner updates own" ON public.w_password_vault
      FOR UPDATE TO authenticated
      USING (auth.uid() = auth_user_id AND public.ino_is_aal2_satisfied())
      WITH CHECK (auth.uid() = auth_user_id AND public.ino_is_aal2_satisfied());

    CREATE POLICY "w_password_vault: owner deletes own" ON public.w_password_vault
      FOR DELETE TO authenticated
      USING (auth.uid() = auth_user_id AND public.ino_is_aal2_satisfied());
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.ino_apply_password_vault_mfa_policies() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ino_apply_password_vault_mfa_policies() TO authenticated, service_role;

-- 1.2 Purge w_password_vault from public.wallets registry if present
DELETE FROM public.wallets WHERE slug = 'w_password_vault';

-- 1.3 Add CHECK constraint on public.wallets ensuring w_password_vault can NEVER be added
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'wallets_no_password_vault_chk'
      AND conrelid = 'public.wallets'::regclass
  ) THEN
    ALTER TABLE public.wallets
      ADD CONSTRAINT wallets_no_password_vault_chk CHECK (slug <> 'w_password_vault');
  END IF;
END $$;

-- 1.4 Hardened ino_create_wallet_table: skips w_password_vault and reapplies MFA policies
CREATE OR REPLACE FUNCTION public.ino_create_wallet_table(p_table text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  -- Guard: Password Vault has its own dedicated schema and must NEVER be treated
  -- as a generic document wallet table, nor should generic non-MFA policies be applied.
  IF p_table = 'w_password_vault' THEN
    PERFORM public.ino_apply_password_vault_mfa_policies();
    RETURN;
  END IF;

  -- 1) Create table skeleton if it does not exist
  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS public.%1$I (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid()
    )
  $ddl$, p_table);

  -- 2) Guarantee all 13 core columns exist
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

REVOKE ALL ON FUNCTION public.ino_create_wallet_table(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ino_create_wallet_table(text) TO service_role;

-- 1.5 Hardened ino_register_wallet: explicitly blocks w_password_vault
CREATE OR REPLACE FUNCTION public.ino_register_wallet(
  p_label text,
  p_kind  text default 'custom',
  p_icon  text default null,
  p_color bigint default null
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_slug text := public.ino_wallet_slug(p_label);
BEGIN
  IF v_slug is null or v_slug = 'w_' THEN
    RAISE EXCEPTION 'Wallet name must contain at least one letter or digit';
  END IF;

  IF v_slug = 'w_password_vault' THEN
    RAISE EXCEPTION 'Password Vault is a protected vault and cannot be registered as a generic wallet';
  END IF;

  PERFORM public.ino_create_wallet_table(v_slug);

  INSERT INTO public.wallets (slug, label, kind, icon_key, color_value, created_by)
  VALUES (v_slug, trim(p_label), p_kind, p_icon, p_color, auth.uid())
  ON CONFLICT (slug) DO UPDATE
    SET icon_key    = coalesce(excluded.icon_key,    wallets.icon_key),
        color_value = coalesce(excluded.color_value, wallets.color_value);

  RETURN v_slug;
END;
$fn$;

REVOKE ALL ON FUNCTION public.ino_register_wallet(text, text, text, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ino_register_wallet(text, text, text, bigint) TO service_role;

-- 1.6 Hardened ino_rebuild_documents_view: skips w_password_vault and reapplies MFA policies
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
  -- Sweep all registered wallet tables except w_password_vault
  FOR v_rec IN SELECT slug FROM public.wallets WHERE slug != 'w_password_vault' LOOP
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
  FROM public.wallets
  WHERE slug != 'w_password_vault';

  IF v_sql IS NOT NULL THEN
    EXECUTE 'DROP VIEW IF EXISTS public.documents';
    EXECUTE 'CREATE VIEW public.documents WITH (security_invoker = on) AS ' || v_sql;
    EXECUTE 'GRANT SELECT ON public.documents TO authenticated, service_role';
  END IF;

  -- Ensure MFA policies on w_password_vault are always preserved after view rebuilds
  PERFORM public.ino_apply_password_vault_mfa_policies();
END;
$fn$;

REVOKE ALL ON FUNCTION public.ino_rebuild_documents_view() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ino_rebuild_documents_view() TO service_role;

-- 1.7 Hardened create_custom_wallet: guarantees MFA enforcement is preserved after wallet creation
CREATE OR REPLACE FUNCTION public.create_custom_wallet(
  p_name  text,
  p_icon  text   default 'folder',
  p_color bigint default 4281039526
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_slug  text;
  v_count integer;
BEGIN
  IF auth.uid() is null THEN
    RAISE EXCEPTION 'You must be signed in to create a wallet' USING errcode = '28000';
  END IF;

  IF p_name is null or trim(p_name) !~ '^[A-Za-z0-9][A-Za-z0-9 _''&-]{0,39}$' THEN
    RAISE EXCEPTION 'Invalid wallet name: use 1-40 letters, digits, spaces, & _ - or apostrophe';
  END IF;

  SELECT count(*) INTO v_count FROM public.wallets WHERE kind = 'custom';
  IF v_count >= 200 THEN
    RAISE EXCEPTION 'Custom wallet limit reached';
  END IF;

  v_slug := public.ino_register_wallet(p_name, 'custom', p_icon, p_color);

  PERFORM public.ino_rebuild_documents_view();
  PERFORM public.ino_apply_password_vault_mfa_policies();
  NOTIFY pgrst, 'reload schema';
  RETURN v_slug;
END;
$fn$;

REVOKE ALL ON FUNCTION public.create_custom_wallet(text, text, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_custom_wallet(text, text, bigint) TO authenticated, service_role;


-- ============================================================================
-- PART 2: ISSUE #2 - UNAUTHENTICATED DOCUMENT DELETION (FAIL-CLOSED)
-- ============================================================================

-- 2.1 Hardened remove_vault_document: fail-closed authentication and permission validation
CREATE OR REPLACE FUNCTION public.remove_vault_document(p_document uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc public.vault_documents;
  v_uid uuid := auth.uid();
BEGIN
  -- 1. Explicit caller session authentication validation (fail closed)
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to remove a document'
      USING errcode = '28000';
  END IF;

  -- 2. Fetch document record
  SELECT * INTO v_doc FROM public.vault_documents WHERE id = p_document;
  IF NOT FOUND THEN
    RETURN; -- already gone; removing twice is not an error
  END IF;

  -- 3. Fail-closed authorization check:
  -- Only the user who shared the document OR an admin of that specific vault may remove it.
  -- Using known non-null v_uid prevents 3VL NULL comparison bypass.
  IF NOT (v_doc.shared_by = v_uid OR public.is_vault_admin(v_doc.vault_id)) THEN
    RAISE EXCEPTION 'You can only remove documents you shared or administer'
      USING errcode = '42501';
  END IF;

  -- 4. Proceed with document deletion
  DELETE FROM public.vault_documents WHERE id = p_document;

  -- 5. Audit log event
  PERFORM public.ino_log_vault_event(
    p_vault        => v_doc.vault_id,
    p_action       => 'document_removed',
    p_target_type  => 'document',
    p_target_id    => p_document,
    p_target_label => v_doc.name,
    p_metadata     => jsonb_build_object('object_path', v_doc.object_path)
  );
END;
$$;

-- Explicitly revoke from PUBLIC and anon, grant only to authenticated and service_role
REVOKE ALL ON FUNCTION public.remove_vault_document(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.remove_vault_document(uuid) TO authenticated, service_role;

-- 2.2 Hardened share_document_to_vault: fail-closed authentication and permission validation
CREATE OR REPLACE FUNCTION public.share_document_to_vault(
  p_vault        uuid,
  p_object_path  text,
  p_name         text,
  p_category     text default null,
  p_size_bytes   bigint default null,
  p_content_type text default null,
  p_source_table text default null,
  p_source_id    uuid default null,
  p_note         text default null
)
RETURNS public.vault_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.vault_documents;
  v_uid uuid := auth.uid();
BEGIN
  -- 1. Explicit caller session authentication validation (fail closed)
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to share documents into a vault'
      USING errcode = '28000';
  END IF;

  IF NOT public.is_vault_editor(p_vault) THEN
    RAISE EXCEPTION 'Only editors and above can share documents into this vault'
      USING errcode = '42501';
  END IF;

  IF coalesce(p_object_path, '') = '' THEN
    RAISE EXCEPTION 'A document must have a storage path' USING errcode = '22023';
  END IF;

  INSERT INTO public.vault_documents AS vd (
    vault_id, shared_by, object_path, name, category,
    size_bytes, content_type, source_table, source_id, note
  ) VALUES (
    p_vault, v_uid, p_object_path, p_name, p_category,
    p_size_bytes, p_content_type, p_source_table, p_source_id, p_note
  )
  ON CONFLICT (vault_id, object_path) DO UPDATE
    SET name       = excluded.name,
        category   = excluded.category,
        note       = excluded.note,
        updated_at = now()
  RETURNING * INTO v_row;

  PERFORM public.ino_log_vault_event(
    p_vault        => p_vault,
    p_action       => 'document_shared',
    p_target_type  => 'document',
    p_target_id    => v_row.id,
    p_target_label => p_name,
    p_metadata     => jsonb_build_object('object_path', p_object_path)
  );

  RETURN v_row;
END;
$$;

-- Explicitly revoke from PUBLIC and anon, grant only to authenticated and service_role
REVOKE ALL ON FUNCTION public.share_document_to_vault(uuid, text, text, text, bigint, text, text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.share_document_to_vault(uuid, text, text, text, bigint, text, text, uuid, text) TO authenticated, service_role;

-- 2.3 Ensure Password Vault MFA policies are active right now
SELECT public.ino_apply_password_vault_mfa_policies();

-- 2.4 Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;
