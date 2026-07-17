-- This project's `service_role` was missing standard table privileges on
-- `profiles` (only REFERENCES/TRIGGER/TRUNCATE were granted), so edge functions
-- — which run as service_role — got "permission denied for table profiles" when
-- writing `premium_until`. Grant the access service_role is meant to have.
grant select, insert, update, delete on public.profiles to service_role;
