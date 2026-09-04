-- ============================================================================
-- INO - Security Hardening: Device Tokens RLS Update Policy
-- ----------------------------------------------------------------------------
-- Fixes ISSUE L6: Removes UPDATE USING (true) policy from device_tokens
-- table and replaces it with owner-only policy auth_user_id = auth.uid().
-- ============================================================================

DROP POLICY IF EXISTS "device_tokens: owner updates own" ON public.device_tokens;

CREATE POLICY "device_tokens: owner updates own" ON public.device_tokens
  FOR UPDATE USING (auth_user_id = auth.uid()) WITH CHECK (auth_user_id = auth.uid());
