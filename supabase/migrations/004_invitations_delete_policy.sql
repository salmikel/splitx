create policy "invitations_delete" on public.invitations for delete
  using (public.is_group_member(group_id) and invited_by = auth.uid());
