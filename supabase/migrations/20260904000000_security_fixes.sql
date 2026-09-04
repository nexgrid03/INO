-- ============================================================================
-- INO Critical Security Hardening — 2026-09-04
-- ============================================================================

begin;

-- 1. Revoke unauthenticated / public execution on privileged RPCs
REVOKE ALL ON FUNCTION public.ino_register_wallet(text, text, text, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ino_register_wallet(text, text, text, bigint) FROM anon;
REVOKE ALL ON FUNCTION public.ino_register_wallet(text, text, text, bigint) FROM authenticated;

REVOKE ALL ON FUNCTION public.ino_create_wallet_table(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ino_create_wallet_table(text) FROM anon;
REVOKE ALL ON FUNCTION public.ino_create_wallet_table(text) FROM authenticated;

REVOKE ALL ON FUNCTION public.expire_due_shares() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.expire_due_shares() FROM anon;
REVOKE ALL ON FUNCTION public.expire_due_shares() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.expire_due_shares() TO service_role;

REVOKE ALL ON FUNCTION public.ino_rebuild_documents_view() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ino_rebuild_documents_view() FROM anon;
REVOKE ALL ON FUNCTION public.ino_rebuild_documents_view() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.ino_rebuild_documents_view() TO service_role;

-- 2. Restrict vault_members INSERT policy to disallow owner creation by admins
DROP POLICY IF EXISTS "members: admins insert" ON public.vault_members;

CREATE POLICY "members: admins insert" ON public.vault_members
  FOR INSERT
  WITH CHECK (
    public.is_vault_admin(vault_id)
    AND role IN ('admin', 'editor', 'viewer')
    AND role <> 'owner'
  );

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

commit;
