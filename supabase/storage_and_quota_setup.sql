-- ============================================================================
-- INO: Real-time 5 GB Storage Quota Calculation
-- Safe to run directly in the Supabase SQL Editor.
-- This does NOT touch table ownership and avoids 42501 permission errors.
-- ============================================================================

create or replace function public.get_user_storage_usage()
returns jsonb
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v_used_bytes bigint := 0;
  v_file_count int := 0;
begin
  select 
    coalesce(sum((metadata->>'size')::bigint), 0),
    count(*)
  into v_used_bytes, v_file_count
  from storage.objects
  where bucket_id = 'documents'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or owner = auth.uid()
    );

  return jsonb_build_object(
    'used_bytes', v_used_bytes,
    'file_count', v_file_count
  );
end;
$$;

grant execute on function public.get_user_storage_usage() to authenticated, service_role;

notify pgrst, 'reload schema';
