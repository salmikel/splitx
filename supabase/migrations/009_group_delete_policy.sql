-- Allow a group's creator (admin) to delete it. Members, invitations,
-- transactions, and transaction_splits are removed automatically via their
-- ON DELETE CASCADE foreign keys. Without this policy, RLS blocks all deletes.
create policy "groups_delete" on public.groups for delete
  using (created_by = auth.uid());
