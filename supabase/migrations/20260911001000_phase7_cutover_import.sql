-- Phase 7 operational checkpoint for the one-way Cloudflare D1 import.
-- This table is deliberately inaccessible to application clients. The
-- service-role importer is the only writer.
create table public.legacy_import_runs (
  user_id uuid primary key references auth.users(id) on delete cascade,
  source text not null default 'cloudflare_d1'
    check (source = 'cloudflare_d1'),
  bundle_hash text not null check (bundle_hash ~ '^[0-9a-f]{64}$'),
  status text not null check (status in ('in_progress', 'completed')),
  row_counts jsonb not null default '{}'::jsonb
    check (jsonb_typeof(row_counts) = 'object'),
  started_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  check (
    (status = 'in_progress' and completed_at is null)
    or (status = 'completed' and completed_at is not null)
  )
);

alter table public.legacy_import_runs enable row level security;
alter table public.legacy_import_runs force row level security;
revoke all on public.legacy_import_runs from public, anon, authenticated;
grant select, insert, update, delete on public.legacy_import_runs to service_role;

create trigger legacy_import_runs_set_updated_at
before update on public.legacy_import_runs
for each row execute function public.set_updated_at();
