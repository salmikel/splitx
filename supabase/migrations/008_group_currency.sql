-- Per-group currency. Each group has a single currency chosen by its creator
-- (admin); all amounts in the group are displayed in it. Defaults to USD so
-- existing groups keep their current behavior.
alter table public.groups
  add column if not exists currency text not null default 'USD';
