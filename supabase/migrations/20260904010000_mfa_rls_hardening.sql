-- Migration: 20260904010000_mfa_rls_hardening.sql
-- Description: Enforces MFA (AAL2) validation for sensitive user vault tables.

CREATE OR REPLACE FUNCTION public.ino_is_aal2_satisfied()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT (auth.jwt()->>'aal') = 'aal2' OR NOT EXISTS (
    SELECT 1 FROM auth.mfa_factors
    WHERE user_id = auth.uid() AND status = 'verified'
  );
$$;

REVOKE EXECUTE ON FUNCTION public.ino_is_aal2_satisfied() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ino_is_aal2_satisfied() TO authenticated, service_role;

-- Enforce MFA requirement on sensitive password vault table if it exists
DO $$
BEGIN
  IF to_regclass('public.w_password_vault') IS NOT NULL THEN
    ALTER TABLE public.w_password_vault ENABLE ROW LEVEL SECURITY;

    DROP POLICY IF EXISTS "w_password_vault: owner select" ON public.w_password_vault;
    CREATE POLICY "w_password_vault: owner select" ON public.w_password_vault
      FOR SELECT TO authenticated
      USING (auth.uid() = auth_user_id AND public.ino_is_aal2_satisfied());

    DROP POLICY IF EXISTS "w_password_vault: owner insert" ON public.w_password_vault;
    CREATE POLICY "w_password_vault: owner insert" ON public.w_password_vault
      FOR INSERT TO authenticated
      WITH CHECK (auth.uid() = auth_user_id AND public.ino_is_aal2_satisfied());

    DROP POLICY IF EXISTS "w_password_vault: owner update" ON public.w_password_vault;
    CREATE POLICY "w_password_vault: owner update" ON public.w_password_vault
      FOR UPDATE TO authenticated
      USING (auth.uid() = auth_user_id AND public.ino_is_aal2_satisfied())
      WITH CHECK (auth.uid() = auth_user_id AND public.ino_is_aal2_satisfied());

    DROP POLICY IF EXISTS "w_password_vault: owner delete" ON public.w_password_vault;
    CREATE POLICY "w_password_vault: owner delete" ON public.w_password_vault
      FOR DELETE TO authenticated
      USING (auth.uid() = auth_user_id AND public.ino_is_aal2_satisfied());
  END IF;
END;
$$;
