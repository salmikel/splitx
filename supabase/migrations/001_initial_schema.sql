-- Enable pgcrypto for gen_random_bytes
create extension if not exists "pgcrypto";

-- ============================================================
-- TABLES
-- ============================================================

create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  email text not null,
  display_name text,
  created_at timestamptz default now() not null
);

create table public.groups (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now() not null
);

create table public.group_members (
  id uuid default gen_random_uuid() primary key,
  group_id uuid references public.groups(id) on delete cascade not null,
  user_id uuid references public.profiles(id) on delete cascade not null,
  joined_at timestamptz default now() not null,
  unique(group_id, user_id)
);

create table public.invitations (
  id uuid default gen_random_uuid() primary key,
  group_id uuid references public.groups(id) on delete cascade not null,
  invited_by uuid references public.profiles(id) on delete set null,
  email text not null,
  token text unique not null default encode(gen_random_bytes(32), 'hex'),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'expired')),
  created_at timestamptz default now() not null,
  expires_at timestamptz default (now() + interval '7 days') not null
);

create table public.transactions (
  id uuid default gen_random_uuid() primary key,
  group_id uuid references public.groups(id) on delete cascade not null,
  description text not null,
  amount numeric(10,2) not null check (amount > 0),
  paid_by uuid references public.profiles(id) on delete set null,
  type text not null default 'expense' check (type in ('expense', 'payment')),
  date date not null default current_date,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);

create table public.transaction_splits (
  id uuid default gen_random_uuid() primary key,
  transaction_id uuid references public.transactions(id) on delete cascade not null,
  user_id uuid references public.profiles(id) on delete cascade not null,
  percentage numeric(5,2) not null check (percentage >= 0 and percentage <= 100),
  amount numeric(10,2) not null,
  unique(transaction_id, user_id)
);

-- ============================================================
-- FUNCTIONS & TRIGGERS
-- ============================================================

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, new.email, split_part(new.email, '@', 1));
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Auto-update updated_at
create or replace function public.handle_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger transactions_updated_at
  before update on public.transactions
  for each row execute function public.handle_updated_at();

-- Helper: check if current user is a member of a group
create or replace function public.is_group_member(gid uuid)
returns boolean as $$
  select exists (
    select 1 from public.group_members
    where group_id = gid and user_id = auth.uid()
  );
$$ language sql security definer stable;

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.invitations enable row level security;
alter table public.transactions enable row level security;
alter table public.transaction_splits enable row level security;

-- Profiles
create policy "profiles_select" on public.profiles for select
  using (
    id = auth.uid() or
    exists (
      select 1 from public.group_members gm1
      join public.group_members gm2 on gm1.group_id = gm2.group_id
      where gm1.user_id = auth.uid() and gm2.user_id = profiles.id
    )
  );

create policy "profiles_update" on public.profiles for update
  using (id = auth.uid());

-- Groups
create policy "groups_select" on public.groups for select
  using (public.is_group_member(id));

create policy "groups_insert" on public.groups for insert
  with check (auth.uid() is not null and created_by = auth.uid());

create policy "groups_update" on public.groups for update
  using (created_by = auth.uid());

-- Group members
create policy "group_members_select" on public.group_members for select
  using (public.is_group_member(group_id));

create policy "group_members_insert" on public.group_members for insert
  with check (
    auth.uid() is not null and (
      user_id = auth.uid() or
      exists (select 1 from public.groups where id = group_id and created_by = auth.uid())
    )
  );

create policy "group_members_delete" on public.group_members for delete
  using (user_id = auth.uid());

-- Invitations
create policy "invitations_select" on public.invitations for select
  using (
    public.is_group_member(group_id) or
    email = (select email from public.profiles where id = auth.uid())
  );

create policy "invitations_insert" on public.invitations for insert
  with check (public.is_group_member(group_id) and invited_by = auth.uid());

create policy "invitations_update" on public.invitations for update
  using (public.is_group_member(group_id));

-- Transactions
create policy "transactions_select" on public.transactions for select
  using (public.is_group_member(group_id));

create policy "transactions_insert" on public.transactions for insert
  with check (public.is_group_member(group_id));

create policy "transactions_update" on public.transactions for update
  using (public.is_group_member(group_id));

create policy "transactions_delete" on public.transactions for delete
  using (public.is_group_member(group_id));

-- Transaction splits
create policy "splits_select" on public.transaction_splits for select
  using (exists (
    select 1 from public.transactions t
    where t.id = transaction_id and public.is_group_member(t.group_id)
  ));

create policy "splits_insert" on public.transaction_splits for insert
  with check (exists (
    select 1 from public.transactions t
    where t.id = transaction_id and public.is_group_member(t.group_id)
  ));

create policy "splits_update" on public.transaction_splits for update
  using (exists (
    select 1 from public.transactions t
    where t.id = transaction_id and public.is_group_member(t.group_id)
  ));

create policy "splits_delete" on public.transaction_splits for delete
  using (exists (
    select 1 from public.transactions t
    where t.id = transaction_id and public.is_group_member(t.group_id)
  ));
