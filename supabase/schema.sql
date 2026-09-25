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

-- Apple Watch 配對：手機網頁產生 8 位數配對碼，手錶輸入後換到自己的登入（10 分鐘內有效、只能用一次）
create table if not exists public.watch_link (
  code          text        primary key,
  user_id       uuid        not null references auth.users(id) on delete cascade,
  refresh_token text        not null,
  email         text,
  created_at    timestamptz not null default now()
);
alter table public.watch_link enable row level security;
drop policy if exists "own watch_link insert" on public.watch_link;
create policy "own watch_link insert" on public.watch_link
  for insert to authenticated with check (auth.uid() = user_id);

create or replace function public.claim_watch_link(p_code text)
returns table(r_token text, r_email text)
language plpgsql security definer set search_path = public as $$
begin
  delete from public.watch_link where created_at < now() - interval '10 minutes';
  return query delete from public.watch_link w where w.code = p_code returning w.refresh_token, w.email;
end $$;
revoke all on function public.claim_watch_link(text) from public;
grant execute on function public.claim_watch_link(text) to anon, authenticated;
