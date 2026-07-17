-- Persist a user's subscription expiry so the web app can honor the same
-- Premium entitlement (StoreKit on the iOS device remains the source of truth;
-- the iOS app writes this on entitlement refresh). Null / past = free.
alter table public.profiles add column if not exists premium_until timestamptz;
