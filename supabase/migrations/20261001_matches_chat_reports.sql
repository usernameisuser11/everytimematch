-- Everytime Match
-- 2026-10-01: persistent matches + internal text chat + report flow
--
-- Run once in Supabase Dashboard > SQL Editor after:
--   supabase/schema.sql
--   supabase/migrations/20261001_discovery_limits.sql
--
-- This migration:
-- - persists mutual likes as matches
-- - backfills existing reciprocal likes
-- - adds internal text messages
-- - makes messages accessible only to active match participants
-- - adds unmatch/block RPC
-- - adds report categories and optional reported-message evidence
-- - removes legacy external contact data

begin;

create extension if not exists pgcrypto;

-- =========================================================
-- 1. Persistent matches
-- =========================================================

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active','ended','blocked')),
  matched_at timestamptz not null default now(),
  ended_at timestamptz,
  check (user_a <> user_b),
  check (user_a::text < user_b::text),
  unique (user_a, user_b)
);

create index if not exists matches_user_a_idx on public.matches(user_a);
create index if not exists matches_user_b_idx on public.matches(user_b);
create index if not exists matches_status_idx on public.matches(status);

-- Existing reciprocal likes become persistent matches.
insert into public.matches(user_a, user_b)
select distinct
  case when l.from_user::text < l.to_user::text then l.from_user else l.to_user end,
  case when l.from_user::text < l.to_user::text then l.to_user else l.from_user end
from public.likes l
where exists (
  select 1
  from public.likes r
  where r.from_user = l.to_user
    and r.to_user = l.from_user
)
on conflict (user_a, user_b) do nothing;

create or replace function public.create_match_on_mutual_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_a uuid;
  v_b uuid;
begin
  if exists (
    select 1
    from public.likes r
    where r.from_user = new.to_user
      and r.to_user = new.from_user
  ) then
    if new.from_user::text < new.to_user::text then
      v_a := new.from_user;
      v_b := new.to_user;
    else
      v_a := new.to_user;
      v_b := new.from_user;
    end if;

    insert into public.matches(user_a, user_b, status, matched_at, ended_at)
    values (v_a, v_b, 'active', now(), null)
    on conflict (user_a, user_b)
    do update set
      status = 'active',
      matched_at = now(),
      ended_at = null;
  end if;

  return new;
end;
$$;

drop trigger if exists likes_create_match_trigger on public.likes;
create trigger likes_create_match_trigger
after insert on public.likes
for each row
execute function public.create_match_on_mutual_like();

-- =========================================================
-- 2. Internal text chat
-- =========================================================

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  content text not null check (char_length(btrim(content)) between 1 and 1000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists messages_match_created_idx
  on public.messages(match_id, created_at);

create or replace function public.can_access_match(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.matches m
    where m.id = p_match_id
      and m.status = 'active'
      and (m.user_a = auth.uid() or m.user_b = auth.uid())
  );
$$;

alter table public.matches enable row level security;
alter table public.messages enable row level security;

revoke all on table public.matches from anon, authenticated;
revoke all on table public.messages from anon, authenticated;

grant select on table public.matches to authenticated;
grant select, insert on table public.messages to authenticated;

drop policy if exists "participants read active matches" on public.matches;
create policy "participants read active matches"
on public.matches for select
to authenticated
using (
  status = 'active'
  and (user_a = auth.uid() or user_b = auth.uid())
);

drop policy if exists "participants read messages" on public.messages;
create policy "participants read messages"
on public.messages for select
to authenticated
using (public.can_access_match(match_id));

drop policy if exists "participants send messages" on public.messages;
create policy "participants send messages"
on public.messages for insert
to authenticated
with check (
  sender_id = auth.uid()
  and public.can_access_match(match_id)
);

-- =========================================================
-- 3. Match list RPC
-- =========================================================

create or replace function public.get_my_matches()
returns table (
  match_id uuid,
  other_user_id uuid,
  nickname text,
  grade text,
  mbti text,
  relationship_intent text,
  bio text,
  matched_at timestamptz,
  last_message text,
  last_message_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    m.id,
    case when m.user_a = auth.uid() then m.user_b else m.user_a end,
    p.nickname,
    p.grade,
    p.mbti,
    p.relationship_intent,
    p.bio,
    m.matched_at,
    (
      select msg.content
      from public.messages msg
      where msg.match_id = m.id
      order by msg.created_at desc
      limit 1
    ),
    (
      select msg.created_at
      from public.messages msg
      where msg.match_id = m.id
      order by msg.created_at desc
      limit 1
    )
  from public.matches m
  join public.profiles p
    on p.user_id = case when m.user_a = auth.uid() then m.user_b else m.user_a end
  where m.status = 'active'
    and (m.user_a = auth.uid() or m.user_b = auth.uid())
    and not public.is_blocked_between(p.user_id)
  order by coalesce(
    (
      select max(msg.created_at)
      from public.messages msg
      where msg.match_id = m.id
    ),
    m.matched_at
  ) desc;
$$;

-- =========================================================
-- 4. Unmatch / block
-- =========================================================

create or replace function public.end_match(
  p_match_id uuid,
  p_block boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_other uuid;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select
    case when m.user_a = v_uid then m.user_b else m.user_a end
  into v_other
  from public.matches m
  where m.id = p_match_id
    and m.status = 'active'
    and (m.user_a = v_uid or m.user_b = v_uid)
  for update;

  if not found then
    raise exception 'MATCH_NOT_FOUND';
  end if;

  update public.matches
  set
    status = case when p_block then 'blocked' else 'ended' end,
    ended_at = now()
  where id = p_match_id;

  -- Remove mutual likes so a future match requires both people to like again.
  delete from public.likes
  where (from_user = v_uid and to_user = v_other)
     or (from_user = v_other and to_user = v_uid);

  if p_block then
    insert into public.blocks(blocker, blocked)
    values (v_uid, v_other)
    on conflict (blocker, blocked) do nothing;
  end if;

  return true;
end;
$$;

-- =========================================================
-- 5. Reports
-- =========================================================

alter table public.reports
  add column if not exists category text;

alter table public.reports
  add column if not exists match_id uuid;

alter table public.reports
  add column if not exists message_id uuid;

alter table public.reports
  add column if not exists status text not null default 'pending';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'reports_category_check'
      and conrelid = 'public.reports'::regclass
  ) then
    alter table public.reports
      add constraint reports_category_check
      check (
        category is null
        or category in ('괴롭힘/욕설','성적 발언','사칭','스팸/홍보','부적절한 콘텐츠','기타')
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'reports_status_check'
      and conrelid = 'public.reports'::regclass
  ) then
    alter table public.reports
      add constraint reports_status_check
      check (status in ('pending','reviewing','warned','suspended','banned','dismissed'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'reports_match_id_fkey'
      and conrelid = 'public.reports'::regclass
  ) then
    alter table public.reports
      add constraint reports_match_id_fkey
      foreign key (match_id) references public.matches(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'reports_message_id_fkey'
      and conrelid = 'public.reports'::regclass
  ) then
    alter table public.reports
      add constraint reports_message_id_fkey
      foreign key (message_id) references public.messages(id) on delete set null;
  end if;
end
$$;

-- Reports go through the RPC below so reporter identity and evidence are verified.
revoke insert on table public.reports from authenticated;
drop policy if exists "submit own report" on public.reports;

create or replace function public.submit_report(
  p_reported uuid,
  p_category text,
  p_reason text default null,
  p_message_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_match_id uuid;
  v_report_id bigint;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_reported is null or p_reported = v_uid then
    raise exception 'INVALID_TARGET';
  end if;

  if p_category not in (
    '괴롭힘/욕설',
    '성적 발언',
    '사칭',
    '스팸/홍보',
    '부적절한 콘텐츠',
    '기타'
  ) then
    raise exception 'INVALID_REPORT_CATEGORY';
  end if;

  if p_message_id is not null then
    select msg.match_id
    into v_match_id
    from public.messages msg
    join public.matches m on m.id = msg.match_id
    where msg.id = p_message_id
      and msg.sender_id = p_reported
      and (m.user_a = v_uid or m.user_b = v_uid)
      and (m.user_a = p_reported or m.user_b = p_reported);

    if not found then
      raise exception 'INVALID_REPORT_MESSAGE';
    end if;
  else
    select m.id
    into v_match_id
    from public.matches m
    where (m.user_a = v_uid and m.user_b = p_reported)
       or (m.user_a = p_reported and m.user_b = v_uid)
    order by m.matched_at desc
    limit 1;
  end if;

  insert into public.reports(
    reporter,
    reported,
    reason,
    category,
    match_id,
    message_id,
    status
  )
  values (
    v_uid,
    p_reported,
    nullif(btrim(coalesce(p_reason, '')), ''),
    p_category,
    v_match_id,
    p_message_id,
    'pending'
  )
  returning id into v_report_id;

  -- Immediate separation for the reporter.
  insert into public.blocks(blocker, blocked)
  values (v_uid, p_reported)
  on conflict (blocker, blocked) do nothing;

  update public.matches
  set status = 'blocked', ended_at = now()
  where status = 'active'
    and (
      (user_a = v_uid and user_b = p_reported)
      or
      (user_a = p_reported and user_b = v_uid)
    );

  delete from public.likes
  where (from_user = v_uid and to_user = p_reported)
     or (from_user = p_reported and to_user = v_uid);

  return v_report_id;
end;
$$;

-- =========================================================
-- 6. Legacy external contacts are no longer collected
-- =========================================================

drop table if exists public.private_contacts cascade;

-- =========================================================
-- 7. Function permissions
-- =========================================================

revoke all on function public.can_access_match(uuid) from public;
revoke all on function public.get_my_matches() from public;
revoke all on function public.end_match(uuid, boolean) from public;
revoke all on function public.submit_report(uuid, text, text, uuid) from public;

grant execute on function public.can_access_match(uuid) to authenticated;
grant execute on function public.get_my_matches() to authenticated;
grant execute on function public.end_match(uuid, boolean) to authenticated;
grant execute on function public.submit_report(uuid, text, text, uuid) to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
