create policy "profiles_insert" on public.profiles for insert
  with check (id = auth.uid());
