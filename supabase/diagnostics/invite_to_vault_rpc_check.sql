-- ============================================================================
-- INO — diagnose "Could not find the function public.invite_to_vault(...)"
-- Run EACH block in the SQL editor of the project the app connects to
-- (dashboard URL ref MUST be:  ilfzppryyojoponkomrw).
-- ============================================================================

-- (2/9) Function exists, in which SCHEMA, and its ACL (privilege list).
--   proacl = NULL           -> default: PUBLIC has EXECUTE  (REST should see it)
--   proacl without authenticated/PUBLIC -> revoked; REST will HIDE it (PGRST202)
select p.proname,
       p.oid::regprocedure                as signature,
       n.nspname                          as schema,   -- must be 'public'
       p.proacl                           as acl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.proname = 'invite_to_vault';

-- (8) Decisive test: can the API role actually EXECUTE it?
--   FALSE  -> ROOT CAUSE = missing grant (see FIX A below)
--   TRUE   -> privilege is fine; cause is stale cache (FIX B) or exposed schema.
select has_function_privilege(
  'authenticated',
  'public.invite_to_vault(uuid,text,text,text)',
  'EXECUTE'
) as authenticated_can_execute;

-- (10) Which schemas PostgREST is told to expose (set on the API roles).
--   Must contain 'public'. If it doesn't, EVERY public RPC 404s.
select r.rolname,
       (select option_value
          from pg_options_to_table(r.rolconfig)
         where option_name = 'pgrst.db_schemas') as exposed_schemas
from pg_roles r
where r.rolname in ('authenticator','authenticated','anon');

-- (7) Are there duplicate/overloaded definitions (a second one could shadow)?
select oid::regprocedure from pg_proc where proname = 'invite_to_vault';
-- Expect EXACTLY one row: invite_to_vault(uuid,text,text,text)
