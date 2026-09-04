-- ============================================================================
-- INO - User sessions table for real device session management
-- ----------------------------------------------------------------------------
-- Replaces local-only "trusted devices" with server-tracked active sessions.
-- Allows users to view active sessions, revoke specific device sessions,
-- or sign out all other devices.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_sessions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  UUID DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  device_id   TEXT NOT NULL,
  device_name TEXT NOT NULL,
  platform    TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen   TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked     BOOLEAN NOT NULL DEFAULT false,
  CONSTRAINT user_sessions_user_device_unique UNIQUE (user_id, device_id)
);

ALTER TABLE public.user_sessions ADD COLUMN IF NOT EXISTS session_id UUID DEFAULT gen_random_uuid();
UPDATE public.user_sessions SET session_id = id WHERE session_id IS NULL;

COMMENT ON TABLE public.user_sessions IS
  'Tracks active user device sessions for real session management and remote sign-out.';

CREATE INDEX IF NOT EXISTS user_sessions_user_id_idx ON public.user_sessions (user_id);

ALTER TABLE public.user_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_sessions: owner reads own" ON public.user_sessions;
DROP POLICY IF EXISTS "user_sessions: owner inserts own" ON public.user_sessions;
DROP POLICY IF EXISTS "user_sessions: owner updates own" ON public.user_sessions;
DROP POLICY IF EXISTS "user_sessions: owner deletes own" ON public.user_sessions;

CREATE POLICY "user_sessions: owner reads own" ON public.user_sessions
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "user_sessions: owner inserts own" ON public.user_sessions
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_sessions: owner updates own" ON public.user_sessions
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_sessions: owner deletes own" ON public.user_sessions
  FOR DELETE USING (user_id = auth.uid());
