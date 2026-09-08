-- ============================================================================
-- FIX: Create vault_invite_audit_logs table and harden invite_ino_user_to_vault
-- ============================================================================

-- 1. Ensure the audit table exists
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

GRANT ALL ON public.vault_invite_audit_logs TO authenticated;
GRANT ALL ON public.vault_invite_audit_logs TO service_role;

-- 2. Resilient invite_ino_user_to_vault RPC
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

  -- 2. Server-side Rate Limiting & Audit Logging (Safe fallback if table is created dynamically)
  IF to_regclass('public.vault_invite_audit_logs') IS NOT NULL THEN
    BEGIN
      SELECT count(*) INTO v_hourly_count
      FROM public.vault_invite_audit_logs
      WHERE caller_id = v_uid
        AND created_at > now() - INTERVAL '1 hour';

      IF v_hourly_count >= 20 THEN
        RAISE EXCEPTION 'Rate limit exceeded. Please wait before attempting more invitations.' USING errcode = '42900';
      END IF;

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
    EXCEPTION WHEN OTHERS THEN
      -- Do not block invitation if audit log table encounters a transient error
      RAISE NOTICE 'Audit logging notice: %', SQLERRM;
    END;
  END IF;

  -- 3. User resolution
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

  IF v_count = 0 OR v_target.auth_user_id IS NULL THEN
    RAISE EXCEPTION 'No INO user found matching "%"', v_q USING errcode = 'P0002';
  END IF;

  IF v_target.auth_user_id = v_uid THEN
    RAISE EXCEPTION 'You cannot invite yourself to your own vault' USING errcode = '22023';
  END IF;

  IF EXISTS (SELECT 1 FROM public.vault_members m WHERE m.vault_id = p_vault AND m.auth_user_id = v_target.auth_user_id) THEN
    RAISE EXCEPTION 'This user is already a member of the vault' USING errcode = '23505';
  END IF;

  IF EXISTS (SELECT 1 FROM public.vault_invitations i WHERE i.vault_id = p_vault AND i.status = 'pending' AND (i.invitee_auth_user_id = v_target.auth_user_id OR (v_kind = 'email' AND lower(i.email) = lower(v_q)) OR (v_kind = 'phone' AND i.phone = v_q))) THEN
    RAISE EXCEPTION 'An invitation has already been sent to this user' USING errcode = '23505';
  END IF;

  -- Create invitation row
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

  -- Attempt vault event log
  BEGIN
    PERFORM public.ino_log_vault_event(
      p_vault, 'invite_sent', 'invitation', v_row.id,
      v_q,
      jsonb_build_object('role', p_role, 'invited_by', v_inviter, 'target', v_target.full_name)
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- Attempt in-app notification to invitee
  BEGIN
    INSERT INTO public.in_app_notifications
      (user_id, title, body, kind, payload)
    VALUES
      (v_target.auth_user_id,
       'Vault Invitation',
       coalesce(v_inviter, 'Someone') || ' invited you to join ' || coalesce(v_vault_name, 'a Family Vault') || ' as ' || p_role,
       'vault_invite',
       jsonb_build_object('vault_id', p_vault, 'invitation_id', v_row.id, 'role', p_role));
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'vault_id', v_row.vault_id,
    'invited_by', v_row.invited_by,
    'invitee_auth_user_id', v_row.invitee_auth_user_id,
    'role', v_row.role,
    'status', v_row.status,
    'created_at', v_row.created_at,
    'expires_at', v_row.expires_at,
    'invited_name', v_target.full_name,
    'invited_by_name', v_inviter,
    'vault_name', v_vault_name
  );
END;
$$;

REVOKE ALL ON FUNCTION public.invite_ino_user_to_vault(UUID, TEXT, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.invite_ino_user_to_vault(UUID, TEXT, TEXT) TO authenticated;
