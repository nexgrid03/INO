-- ============================================================================
-- INO - PHASE 7: CRITICAL BACKEND & SECURITY REMEDIATIONS
-- ----------------------------------------------------------------------------
-- Fixes:
-- 1. Critical Issue 1: Prevent invite PII leakage & name constraint oracle
-- 2. Medium Issue 2: Account deletion transfers shared vaults & preserves custom wallets
-- 3. Medium Issue 3: Cleanup historical invalid vault_documents cross-user rows
-- 4. Medium Issue 4: share_rate_limits lockout decay & IP hashing
-- 5. Medium Issue 5: register_device_token atomic handover RPC
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. CRITICAL ISSUE 1: VAULT INVITATION TARGET CONSTRAINT & PII PROTECTION
-- ----------------------------------------------------------------------------
-- Widen target check constraint so name-only lookups or auth-user invites do not throw
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'vault_invitations_target_chk') THEN
    ALTER TABLE public.vault_invitations DROP CONSTRAINT vault_invitations_target_chk;
  END IF;
END;
$$;

ALTER TABLE public.vault_invitations
  ADD CONSTRAINT vault_invitations_target_chk
  CHECK (
    COALESCE(email, '') <> '' OR 
    COALESCE(phone, '') <> '' OR 
    COALESCE(invited_name, '') <> '' OR 
    invitee_auth_user_id IS NOT NULL
  );

DROP FUNCTION IF EXISTS public.invite_ino_user_to_vault(UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.invite_ino_user_to_vault(
  p_vault UUID,
  p_role  TEXT,
  p_query TEXT
)
  RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE
  v_uid          UUID := auth.uid();
  v_q            TEXT := trim(coalesce(p_query, ''));
  v_kind         TEXT;
  v_count        INT := 0;
  v_target       public.users%ROWTYPE;
  v_vault_name   TEXT;
  v_inviter      TEXT;
  v_ip           TEXT;
  v_hourly_count INT := 0;
  v_row          public.vault_invitations%ROWTYPE;
BEGIN
  -- 1. Authorization checks
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'You must be signed in' USING errcode = '28000';
  END IF;
  IF NOT public.is_vault_admin(p_vault) THEN
    RAISE EXCEPTION 'Only an owner or admin can invite members' USING errcode = '42501';
  END IF;
  IF p_role NOT IN ('admin', 'editor', 'viewer') THEN
    RAISE EXCEPTION 'Invalid role (owner cannot be invited)' USING errcode = '22023';
  END IF;
  IF v_q = '' THEN
    RAISE EXCEPTION 'Enter a phone number, name or email' USING errcode = '22023';
  END IF;

  -- 2. Server-side Rate Limiting (10 invite lookups per hour per user)
  SELECT count(*) INTO v_hourly_count
  FROM public.vault_invite_audit_logs
  WHERE caller_id = v_uid
    AND created_at > now() - INTERVAL '1 hour';

  IF v_hourly_count >= 10 THEN
    RAISE EXCEPTION 'Rate limit exceeded. Please wait before attempting more invitations.' USING errcode = '42900';
  END IF;

  -- 3. Audit Logging
  BEGIN
    v_ip := current_setting('request.headers', true)::json->>'x-forwarded-for';
    IF v_ip IS NULL THEN
      v_ip := current_setting('request.headers', true)::json->>'remote_addr';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_ip := NULL;
  END;

  INSERT INTO public.vault_invite_audit_logs (caller_id, target, client_ip)
  VALUES (v_uid, v_q, v_ip);

  -- 4. User resolution
  SELECT name INTO v_vault_name FROM public.family_vaults WHERE id = p_vault;
  SELECT full_name INTO v_inviter FROM public.users WHERE auth_user_id = v_uid;

  IF v_q LIKE '%@%' THEN
    v_kind := 'email';
    SELECT count(*) INTO v_count FROM public.users u WHERE lower(u.email) = lower(v_q);
    SELECT * INTO v_target FROM public.users u WHERE lower(u.email) = lower(v_q) LIMIT 1;
  ELSIF v_q ~ '^[+()\s\d-]+$' AND length(public.ino_phone_digits(v_q)) >= 8 THEN
    v_kind := 'phone';
    SELECT count(*) INTO v_count FROM public.users u
     WHERE public.ino_phone_digits(u.phone) = public.ino_phone_digits(v_q);
    SELECT * INTO v_target FROM public.users u
     WHERE public.ino_phone_digits(u.phone) = public.ino_phone_digits(v_q)
     ORDER BY u.created_at LIMIT 1;
  ELSE
    v_kind := 'name';
    SELECT count(*) INTO v_count FROM public.users u WHERE lower(trim(u.full_name)) = lower(v_q);
    IF v_count = 0 THEN
      SELECT count(*) INTO v_count FROM public.users u WHERE lower(trim(u.full_name)) LIKE lower(v_q) || '%';
      SELECT * INTO v_target FROM public.users u WHERE lower(trim(u.full_name)) LIKE lower(v_q) || '%' LIMIT 1;
    ELSE
      SELECT * INTO v_target FROM public.users u WHERE lower(trim(u.full_name)) = lower(v_q) LIMIT 1;
    END IF;
  END IF;

  -- Create internal invite row safely WITHOUT harvesting or leaking target contact details
  IF v_count > 0 AND v_target.auth_user_id IS NOT NULL THEN
    IF v_target.auth_user_id <> v_uid AND
       NOT EXISTS (SELECT 1 FROM public.vault_members m WHERE m.vault_id = p_vault AND m.auth_user_id = v_target.auth_user_id) AND
       NOT EXISTS (SELECT 1 FROM public.vault_invitations i WHERE i.vault_id = p_vault AND i.status = 'pending' AND (i.invitee_auth_user_id = v_target.auth_user_id OR (v_kind = 'email' AND lower(i.email) = lower(v_q)) OR (v_kind = 'phone' AND i.phone = v_q))) THEN
      
      -- Store ONLY the query identifier provided by the inviter to prevent PII harvesting
      INSERT INTO public.vault_invitations
        (vault_id, invited_by, role, email, phone, invited_name, status,
         vault_name, invited_by_name, invitee_auth_user_id)
      VALUES
        (p_vault, v_uid, p_role,
         CASE WHEN v_kind = 'email' THEN lower(v_q) ELSE NULL END,
         CASE WHEN v_kind = 'phone' THEN v_q ELSE NULL END,
         CASE WHEN v_kind = 'name' THEN v_q ELSE NULL END,
         'pending', coalesce(v_vault_name, 'Family Vault'), v_inviter, v_target.auth_user_id)
      RETURNING * INTO v_row;

      PERFORM public.ino_log_vault_event(
        p_vault, 'invite_sent', 'invitation', v_row.id,
        v_q,
        jsonb_build_object('role', p_role, 'via', v_kind));
      PERFORM public.ino_enqueue_vault_notification(
        'invitation.created', p_vault, v_target.auth_user_id, v_target.email, v_target.phone,
        jsonb_build_object('invitation_id', v_row.id, 'vault_name', coalesce(v_vault_name, 'Family Vault'), 'role', p_role));
    END IF;
  ELSE
    -- User not found: record pending invitation by entered identifier without throwing constraint errors
    IF NOT EXISTS (SELECT 1 FROM public.vault_invitations i WHERE i.vault_id = p_vault AND i.status = 'pending' AND ( (v_kind = 'email' AND lower(i.email) = lower(v_q)) OR (v_kind = 'phone' AND i.phone = v_q) OR (v_kind = 'name' AND lower(i.invited_name) = lower(v_q)) )) THEN
      INSERT INTO public.vault_invitations
        (vault_id, invited_by, role, email, phone, invited_name, status,
         vault_name, invited_by_name)
      VALUES
        (p_vault, v_uid, p_role,
         CASE WHEN v_kind = 'email' THEN lower(v_q) ELSE NULL END,
         CASE WHEN v_kind = 'phone' THEN v_q ELSE NULL END,
         CASE WHEN v_kind = 'name' THEN v_q ELSE NULL END,
         'pending', coalesce(v_vault_name, 'Family Vault'), v_inviter);
    END IF;
  END IF;

  -- Uniform response prevents oracle enumeration
  RETURN jsonb_build_object('status', 'success', 'message', 'Invitation processed.');
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. MEDIUM ISSUE 2: ACCOUNT DELETION CO-OWNER VAULT PRESERVATION
-- ----------------------------------------------------------------------------
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

  -- 1. Storage bucket cleanup
  BEGIN
    DELETE FROM storage.objects
    WHERE bucket_id = 'documents'
      AND (storage.foldername(name))[1] = v_uid::text;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Storage objects cleanup exception for %: %', v_uid, SQLERRM;
  END;

  -- 2. Profile & Core Tables
  IF to_regclass('public.users') IS NOT NULL THEN
    DELETE FROM public.users WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.reminders') IS NOT NULL THEN
    DELETE FROM public.reminders WHERE auth_user_id = v_uid;
  END IF;

  IF to_regclass('public.expenses') IS NOT NULL THEN
    DELETE FROM public.expenses WHERE user_id = v_uid;
  END IF;

  -- 3. Vault Keys & Sessions
  IF to_regclass('public.vault_keys') IS NOT NULL THEN
    DELETE FROM public.vault_keys WHERE auth_user_id = v_uid;
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

  -- 4. Built-in per-wallet tables
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

  -- 5. Custom wallets: Clean user's records; only remove registry if no other users have data
  IF to_regclass('public.wallets') IS NOT NULL THEN
    FOR r IN (
      SELECT slug FROM public.wallets
      WHERE to_regclass('public.' || slug) IS NOT NULL
    ) LOOP
      EXECUTE format('DELETE FROM public.%I WHERE auth_user_id = $1', r.slug) USING v_uid;
    END LOOP;

    -- Only remove wallet definition if no other user has records in that custom wallet
    FOR r IN (
      SELECT slug, id FROM public.wallets WHERE created_by = v_uid
    ) LOOP
      IF to_regclass('public.' || r.slug) IS NOT NULL THEN
        EXECUTE format('SELECT count(*) FROM public.%I WHERE auth_user_id != $1', r.slug)
        INTO v_other_records_count
        USING v_uid;

        IF v_other_records_count = 0 THEN
          DELETE FROM public.wallets WHERE id = r.id;
        END IF;
      ELSE
        DELETE FROM public.wallets WHERE id = r.id;
      END IF;
    END LOOP;
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

  -- 7. Family Vaults: Preserve shared vaults by transferring ownership to surviving co-owner/admin
  IF to_regclass('public.family_vaults') IS NOT NULL AND to_regclass('public.vault_members') IS NOT NULL THEN
    FOR v_vault IN (
      SELECT id FROM public.family_vaults WHERE owner_auth_user_id = v_uid
    ) LOOP
      -- Find highest ranking surviving member (owner/admin/editor/oldest member)
      SELECT auth_user_id INTO v_successor
      FROM public.vault_members
      WHERE vault_id = v_vault.id
        AND auth_user_id != v_uid
      ORDER BY 
        CASE role WHEN 'owner' THEN 1 WHEN 'admin' THEN 2 WHEN 'editor' THEN 3 ELSE 4 END,
        created_at ASC
      LIMIT 1;

      IF v_successor IS NOT NULL THEN
        -- Transfer vault ownership to surviving member
        UPDATE public.family_vaults
        SET owner_auth_user_id = v_successor
        WHERE id = v_vault.id;

        UPDATE public.vault_members
        SET role = 'owner'
        WHERE vault_id = v_vault.id AND auth_user_id = v_successor;

        PERFORM public.ino_log_vault_event(
          v_vault.id, 'ownership_transferred', 'vault', v_vault.id,
          'Account deletion handover',
          jsonb_build_object('previous_owner', v_uid, 'new_owner', v_successor));
      ELSE
        -- Sole owner with no other members: delete the vault
        DELETE FROM public.family_vaults WHERE id = v_vault.id;
      END IF;
    END LOOP;
  END IF;

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

-- ----------------------------------------------------------------------------
-- 3. MEDIUM ISSUE 3: PURGE HISTORICAL INVALID VAULT_DOCUMENTS ROWS
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.vault_documents') IS NOT NULL THEN
    DELETE FROM public.vault_documents
    WHERE object_path IS NOT NULL
      AND split_part(object_path, '/', 1) <> shared_by::text;
  END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. MEDIUM ISSUE 4: SHARE RATE LIMIT COUNTER DECAY & IP HASHING
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_share_password_lock(
  p_ip text,
  p_token text
)
RETURNS TABLE (is_locked boolean, lock_until timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_lock timestamptz;
  v_ip_hash text;
BEGIN
  v_ip_hash := encode(digest(p_ip, 'sha256'), 'hex');

  SELECT srl.lock_until INTO v_lock
  FROM public.share_rate_limits srl
  WHERE (srl.ip = v_ip_hash OR srl.ip = p_ip) AND srl.token = p_token;

  IF v_lock IS NOT NULL AND v_lock > now() THEN
    RETURN QUERY SELECT true, v_lock;
  ELSE
    RETURN QUERY SELECT false, null::timestamptz;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_share_password_attempt(
  p_ip text,
  p_token text,
  p_success boolean
)
RETURNS TABLE (is_locked boolean, attempts integer, lock_until timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_attempts integer;
  v_lock timestamptz := null;
  v_ip_hash text;
BEGIN
  v_ip_hash := encode(digest(p_ip, 'sha256'), 'hex');

  IF p_success THEN
    DELETE FROM public.share_rate_limits 
    WHERE (ip = v_ip_hash OR ip = p_ip) AND token = p_token;
    RETURN QUERY SELECT false, 0, null::timestamptz;
    RETURN;
  END IF;

  INSERT INTO public.share_rate_limits (ip, token, attempts, last_attempt, lock_until)
  VALUES (v_ip_hash, p_token, 1, now(), null)
  ON CONFLICT (ip, token) DO UPDATE
  SET attempts = CASE
        -- Decay: reset attempt counter if last failure was > 1 hour ago or previous lock expired
        WHEN share_rate_limits.last_attempt < now() - INTERVAL '1 hour' OR
             (share_rate_limits.lock_until IS NOT NULL AND share_rate_limits.lock_until < now()) THEN 1
        ELSE share_rate_limits.attempts + 1
      END,
      last_attempt = now(),
      lock_until = CASE
        WHEN (CASE
                WHEN share_rate_limits.last_attempt < now() - INTERVAL '1 hour' OR
                     (share_rate_limits.lock_until IS NOT NULL AND share_rate_limits.lock_until < now()) THEN 1
                ELSE share_rate_limits.attempts + 1
              END) >= 5 THEN now() + INTERVAL '15 minutes'
        ELSE NULL
      END
  RETURNING share_rate_limits.attempts, share_rate_limits.lock_until
  INTO v_attempts, v_lock;

  RETURN QUERY SELECT (v_lock IS NOT NULL AND v_lock > now()), v_attempts, v_lock;
END;
$$;

-- ----------------------------------------------------------------------------
-- 5. MEDIUM ISSUE 5: ATOMIC DEVICE TOKEN REASSIGNMENT / HANDOVER RPC
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_device_token(
  p_token TEXT,
  p_platform TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated' USING errcode = '28000';
  END IF;

  IF p_token IS NULL OR trim(p_token) = '' THEN
    RETURN;
  END IF;

  -- 1. Detach token from any previous user on this device (reinstallation / handover)
  DELETE FROM public.device_tokens
  WHERE token = p_token AND auth_user_id != v_uid;

  -- 2. Upsert token for current user
  INSERT INTO public.device_tokens (token, auth_user_id, platform, updated_at)
  VALUES (p_token, v_uid, coalesce(p_platform, 'android'), now())
  ON CONFLICT (token) DO UPDATE
  SET auth_user_id = v_uid,
      platform = excluded.platform,
      updated_at = now();
END;
$$;

REVOKE EXECUTE ON FUNCTION public.register_device_token(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_device_token(TEXT, TEXT) TO authenticated, service_role;

COMMIT;
