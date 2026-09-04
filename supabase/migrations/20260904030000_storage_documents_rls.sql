-- Migration: 20260904030000_storage_documents_rls.sql
-- Description: Enables RLS and creates explicit, version-controlled storage RLS policies
-- for the `documents` bucket across SELECT, INSERT, UPDATE, and DELETE operations,
-- restricting access strictly to the authenticated user's own folder path: (storage.foldername(name))[1] = auth.uid()::text.

-- 1. Ensure `documents` bucket exists, is private, and has 5 GB limit
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('documents', 'documents', false, 5368709120, NULL)
ON CONFLICT (id) DO UPDATE SET public = false;

-- 2. Enable Row Level Security on storage.objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- 3. Apply folder-isolated policies for SELECT, INSERT, UPDATE, DELETE
DO $$
BEGIN
  -- --------------------------------------------------------------------------
  -- SELECT Policy: Users can read files only inside their own <uid>/ folder
  -- --------------------------------------------------------------------------
  EXECUTE 'DROP POLICY IF EXISTS "documents owner read" ON storage.objects';
  EXECUTE $pol$
    CREATE POLICY "documents owner read" ON storage.objects
      FOR SELECT TO authenticated
      USING (
        bucket_id = 'documents'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  $pol$;

  -- --------------------------------------------------------------------------
  -- INSERT Policy: Users can upload files only into their own <uid>/ folder
  -- --------------------------------------------------------------------------
  EXECUTE 'DROP POLICY IF EXISTS "documents owner insert" ON storage.objects';
  EXECUTE $pol$
    CREATE POLICY "documents owner insert" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (
        bucket_id = 'documents'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  $pol$;

  -- --------------------------------------------------------------------------
  -- UPDATE Policy: Users can update metadata/files only in their own <uid>/ folder
  -- --------------------------------------------------------------------------
  EXECUTE 'DROP POLICY IF EXISTS "documents owner update" ON storage.objects';
  EXECUTE $pol$
    CREATE POLICY "documents owner update" ON storage.objects
      FOR UPDATE TO authenticated
      USING (
        bucket_id = 'documents'
        AND (storage.foldername(name))[1] = auth.uid()::text
      )
      WITH CHECK (
        bucket_id = 'documents'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  $pol$;

  -- --------------------------------------------------------------------------
  -- DELETE Policy: Users can delete files only inside their own <uid>/ folder
  -- --------------------------------------------------------------------------
  EXECUTE 'DROP POLICY IF EXISTS "documents owner delete" ON storage.objects';
  EXECUTE $pol$
    CREATE POLICY "documents owner delete" ON storage.objects
      FOR DELETE TO authenticated
      USING (
        bucket_id = 'documents'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  $pol$;

EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE WARNING 'Could not create storage policies automatically due to permissions. Run this script in the Supabase SQL Editor.';
END $$;

NOTIFY pgrst, 'reload schema';
