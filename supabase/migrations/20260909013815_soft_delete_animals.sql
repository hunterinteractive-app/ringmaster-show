alter table public.animals
  add column if not exists deleted_at timestamptz;

comment on column public.animals.deleted_at is
  'When set, hides the saved animal from normal animal lists without changing historical entries.';

create index if not exists animals_active_owner_user_id_idx
  on public.animals (owner_user_id)
  where deleted_at is null;

create index if not exists animals_active_exhibitor_id_idx
  on public.animals (exhibitor_id)
  where deleted_at is null;
