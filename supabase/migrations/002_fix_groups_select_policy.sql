-- Fix groups_select policy: allow creator to see their newly created group
-- before they are added to group_members
drop policy if exists "groups_select" on public.groups;

create policy "groups_select" on public.groups for select
  using (public.is_group_member(id) or created_by = auth.uid());
