-- Migration: 20260904040000_encrypt_government_ids.sql
-- Description: Sanitizes and masks existing historical government ID numbers (Aadhaar, PAN, Passport, DL)
-- across all wallet tables so that no plaintext unmasked identifiers remain in database storage.

CREATE OR REPLACE FUNCTION public.ino_mask_identifier(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_cleaned text;
  v_digits text;
  v_len int;
BEGIN
  IF p_raw IS NULL OR trim(p_raw) = '' THEN
    RETURN p_raw;
  END IF;

  v_cleaned := trim(p_raw);
  IF v_cleaned LIKE 'enc:%' OR v_cleaned LIKE 'XXXX%' OR v_cleaned LIKE '%****%' THEN
    RETURN v_cleaned;
  END IF;

  v_digits := regexp_replace(v_cleaned, '\D', '', 'g');
  v_len := length(v_cleaned);

  -- 1. Aadhaar (12 digits) -> XXXX XXXX 1234
  IF length(v_digits) = 12 THEN
    RETURN 'XXXX XXXX ' || right(v_digits, 4);
  END IF;

  -- 2. PAN Card (10 chars: 5 letters + 4 digits + 1 letter, e.g. ABCDE1234F) -> ABCDE****F
  IF v_len = 10 AND v_cleaned ~* '^[A-Z]{5}[0-9]{4}[A-Z]$' THEN
    RETURN upper(left(v_cleaned, 5)) || '****' || upper(right(v_cleaned, 1));
  END IF;

  -- 3. Passport (8-9 chars, e.g. P1234567) -> P*****67
  IF v_len >= 8 AND v_len <= 9 AND v_cleaned ~* '^[A-Z]' THEN
    RETURN upper(left(v_cleaned, 1)) || repeat('*', v_len - 3) || upper(right(v_cleaned, 2));
  END IF;

  -- 4. General / Driving License / Voter ID -> show last 4 chars
  IF v_len > 4 THEN
    RETURN repeat('*', v_len - 4) || right(v_cleaned, 4);
  END IF;

  RETURN v_cleaned;
END;
$$;

-- Revoke public execution of utility function
REVOKE EXECUTE ON FUNCTION public.ino_mask_identifier(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ino_mask_identifier(text) TO authenticated, service_role;

-- Apply to all per-wallet tables containing record_number
UPDATE public.w_identity_wallet SET record_number = public.ino_mask_identifier(record_number) WHERE record_number IS NOT NULL AND record_number != '';
UPDATE public.w_tax_wallet SET record_number = public.ino_mask_identifier(record_number) WHERE record_number IS NOT NULL AND record_number != '';
UPDATE public.w_vehicle_wallet SET record_number = public.ino_mask_identifier(record_number) WHERE record_number IS NOT NULL AND record_number != '';
UPDATE public.w_document_wallet SET record_number = public.ino_mask_identifier(record_number) WHERE record_number IS NOT NULL AND record_number != '';
UPDATE public.w_property_wallet SET record_number = public.ino_mask_identifier(record_number) WHERE record_number IS NOT NULL AND record_number != '';
UPDATE public.w_investment_wallet SET record_number = public.ino_mask_identifier(record_number) WHERE record_number IS NOT NULL AND record_number != '';
UPDATE public.w_card_wallet SET record_number = public.ino_mask_identifier(record_number) WHERE record_number IS NOT NULL AND record_number != '';
UPDATE public.w_health_wallet SET record_number = public.ino_mask_identifier(record_number) WHERE record_number IS NOT NULL AND record_number != '';

-- Rebuild union view if necessary
SELECT public.ino_rebuild_documents_view();
