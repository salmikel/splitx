-- LOCK-DOWN (do NOT apply until the app-store-notifications edge function is
-- verified working with Apple sandbox notifications).
--
-- Makes `profiles.premium_until` writable only by the service role (the
-- app-store-notifications function). Blocks users from forging Premium via the
-- normal profile-update RLS path. Apply this AND remove the iOS client-side
-- sync (SubscriptionManager.syncEntitlementToProfile) at the same time, so the
-- verified Apple notification becomes the single source of truth.
create or replace function public.prevent_premium_tampering()
returns trigger as $$
begin
  if new.premium_until is distinct from old.premium_until
     and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'premium_until can only be set by the server';
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists profiles_premium_guard on public.profiles;
create trigger profiles_premium_guard
  before update on public.profiles
  for each row execute function public.prevent_premium_tampering();
