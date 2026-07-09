-- Lock the group currency to the creator (admin), without restricting the
-- other member-editable group settings (default payer / split percentages).
--
-- The groups_update RLS policy intentionally allows any member to update the
-- row (to edit split defaults). RLS can't restrict a single column, so a
-- BEFORE UPDATE trigger rejects any change to `currency` unless the caller is
-- the group's creator. Updates that leave currency unchanged pass through, so
-- members can still edit defaults.
create or replace function public.enforce_currency_admin_only()
returns trigger as $$
begin
  if new.currency is distinct from old.currency
     and old.created_by is distinct from auth.uid() then
    raise exception 'Only the group creator can change the currency';
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists groups_currency_admin_only on public.groups;
create trigger groups_currency_admin_only
  before update on public.groups
  for each row execute function public.enforce_currency_admin_only();
