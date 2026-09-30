-- Everytime Match - initial Supabase schema
-- Run this whole file in Supabase Dashboard > SQL Editor.
-- This schema is designed for browser access with a Supabase publishable key.
-- RLS protects private rows; NEVER put a Supabase secret key in frontend code.

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null check (char_length(nickname) between 1 and 20),
  grade text not null check (grade in ('1학년','2학년','3학년','4학년','졸업생')),
  mbti text check (
    mbti is null or mbti in (
      'INTJ','INTP','ENTJ','ENTP',
      'INFJ','INFP','ENFJ','ENFP',
      'ISTJ','ISFJ','ESTJ','ESFJ',
      'ISTP','ISFP','ESTP','ESFP'
    )
  ),
  gender text not null check (gender in ('남성','여성')),
  preference text not null check (preference in ('남성','여성')),
  bio text not null check (char_length(bio) between 1 and 120),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.private_contacts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  contact_type text not null check (contact_type in ('Instagram','카카오 오픈채팅')),
  contact_value text not null check (char_length(contact_value) between 1 and 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.likes (
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_user, to_user),
  check (from_user <> to_user)
);

create table if not exists public.blocks (
  blocker uuid not null references auth.users(id) on delete cascade,
  blocked uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);

create table if not exists public.reports (
  id bigint generated always as identity primary key,
  reporter uuid not null references auth.users(id) on delete cascade,
  reported uuid not null references auth.users(id) on delete cascade,
  reason text,
  created_at timestamptz not null default now(),
  check (reporter <> reported)
);

-- Helper: true only when both users liked each other.
-- SECURITY DEFINER is used so the reciprocal like can be checked without exposing
-- every user's incoming likes to the browser.
create or replace function public.is_match(target_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    auth.uid() is not null
    and target_user is not null
    and target_user <> auth.uid()
    and exists (
      select 1
      from public.likes a
      where a.from_user = auth.uid()
        and a.to_user = target_user
    )
    and exists (
      select 1
      from public.likes b
      where b.from_user = target_user
        and b.to_user = auth.uid()
    );
$$;

-- Helper: hides profiles when either side has blocked the other.
create or replace function public.is_blocked_between(target_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    auth.uid() is null
    or exists (
      select 1
      from public.blocks b
      where (b.blocker = auth.uid() and b.blocked = target_user)
         or (b.blocker = target_user and b.blocked = auth.uid())
    );
$$;

revoke all on function public.is_match(uuid) from public;
revoke all on function public.is_blocked_between(uuid) from public;
grant execute on function public.is_match(uuid) to authenticated;
grant execute on function public.is_blocked_between(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.private_contacts enable row level security;
alter table public.likes enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;

-- Start from least privilege.
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.private_contacts from anon, authenticated;
revoke all on table public.likes from anon, authenticated;
revoke all on table public.blocks from anon, authenticated;
revoke all on table public.reports from anon, authenticated;

grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.private_contacts to authenticated;
grant select, insert, delete on table public.likes to authenticated;
grant select, insert, delete on table public.blocks to authenticated;
grant insert on table public.reports to authenticated;

-- PROFILES
drop policy if exists "read own profile" on public.profiles;
create policy "read own profile"
on public.profiles for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "read discoverable profiles" on public.profiles;
create policy "read discoverable profiles"
on public.profiles for select
to authenticated
using (
  is_active
  and (select auth.uid()) <> user_id
  and not public.is_blocked_between(user_id)
);

drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile"
on public.profiles for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "update own profile" on public.profiles;
create policy "update own profile"
on public.profiles for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "delete own profile" on public.profiles;
create policy "delete own profile"
on public.profiles for delete
to authenticated
using ((select auth.uid()) = user_id);

-- PRIVATE CONTACTS
-- A user can read their own contact.
-- Another user's contact becomes readable only after a mutual like.
drop policy if exists "read own or matched contact" on public.private_contacts;
create policy "read own or matched contact"
on public.private_contacts for select
to authenticated
using (
  (select auth.uid()) = user_id
  or public.is_match(user_id)
);

drop policy if exists "insert own contact" on public.private_contacts;
create policy "insert own contact"
on public.private_contacts for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "update own contact" on public.private_contacts;
create policy "update own contact"
on public.private_contacts for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "delete own contact" on public.private_contacts;
create policy "delete own contact"
on public.private_contacts for delete
to authenticated
using ((select auth.uid()) = user_id);

-- LIKES
-- Users can see and manage only likes they sent themselves.
drop policy if exists "read own outgoing likes" on public.likes;
create policy "read own outgoing likes"
on public.likes for select
to authenticated
using ((select auth.uid()) = from_user);

drop policy if exists "send own like" on public.likes;
create policy "send own like"
on public.likes for insert
to authenticated
with check (
  (select auth.uid()) = from_user
  and from_user <> to_user
  and not public.is_blocked_between(to_user)
);

drop policy if exists "remove own like" on public.likes;
create policy "remove own like"
on public.likes for delete
to authenticated
using ((select auth.uid()) = from_user);

-- BLOCKS
drop policy if exists "read own blocks" on public.blocks;
create policy "read own blocks"
on public.blocks for select
to authenticated
using ((select auth.uid()) = blocker);

drop policy if exists "create own block" on public.blocks;
create policy "create own block"
on public.blocks for insert
to authenticated
with check ((select auth.uid()) = blocker);

drop policy if exists "remove own block" on public.blocks;
create policy "remove own block"
on public.blocks for delete
to authenticated
using ((select auth.uid()) = blocker);

-- REPORTS
-- Users may submit reports, but ordinary clients cannot list reports.
drop policy if exists "submit own report" on public.reports;
create policy "submit own report"
on public.reports for insert
to authenticated
with check ((select auth.uid()) = reporter);

-- Helpful indexes
create index if not exists likes_to_user_idx on public.likes(to_user);
create index if not exists blocks_blocked_idx on public.blocks(blocked);
create index if not exists profiles_active_idx on public.profiles(is_active);
