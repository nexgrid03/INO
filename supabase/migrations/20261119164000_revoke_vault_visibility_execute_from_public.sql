-- Close the default PUBLIC execute grant on the vault share and visibility
-- RPCs. The app calls them only with a signed-in session. anon and service_role
-- are not granted.

revoke execute on function public.share_vault_item(
  uuid, text, text, text, bigint, text, text, text, jsonb, jsonb, text, boolean
) from public, anon;

grant execute on function public.share_vault_item(
  uuid, text, text, text, bigint, text, text, text, jsonb, jsonb, text, boolean
) to authenticated;

revoke execute on function public.set_vault_document_visibility(uuid, boolean)
  from public, anon;

grant execute on function public.set_vault_document_visibility(uuid, boolean)
  to authenticated;

revoke execute on function public.set_vault_wallet_visibility(uuid, text, boolean)
  from public, anon;

grant execute on function public.set_vault_wallet_visibility(uuid, text, boolean)
  to authenticated;
