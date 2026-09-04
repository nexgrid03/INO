-- Migration: 20260904010000_mfa_rls_hardening.sql
-- Description: Enforces MFA (AAL2) validation for sensitive user vault tables.

CREATE OR REPLACE FUNCTION public.ino_is_aal2_satisfied()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt()->>'aal') = 'aal2' OR NOT EXISTS (
    SELECT 1 FROM auth.mfa_factors
    WHERE auth_user_id = auth.uid() AND status = 'verified'
  );
$$;

REVOKE EXECUTE ON FUNCTION public.ino_is_aal2_satisfied() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ino_is_aal2_satisfied() TO authenticated, service_role;
