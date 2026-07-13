-- =============================================================
--  Feedyard DM Tracker  —  Supabase schema + Row Level Security
--  Run this ONCE:  Supabase dashboard > SQL Editor > New query >
--  paste all of this > Run.
-- =============================================================

-- 1. FEEDYARDS  (one row per yard) ----------------------------
create table if not exists public.feedyards (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  created_at timestamptz not null default now()
);

-- 2. PROFILES  (one row per login; created automatically) -----
--    feedyard_id  = which yard this login belongs to
--    is_admin     = true only for you, the developer
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  feedyard_id uuid references public.feedyards(id) on delete set null,
  is_admin    boolean not null default false,
  created_at  timestamptz not null default now()
);

-- 3. FEEDSTUFFS  (ingredients & rations, owned by a yard) -----
create table if not exists public.feedstuffs (
  id          uuid primary key default gen_random_uuid(),
  feedyard_id uuid not null references public.feedyards(id) on delete cascade,
  name        text not null,
  kind        text not null check (kind in ('ingredient','ration')),
  created_at  timestamptz not null default now()
);

-- 4. DM RECORDS  (the measurements) ---------------------------
create table if not exists public.dm_records (
  id           uuid primary key default gen_random_uuid(),
  feedyard_id  uuid not null references public.feedyards(id) on delete cascade,
  feedstuff_id uuid not null references public.feedstuffs(id) on delete cascade,
  sample_date  date not null,
  dm_percent   numeric(5,2) not null check (dm_percent >= 0 and dm_percent <= 100),
  created_by   uuid references auth.users(id),
  created_at   timestamptz not null default now()
);

create index if not exists dm_records_feedstuff_idx on public.dm_records(feedstuff_id);
create index if not exists dm_records_feedyard_idx  on public.dm_records(feedyard_id);
create index if not exists feedstuffs_feedyard_idx  on public.feedstuffs(feedyard_id);

-- 5. Auto-create a profile row whenever a login is created ----
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 6. Helper functions  (security definer avoids RLS recursion)-
create or replace function public.current_feedyard_id()
returns uuid language sql stable security definer set search_path = public as $$
  select feedyard_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

-- 7. Turn on Row Level Security -------------------------------
alter table public.feedyards  enable row level security;
alter table public.profiles   enable row level security;
alter table public.feedstuffs enable row level security;
alter table public.dm_records enable row level security;

-- 8. Policies  ------------------------------------------------
--    Rule everywhere: admin can touch everything; a yard user
--    can only touch rows belonging to their own yard.

-- FEEDYARDS
drop policy if exists feedyards_select on public.feedyards;
create policy feedyards_select on public.feedyards for select
  using ( is_admin() or id = current_feedyard_id() );
drop policy if exists feedyards_admin_all on public.feedyards;
create policy feedyards_admin_all on public.feedyards for all
  using ( is_admin() ) with check ( is_admin() );

-- PROFILES  (users cannot edit their own row -> no self-promotion)
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using ( id = auth.uid() or is_admin() );
drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles for update
  using ( is_admin() ) with check ( is_admin() );

-- FEEDSTUFFS
drop policy if exists feedstuffs_select on public.feedstuffs;
create policy feedstuffs_select on public.feedstuffs for select
  using ( is_admin() or feedyard_id = current_feedyard_id() );
drop policy if exists feedstuffs_insert on public.feedstuffs;
create policy feedstuffs_insert on public.feedstuffs for insert
  with check ( is_admin() or feedyard_id = current_feedyard_id() );
drop policy if exists feedstuffs_update on public.feedstuffs;
create policy feedstuffs_update on public.feedstuffs for update
  using ( is_admin() or feedyard_id = current_feedyard_id() )
  with check ( is_admin() or feedyard_id = current_feedyard_id() );
drop policy if exists feedstuffs_delete on public.feedstuffs;
create policy feedstuffs_delete on public.feedstuffs for delete
  using ( is_admin() or feedyard_id = current_feedyard_id() );

-- DM RECORDS
drop policy if exists dm_select on public.dm_records;
create policy dm_select on public.dm_records for select
  using ( is_admin() or feedyard_id = current_feedyard_id() );
drop policy if exists dm_insert on public.dm_records;
create policy dm_insert on public.dm_records for insert
  with check ( is_admin() or feedyard_id = current_feedyard_id() );
drop policy if exists dm_update on public.dm_records;
create policy dm_update on public.dm_records for update
  using ( is_admin() or feedyard_id = current_feedyard_id() )
  with check ( is_admin() or feedyard_id = current_feedyard_id() );
drop policy if exists dm_delete on public.dm_records;
create policy dm_delete on public.dm_records for delete
  using ( is_admin() or feedyard_id = current_feedyard_id() );

-- 9. Grants  (explicit, to satisfy the 2026 Data API grant rule)
grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant execute on all functions in schema public to authenticated;

-- =============================================================
--  AFTER running the above, make yourself the developer/admin.
--  Create your own login first (Authentication > Users > Add user),
--  then run this once, with your email:
--
--    update public.profiles set is_admin = true
--    where email = 'you@example.com';
-- =============================================================
