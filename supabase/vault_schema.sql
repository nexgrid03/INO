-- ===========================================================================
-- INO Password Vault — Supabase schema
-- Run once in the Supabase dashboard: SQL Editor → New query → paste → Run.
-- Everything sensitive is encrypted client-side; these tables only ever hold
-- ciphertext plus non-secret metadata. RLS restricts every row to its owner.
-- ===========================================================================

-- Per-user cryptography parameters (salt + verifier). Not secret.
create table if not exists public.vault_meta (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  kdf_salt   text        not null,           -- base64 PBKDF2 salt
  verifier   text        not null,           -- base64 AES-GCM of a known constant
  iterations integer     not null default 150000,
  created_at timestamptz not null default now()
);

-- One encrypted credential per row.
create table if not exists public.vault_items (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid        not null references auth.users (id) on delete cascade,
  title      text        not null,           -- clear (list + search)
  url        text,                           -- clear (optional)
  category   text        not null default 'other',
  favorite   boolean     not null default false,
  secret_enc text        not null,           -- base64 AES-GCM of {u,p,n}
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists vault_items_user_idx
  on public.vault_items (user_id, updated_at desc);

-- --- Row-Level Security -----------------------------------------------------
alter table public.vault_meta  enable row level security;
alter table public.vault_items enable row level security;

drop policy if exists vault_meta_owner on public.vault_meta;
create policy vault_meta_owner on public.vault_meta
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists vault_items_owner on public.vault_items;
create policy vault_items_owner on public.vault_items
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
