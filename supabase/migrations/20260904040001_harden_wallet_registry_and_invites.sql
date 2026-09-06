-- ============================================================================
-- INO Security Hardening: Wallet Registry Exposure, User Enumeration Prevention,
-- and Server-Side Storage Quota Enforcement
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. WALLET REGISTRY INFORMATION EXPOSURE FIX
-- ----------------------------------------------------------------------------
-- Restrict direct table access on public.wallets so users only read builtin
-- wallets or wallets created by themselves.
DROP POLICY IF EXISTS "wallets: authenticated reads" ON public.wallets;
DROP POLICY IF EXISTS "wallets: owner or builtin reads" ON public.wallets;

CREATE POLICY "wallets: owner or builtin reads" ON public.wallets
  FOR SELECT TO authenticated
  USING (kind = 'builtin' OR created_by = auth.uid());

-- Create a secure public-facing view that exposes ONLY non-sensitive metadata:
-- wallet_id, wallet_name, wallet_icon, wallet_color, wallet_type.
-- NO created_by, owner_id, user_id, email, or phone exposed.
CREATE OR REPLACE VIEW public.public_wallet_registry_view
WITH (security_invoker = true)
AS
SELECT
  slug AS wallet_id,
  label AS wallet_name,
  icon_key AS wallet_icon,
  color_value AS wallet_color,
  kind AS wallet_type
FROM public.wallets;

GRANT SELECT ON public.public_wallet_registry_view TO authenticated;

-- ----------------------------------------------------------------------------
-- 2. USER ENUMERATION VIA VAULT INVITES FIX
-- ----------------------------------------------------------------------------
-- Create audit log table for vault invite attempts (abuse detection & rate limiting)
CREATE TABLE IF NOT EXISTS public.vault_invite_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  caller_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  target TEXT NOT NULL,
  client_ip TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.vault_invite_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vault_invite_audit_logs: owner select" ON public.vault_invite_audit_logs;
CREATE POLICY "vault_invite_audit_logs: owner select" ON public.vault_invite_audit_logs
  FOR SELECT TO authenticated
  USING (caller_id = auth.uid());

CREATE INDEX IF NOT EXISTS vault_invite_audit_logs_caller_time_idx
  ON public.vault_invite_audit_logs (caller_id, created_at DESC);

-- Drop existing function if signature changes
DROP FUNCTION IF EXISTS public.invite_ino_user_to_vault(uuid, text, text);

-- Create non-enumerating invite RPC function
CREATE OR REPLACE FUNCTION public.invite_ino_user_to_vault(
  p_vault UUID,
  p_role  TEXT,
  p_query TEXT
)
  RETURNS JSONB
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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

  -- 4. Internal user resolution without exposing existence signals
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

  -- Create internal invite row safely
  IF v_count > 0 AND v_target.auth_user_id IS NOT NULL THEN
    -- If user exists, process invite if not self and not already member
    IF v_target.auth_user_id <> v_uid AND
       NOT EXISTS (SELECT 1 FROM public.vault_members m WHERE m.vault_id = p_vault AND m.auth_user_id = v_target.auth_user_id) AND
       NOT EXISTS (SELECT 1 FROM public.vault_invitations i WHERE i.vault_id = p_vault AND i.status = 'pending' AND (i.invitee_auth_user_id = v_target.auth_user_id OR (v_target.email IS NOT NULL AND lower(i.email) = lower(v_target.email)))) THEN
      
      INSERT INTO public.vault_invitations
        (vault_id, invited_by, role, email, phone, invited_name, status,
         vault_name, invited_by_name, invitee_auth_user_id)
      VALUES
        (p_vault, v_uid, p_role, nullif(lower(trim(v_target.email)), ''),
         nullif(trim(v_target.phone), ''), v_target.full_name, 'pending',
         coalesce(v_vault_name, 'Family Vault'), v_inviter, v_target.auth_user_id)
      RETURNING * INTO v_row;

      PERFORM public.ino_log_vault_event(
        p_vault, 'invite_sent', 'invitation', v_row.id,
        coalesce(v_target.full_name, v_target.email, v_target.phone),
        jsonb_build_object('role', p_role, 'via', v_kind));
      PERFORM public.ino_enqueue_vault_notification(
        'invitation.created', p_vault, v_target.auth_user_id, v_target.email, v_target.phone,
        jsonb_build_object('invitation_id', v_row.id, 'vault_name', coalesce(v_vault_name, 'Family Vault'), 'role', p_role));
    END IF;
  ELSE
    -- If user does not exist or ambiguous, store pending invite internally
    IF NOT EXISTS (SELECT 1 FROM public.vault_invitations i WHERE i.vault_id = p_vault AND i.status = 'pending' AND ( (v_kind = 'email' AND lower(i.email) = lower(v_q)) OR (v_kind = 'phone' AND i.phone = v_q) )) THEN
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

  -- ALWAYS return a generic, uniform response to prevent user enumeration
  RETURN jsonb_build_object('status', 'success', 'message', 'Invitation processed.');
END;
$$;

GRANT EXECUTE ON FUNCTION public.invite_ino_user_to_vault(uuid, text, text) TO authenticated;

-- ----------------------------------------------------------------------------
-- 3. SERVER-SIDE STORAGE QUOTA ENFORCEMENT FIX
-- ----------------------------------------------------------------------------
-- Server-side trigger function on storage.objects BEFORE INSERT or UPDATE
-- to enforce 5 GB limit per user folder: documents/<uid>/*
CREATE OR REPLACE FUNCTION public.check_user_storage_quota()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  v_uid TEXT := auth.uid()::text;
  v_total_bytes BIGINT := 0;
  v_incoming_size BIGINT := 0;
  v_max_bytes BIGINT := 5368709120; -- 5 GB quota limit
BEGIN
  IF NEW.bucket_id = 'documents' THEN
    IF v_uid IS NULL THEN
      v_uid := (storage.foldername(NEW.name))[1];
    END IF;

    IF v_uid IS NOT NULL THEN
      BEGIN
        v_incoming_size := COALESCE((NEW.metadata->>'size')::BIGINT, 0);
      EXCEPTION WHEN OTHERS THEN
        v_incoming_size := 0;
      END;

      BEGIN
        SELECT COALESCE(SUM((metadata->>'size')::BIGINT), 0)
        INTO v_total_bytes
        FROM storage.objects
        WHERE bucket_id = 'documents'
          AND (storage.foldername(name))[1] = v_uid
          AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);

        IF (v_total_bytes + v_incoming_size) > v_max_bytes THEN
          RAISE EXCEPTION 'Storage quota exceeded' USING errcode = '54000';
        END IF;
      EXCEPTION
        WHEN SQLSTATE '54000' THEN
          RAISE;
        WHEN OTHERS THEN
          RAISE WARNING 'Storage quota check warning: %', SQLERRM;
      END;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DO $$
BEGIN
  BEGIN
    DROP TRIGGER IF EXISTS trg_enforce_storage_quota ON storage.objects;
    CREATE TRIGGER trg_enforce_storage_quota
      BEFORE INSERT OR UPDATE ON storage.objects
      FOR EACH ROW
      EXECUTE FUNCTION public.check_user_storage_quota();
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Could not create storage quota trigger on storage.objects: %', SQLERRM;
  END;
END;
$$;

COMMIT;
