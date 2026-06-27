alter table public.groups
  add column if not exists default_paid_by uuid references public.profiles(id) on delete set null,
  add column if not exists default_splits jsonb default '{}' not null;
