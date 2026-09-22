-- 在 Supabase 專案的 SQL Editor 貼上整段執行一次。

-- 每次訓練一筆
create table if not exists public.sessions (
  id         bigint      not null,               -- 前端產生的 Date.now()
  user_id    uuid        not null references auth.users(id) on delete cascade,
  t          timestamptz not null,
  data       jsonb       not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

-- 每位使用者一筆：重量、替代動作、目前選的課表
create table if not exists public.prefs (
  user_id    uuid        primary key references auth.users(id) on delete cascade,
  data       jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.sessions enable row level security;
alter table public.prefs    enable row level security;

-- 只能讀寫自己的資料
drop policy if exists "own sessions" on public.sessions;
create policy "own sessions" on public.sessions
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own prefs" on public.prefs;
create policy "own prefs" on public.prefs
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index if not exists sessions_user_t on public.sessions (user_id, t desc);
