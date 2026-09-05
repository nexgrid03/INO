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
  r RECORD;
BEGIN
  -- 1. Obtain current authenticated user id
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- 2. Delete storage objects belonging to user (documents, backups, avatars)
  IF to_regclass('storage.objects') IS NOT NULL THEN
    PERFORM set_config('storage.allow_delete_query', 'true', true);
    DELETE FROM storage.objects
    WHERE (storage.foldername(name))[1] = v_uid::text
       OR name LIKE (v_uid::text || '/%')
       OR owner::text = v_uid::text;
  END IF;

  -- 3. Core tables (deletions with check on table existence to guarantee atomic completion)
  IF to_regclass('public.users') IS NOT NULL THEN
    DELETE FROM public.users WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.reminders') IS NOT NULL THEN
    DELETE FROM public.reminders WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.notes') IS NOT NULL THEN
    DELETE FROM public.notes WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.expenses') IS NOT NULL THEN
    DELETE FROM public.expenses WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.tax_documents') IS NOT NULL THEN
    DELETE FROM public.tax_documents WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.vault_keys') IS NOT NULL THEN
    DELETE FROM public.vault_keys WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.vault_items') IS NOT NULL THEN
    DELETE FROM public.vault_items WHERE user_id = v_uid;
  END IF;

  IF to_regclass('public.vault_meta') IS NOT NULL THEN
    DELETE FROM public.vault_meta WHERE user_id = v_uid;
  END IF;

  IF to_regclass('public.device_tokens') IS NOT NULL THEN
    DELETE FROM public.device_tokens WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.user_sessions') IS NOT NULL THEN
    DELETE FROM public.user_sessions WHERE user_id = v_uid;
  END IF;

  IF to_regclass('public.user_consents') IS NOT NULL THEN
    DELETE FROM public.user_consents WHERE user_id = v_uid;
  END IF;

  IF to_regclass('public.user_qr_codes') IS NOT NULL THEN
    DELETE FROM public.user_qr_codes WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.offline_documents') IS NOT NULL THEN
    DELETE FROM public.offline_documents WHERE auth_user_id = v_uid;
  END IF;

  -- 4. Built-in per-wallet tables (note: public.documents is a VIEW, so we delete from underlying tables)
  IF to_regclass('public.w_identity_wallet') IS NOT NULL THEN
    DELETE FROM public.w_identity_wallet WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.w_document_wallet') IS NOT NULL THEN
    DELETE FROM public.w_document_wallet WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.w_property_wallet') IS NOT NULL THEN
    DELETE FROM public.w_property_wallet WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.w_insurance_wallet') IS NOT NULL THEN
    DELETE FROM public.w_insurance_wallet WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.w_health_wallet') IS NOT NULL THEN
    DELETE FROM public.w_health_wallet WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.w_investment_wallet') IS NOT NULL THEN
    DELETE FROM public.w_investment_wallet WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.w_banking_wallet') IS NOT NULL THEN
    DELETE FROM public.w_banking_wallet WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.w_cards_wallet') IS NOT NULL THEN
    DELETE FROM public.w_cards_wallet WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.w_password_vault') IS NOT NULL THEN
    DELETE FROM public.w_password_vault WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.w_ino_share_cache') IS NOT NULL THEN
    DELETE FROM public.w_ino_share_cache WHERE auth_user_id = v_uid;
  END IF;

  -- 5. Dynamically clean all custom user wallets registered in public.wallets
  IF to_regclass('public.wallets') IS NOT NULL THEN
    FOR r IN (
      SELECT slug FROM public.wallets
      WHERE to_regclass('public.' || slug) IS NOT NULL
    ) LOOP
      EXECUTE format('DELETE FROM public.%I WHERE auth_user_id = $1', r.slug) USING v_uid;
    END LOOP;
    DELETE FROM public.wallets WHERE created_by = v_uid;
  END IF;

  -- 6. Shares & analytics
  IF to_regclass('public.share_views') IS NOT NULL AND to_regclass('public.document_shares') IS NOT NULL THEN
    DELETE FROM public.share_views WHERE share_id IN (SELECT share_id FROM public.document_shares WHERE owner_id = v_uid);
  END IF;

  IF to_regclass('public.share_downloads') IS NOT NULL AND to_regclass('public.document_shares') IS NOT NULL THEN
    DELETE FROM public.share_downloads WHERE share_id IN (SELECT share_id FROM public.document_shares WHERE owner_id = v_uid);
  END IF;

  IF to_regclass('public.document_shares') IS NOT NULL THEN
    DELETE FROM public.document_shares WHERE owner_id = v_uid;
  END IF;

  IF to_regclass('public.view_once_shares') IS NOT NULL THEN
    DELETE FROM public.view_once_shares WHERE owner_id = v_uid;
  END IF;

  -- 7. Family Vaults, Invitations, Join Requests & Members
  IF to_regclass('public.vault_documents') IS NOT NULL THEN
    DELETE FROM public.vault_documents WHERE shared_by = v_uid;
  END IF;

  IF to_regclass('public.vault_join_requests') IS NOT NULL THEN
    DELETE FROM public.vault_join_requests WHERE requester_auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.vault_invite_audit_logs') IS NOT NULL THEN
    DELETE FROM public.vault_invite_audit_logs WHERE caller_id = v_uid;
  END IF;

  IF to_regclass('public.vault_audit_log') IS NOT NULL THEN
    DELETE FROM public.vault_audit_log WHERE actor_auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.vault_notification_events') IS NOT NULL THEN
    DELETE FROM public.vault_notification_events WHERE actor_auth_user_id = v_uid OR recipient_auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.vault_members') IS NOT NULL THEN
    DELETE FROM public.vault_members WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.vault_invitations') IS NOT NULL THEN
    DELETE FROM public.vault_invitations
    WHERE invited_by = v_uid
       OR email IN (SELECT email FROM auth.users WHERE id = v_uid);
  END IF;

  IF to_regclass('public.family_vaults') IS NOT NULL THEN
    DELETE FROM public.family_vaults WHERE owner_auth_user_id = v_uid;
  END IF;

  -- 8. Notifications
  IF to_regclass('public.notification_outbox') IS NOT NULL THEN
    DELETE FROM public.notification_outbox WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.push_log') IS NOT NULL THEN
    DELETE FROM public.push_log WHERE auth_user_id = v_uid;
  END IF;

  -- 9. Final step: delete user from auth.users (cascades any remaining foreign keys)
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;

-- Security hardening: REVOKE from PUBLIC, GRANT to authenticated users & service role
REVOKE EXECUTE ON FUNCTION public.delete_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_account() TO authenticated, service_role;
