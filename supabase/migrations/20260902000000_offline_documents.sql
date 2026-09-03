-- ============================================================================
-- INO - Offline Documents Table
-- ----------------------------------------------------------------------------
-- Backs `OfflineDocumentStore` (lib/services/offline_document_store.dart).
--
-- While offline copies live primarily on-device (under the app documents folder
-- and indexed in SharedPreferences), this table provides server-side persistence
-- and multi-device sync of offline document metadata for authenticated users.
-- ============================================================================

begin;

create table if not exists public.offline_documents (
  id           uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  document_id  text not null,
  name         text not null,
  wallet       text not null,
  category     text,
  object_path  text not null,
  local_path   text not null,
  size_bytes   bigint not null default 0,
  saved_at     timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint uq_offline_documents_user_doc unique (auth_user_id, document_id)
);

-- Indexes for quick lookup
create index if not exists idx_offline_docs_user on public.offline_documents(auth_user_id);
create index if not exists idx_offline_docs_user_saved on public.offline_documents(auth_user_id, saved_at desc);

-- Keep updated_at fresh on modifications
drop trigger if exists tg_offline_documents_updated_at on public.offline_documents;
create trigger tg_offline_documents_updated_at
  before update on public.offline_documents
  for each row execute function public.tg_set_updated_at();

-- Enable Row Level Security
alter table public.offline_documents enable row level security;

-- RLS Policies
create policy "offline_docs_select_own"
  on public.offline_documents
  for select
  to authenticated
  using (auth.uid() = auth_user_id);

create policy "offline_docs_insert_own"
  on public.offline_documents
  for insert
  to authenticated
  with check (auth.uid() = auth_user_id);

create policy "offline_docs_update_own"
  on public.offline_documents
  for update
  to authenticated
  using (auth.uid() = auth_user_id)
  with check (auth.uid() = auth_user_id);

create policy "offline_docs_delete_own"
  on public.offline_documents
  for delete
  to authenticated
  using (auth.uid() = auth_user_id);

commit;
