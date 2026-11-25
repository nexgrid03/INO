
-- Authenticated users may read audit logs but cannot modify them.
REVOKE INSERT, UPDATE, DELETE
ON TABLE public.vault_invite_audit_logs
FROM authenticated;

GRANT SELECT
ON TABLE public.vault_invite_audit_logs
TO authenticated;
