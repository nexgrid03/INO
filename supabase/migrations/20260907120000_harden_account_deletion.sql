-- ============================================================================
-- Migration: 20260907120000_harden_account_deletion.sql
--
-- Objective:
-- Harden and future-proof public.delete_account() RPC against schema changes:
-- 1. Fix public.expenses column reference from user_id to auth_user_id.
-- 2. Fix public.vault_members handover sorting from joined_at to created_at.
-- 3. Fix public.wallets cleanup referencing id to slug (primary key).
-- 4. Add defensive to_regclass checks and sub-block exception isolation for
--    all optional/modular tables so future schema migrations never block
--    account deletion.
-- 5. Explicitly clean notes and tax_documents if present.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, storage, extensions
AS $$
DECLARE
  v_uid UUID := auth.uid();
  r RECORD;
  v_vault RECORD;
  v_successor UUID;
  v_other_records_count INT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '28000';
  END IF;

  -- 1. Storage bucket cleanup (best effort, isolated)
  BEGIN
    DELETE FROM storage.objects
    WHERE bucket_id = 'documents'
      AND (storage.foldername(name))[1] = v_uid::text;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Storage objects cleanup exception for %: %', v_uid, SQLERRM;
  END;

  -- 2. Profile & Core Tables
  IF to_regclass('public.users') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.users WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'users cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.reminders') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.reminders WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'reminders cleanup notice: %', SQLERRM;
    END;
  END IF;

  -- FIXED: auth_user_id instead of non-existent user_id
  IF to_regclass('public.expenses') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.expenses WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'expenses cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.notes') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.notes WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'notes cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.tax_documents') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.tax_documents WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'tax_documents cleanup notice: %', SQLERRM;
    END;
  END IF;

  -- 3. Vault Keys & Sessions
  IF to_regclass('public.vault_keys') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.vault_keys WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'vault_keys cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.vault_meta') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.vault_meta WHERE user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'vault_meta cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.device_tokens') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.device_tokens WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'device_tokens cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.user_sessions') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.user_sessions WHERE user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'user_sessions cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.user_consents') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.user_consents WHERE user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'user_consents cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.user_qr_codes') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.user_qr_codes WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'user_qr_codes cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.offline_documents') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.offline_documents WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'offline_documents cleanup notice: %', SQLERRM;
    END;
  END IF;

  -- 4. Built-in per-wallet tables
  IF to_regclass('public.w_identity_wallet') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.w_identity_wallet WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'w_identity_wallet cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.w_document_wallet') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.w_document_wallet WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'w_document_wallet cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.w_property_wallet') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.w_property_wallet WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'w_property_wallet cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.w_insurance_wallet') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.w_insurance_wallet WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'w_insurance_wallet cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.w_health_wallet') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.w_health_wallet WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'w_health_wallet cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.w_investment_wallet') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.w_investment_wallet WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'w_investment_wallet cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.w_banking_wallet') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.w_banking_wallet WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'w_banking_wallet cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.w_cards_wallet') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.w_cards_wallet WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'w_cards_wallet cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.w_password_vault') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.w_password_vault WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'w_password_vault cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.w_ino_share_cache') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.w_ino_share_cache WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'w_ino_share_cache cleanup notice: %', SQLERRM;
    END;
  END IF;

  -- 5. Custom wallets: Clean user's records; only remove registry if no other users have data
  IF to_regclass('public.wallets') IS NOT NULL THEN
    FOR r IN (
      SELECT slug FROM public.wallets
      WHERE to_regclass('public.' || slug) IS NOT NULL
    ) LOOP
      BEGIN
        EXECUTE format('DELETE FROM public.%I WHERE auth_user_id = $1', r.slug) USING v_uid;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Custom wallet % cleanup notice: %', r.slug, SQLERRM;
      END;
    END LOOP;

    -- FIXED: Check slug instead of non-existent column id
    FOR r IN (
      SELECT slug FROM public.wallets WHERE created_by = v_uid
    ) LOOP
      IF to_regclass('public.' || r.slug) IS NOT NULL THEN
        EXECUTE format('SELECT count(*) FROM public.%I WHERE auth_user_id != $1', r.slug)
        INTO v_other_records_count
        USING v_uid;

        IF v_other_records_count = 0 THEN
          DELETE FROM public.wallets WHERE slug = r.slug;
        END IF;
      ELSE
        DELETE FROM public.wallets WHERE slug = r.slug;
      END IF;
    END LOOP;
  END IF;

  -- 6. Shares & analytics
  IF to_regclass('public.share_views') IS NOT NULL AND to_regclass('public.document_shares') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.share_views WHERE share_id IN (SELECT share_id FROM public.document_shares WHERE owner_id = v_uid);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'share_views cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.share_downloads') IS NOT NULL AND to_regclass('public.document_shares') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.share_downloads WHERE share_id IN (SELECT share_id FROM public.document_shares WHERE owner_id = v_uid);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'share_downloads cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.document_shares') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.document_shares WHERE owner_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'document_shares cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.view_once_shares') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.view_once_shares WHERE owner_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'view_once_shares cleanup notice: %', SQLERRM;
    END;
  END IF;

  -- 7. Family Vaults: Preserve shared vaults by transferring ownership to surviving co-owner/admin
  IF to_regclass('public.family_vaults') IS NOT NULL AND to_regclass('public.vault_members') IS NOT NULL THEN
    FOR v_vault IN (
      SELECT id FROM public.family_vaults WHERE owner_auth_user_id = v_uid
    ) LOOP
      -- FIXED: created_at instead of non-existent joined_at
      SELECT auth_user_id INTO v_successor
      FROM public.vault_members
      WHERE vault_id = v_vault.id
        AND auth_user_id != v_uid
      ORDER BY 
        CASE role WHEN 'admin' THEN 1 WHEN 'editor' THEN 2 ELSE 3 END,
        created_at ASC
      LIMIT 1;

      IF v_successor IS NOT NULL THEN
        UPDATE public.family_vaults
        SET owner_auth_user_id = v_successor
        WHERE id = v_vault.id;

        UPDATE public.vault_members
        SET role = 'owner'
        WHERE vault_id = v_vault.id AND auth_user_id = v_successor;

        BEGIN
          PERFORM public.ino_log_vault_event(
            v_vault.id, 'ownership_transferred', 'vault', v_vault.id,
            'Account deletion handover',
            jsonb_build_object('previous_owner', v_uid, 'new_owner', v_successor));
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
      ELSE
        DELETE FROM public.family_vaults WHERE id = v_vault.id;
      END IF;
    END LOOP;
  END IF;

  IF to_regclass('public.vault_documents') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.vault_documents WHERE shared_by = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'vault_documents cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.vault_join_requests') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.vault_join_requests WHERE requester_auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'vault_join_requests cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.vault_invite_audit_logs') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.vault_invite_audit_logs WHERE caller_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'vault_invite_audit_logs cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.vault_audit_log') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.vault_audit_log WHERE actor_auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'vault_audit_log cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.vault_notification_events') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.vault_notification_events WHERE actor_auth_user_id = v_uid OR recipient_auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'vault_notification_events cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.vault_members') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.vault_members WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'vault_members cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.vault_invitations') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.vault_invitations
      WHERE invited_by = v_uid
         OR email IN (SELECT email FROM auth.users WHERE id = v_uid);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'vault_invitations cleanup notice: %', SQLERRM;
    END;
  END IF;

  -- 8. Notifications
  IF to_regclass('public.notification_outbox') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.notification_outbox WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'notification_outbox cleanup notice: %', SQLERRM;
    END;
  END IF;

  IF to_regclass('public.push_log') IS NOT NULL THEN
    BEGIN
      DELETE FROM public.push_log WHERE auth_user_id = v_uid;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'push_log cleanup notice: %', SQLERRM;
    END;
  END IF;

  -- 9. Final step: delete user from auth.users (cascades any remaining foreign keys)
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;

-- Ensure execute permissions
REVOKE EXECUTE ON FUNCTION public.delete_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_account() TO authenticated, service_role;
