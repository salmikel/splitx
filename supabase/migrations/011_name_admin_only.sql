-- Lock both the group name and currency to the creator (admin). The
-- member-editable settings (default payer / split percentages) stay open, so
-- this replaces the currency-only trigger with a combined one.
create or replace function public.enforce_group_admin_only()
returns trigger as $$
begin
  if old.created_by is distinct from auth.uid()
     and (new.currency is distinct from old.currency
          or new.name is distinct from old.name) then
    raise exception 'Only the group creator can change the group name or currency';
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists groups_currency_admin_only on public.groups;
drop trigger if exists groups_admin_only on public.groups;
create trigger groups_admin_only
  before update on public.groups
  for each row execute function public.enforce_group_admin_only();

drop function if exists public.enforce_currency_admin_only();
