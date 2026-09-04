-- Migration: 20260904040000_encrypt_government_ids.sql
-- DISABLED PER SECURITY AND DATA INTEGRITY POLICY:
-- Real Aadhaar/PAN and government ID numbers must NEVER be irreversibly overwritten or masked
-- in the database write-path. Storing masked strings ('XXXX XXXX 1234') causes permanent data loss
-- for legitimate user records.
--
-- Masking is strictly enforced in the client-side presentation layer (IdentifierMasker)
-- with biometric authentication gates for reveal and clipboard copy.
--
-- This file is intentionally a safe no-op to preserve database integrity.

DO $$
BEGIN
  -- Intentionally blank no-op. Preserves raw user records.
  NULL;
END;
$$;
