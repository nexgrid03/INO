-- Migration: 20260904020000_delete_account_rpc.sql
-- Description: Adds SECURITY DEFINER function public.delete_account() to permanently
-- delete the authenticated user, all owned storage objects, and all user data across all tables.

CREATE OR REPLACE FUNCTION public.delete_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, storage
AS $$
DECLARE
  v_uid uuid;
BEGIN
  -- 1. Obtain current authenticated user id
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- 2. Delete storage objects belonging to user (documents, backups, avatars)
  DELETE FROM storage.objects
  WHERE owner = v_uid
     OR name LIKE (v_uid::text || '/%');

  -- 3. Explicitly delete user rows across all user-owned tables
  DELETE FROM public.users WHERE auth_user_id = v_uid;
  DELETE FROM public.reminders WHERE auth_user_id = v_uid;
  DELETE FROM public.documents WHERE auth_user_id = v_uid;
  DELETE FROM public.notes WHERE auth_user_id = v_uid;
  DELETE FROM public.expenses WHERE auth_user_id = v_uid;
  DELETE FROM public.vault_keys WHERE auth_user_id = v_uid;
  DELETE FROM public.device_tokens WHERE auth_user_id = v_uid;
  DELETE FROM public.user_qr_codes WHERE auth_user_id = v_uid;
  DELETE FROM public.offline_documents WHERE auth_user_id = v_uid;

  -- Per-wallet tables
  DELETE FROM public.w_property_wallet WHERE auth_user_id = v_uid;
  DELETE FROM public.w_investment_wallet WHERE auth_user_id = v_uid;
  DELETE FROM public.w_card_wallet WHERE auth_user_id = v_uid;
  DELETE FROM public.w_password_vault WHERE auth_user_id = v_uid;
  DELETE FROM public.w_tax_wallet WHERE auth_user_id = v_uid;
  DELETE FROM public.w_vehicle_wallet WHERE auth_user_id = v_uid;
  DELETE FROM public.w_identity_wallet WHERE auth_user_id = v_uid;
  DELETE FROM public.w_health_wallet WHERE auth_user_id = v_uid;

  -- Shares & Tokens
  DELETE FROM public.document_shares WHERE auth_user_id = v_uid;
  DELETE FROM public.share_tokens WHERE auth_user_id = v_uid;
  DELETE FROM public.view_once_shares WHERE auth_user_id = v_uid;

  -- Family Vaults & Memberships
  DELETE FROM public.family_vault_members WHERE auth_user_id = v_uid;
  DELETE FROM public.family_vault_invitations WHERE created_by = v_uid OR invited_email IN (SELECT email FROM auth.users WHERE id = v_uid);
  DELETE FROM public.family_vaults WHERE owner_user_id = v_uid;

  -- Notifications
  DELETE FROM public.notification_outbox WHERE auth_user_id = v_uid;
  DELETE FROM public.push_log WHERE auth_user_id = v_uid;

  -- 4. Delete the user from auth.users (triggers foreign key cascades)
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;

-- Security hardening: REVOKE from PUBLIC, GRANT to authenticated users & service role
REVOKE EXECUTE ON FUNCTION public.delete_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_account() TO authenticated, service_role;
