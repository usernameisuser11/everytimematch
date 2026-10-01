-- Everytime Match
-- 2026-10-01: relationship intent + same-gender/any-gender discovery
-- + server-enforced daily discovery/like limits.
--
-- Run this file once in Supabase Dashboard > SQL Editor.
-- Daily reset uses Asia/Seoul time.
--
-- Current limits:
--   profiles viewed: 10/day
--   likes:            5/day

begin;

-- Existing users default to 소개팅 so this migration is backward-compatible.
alter table public.profiles
  add column if not exists relationship_intent text not null default '소개팅';

alter table public.profiles
  drop constraint if exists profiles_preference_check;

alter table public.profiles
  add constraint profiles_preference_check
  check (preference in ('남성','여성','상관없음'));

alter table public.profiles
  drop constraint if exists profiles_relationship_intent_check;

alter table public.profiles
  add constraint profiles_relationship_intent_check
  check (relationship_intent in ('친구','소개팅','둘 다'));

-- One row = one profile shown to one user on one Korea-calendar day.
-- decision stays null while that profile is currently being viewed.
create table if not exists public.daily_discovery (
  user_id uuid not null references auth.users(id) on delete cascade,
  target_user uuid not null references auth.users(id) on delete cascade,
  activity_date date not null,
  viewed_at timestamptz not null default now(),
  decision text check (decision is null or decision in ('like','pass')),
  decided_at timestamptz,
  primary key (user_id, target_user, activity_date),
  check (user_id <> target_user)
);

create index if not exists daily_discovery_user_date_idx
  on public.daily_discovery(user_id, activity_date);

alter table public.daily_discovery enable row level security;

-- No direct writes from the browser. Discovery/decision writes happen only
-- through SECURITY DEFINER functions below.
revoke all on table public.daily_discovery from anon, authenticated;

-- Re-apply base permissions. This also fixes projects where authenticated
-- users received "permission denied for table profiles".
grant usage on schema public to authenticated;
grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.private_contacts to authenticated;
grant select, delete on table public.likes to authenticated;
grant select, insert, delete on table public.blocks to authenticated;
grant insert on table public.reports to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Discovery is now RPC-only so users cannot bypass the daily profile-view
-- limit by selecting every public profile directly.
drop policy if exists "read discoverable profiles" on public.profiles;

-- Direct likes are disabled. Likes must go through record_candidate_decision()
-- so the 5/day limit cannot be bypassed from the browser.
revoke insert on table public.likes from authenticated;
drop policy if exists "send own like" on public.likes;

create or replace function public.get_daily_discovery_status()
returns table (
  views_used integer,
  views_limit integer,
  likes_used integer,
  likes_limit integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    count(*)::integer as views_used,
    10::integer as views_limit,
    count(*) filter (where d.decision = 'like')::integer as likes_used,
    5::integer as likes_limit
  from public.daily_discovery d
  where d.user_id = auth.uid()
    and d.activity_date = (now() at time zone 'Asia/Seoul')::date;
$$;

create or replace function public.get_next_candidate()
returns table (
  user_id uuid,
  nickname text,
  grade text,
  mbti text,
  gender text,
  preference text,
  relationship_intent text,
  bio text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_views integer;
  v_target uuid;
  v_me public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select p.*
  into v_me
  from public.profiles p
  where p.user_id = v_uid
    and p.is_active = true;

  if not found then
    return;
  end if;

  -- Refreshing the page should not consume another view. Return the current
  -- undecided profile first, if there is one.
  return query
  select
    p.user_id, p.nickname, p.grade, p.mbti, p.gender,
    p.preference, p.relationship_intent, p.bio
  from public.daily_discovery d
  join public.profiles p on p.user_id = d.target_user
  where d.user_id = v_uid
    and d.activity_date = v_today
    and d.decision is null
    and p.is_active = true
    and not public.is_blocked_between(p.user_id)
  order by d.viewed_at desc
  limit 1;

  if found then
    return;
  end if;

  select count(*)::integer
  into v_views
  from public.daily_discovery d
  where d.user_id = v_uid
    and d.activity_date = v_today;

  if v_views >= 10 then
    return;
  end if;

  select p.user_id
  into v_target
  from public.profiles p
  where p.user_id <> v_uid
    and p.is_active = true

    -- My gender preference accepts the candidate.
    and (v_me.preference = '상관없음' or p.gender = v_me.preference)

    -- The candidate's gender preference accepts me.
    and (p.preference = '상관없음' or v_me.gender = p.preference)

    -- 친구/소개팅 intent must overlap.
    and (
      v_me.relationship_intent = '둘 다'
      or p.relationship_intent = '둘 다'
      or v_me.relationship_intent = p.relationship_intent
    )

    and not public.is_blocked_between(p.user_id)

    -- Do not show the same person twice on the same day.
    and not exists (
      select 1
      from public.daily_discovery d
      where d.user_id = v_uid
        and d.target_user = p.user_id
        and d.activity_date = v_today
    )

    -- Someone already liked is not shown again.
    and not exists (
      select 1
      from public.likes l
      where l.from_user = v_uid
        and l.to_user = p.user_id
    )
  order by random()
  limit 1;

  if v_target is null then
    return;
  end if;

  insert into public.daily_discovery(user_id, target_user, activity_date)
  values (v_uid, v_target, v_today)
  on conflict do nothing;

  return query
  select
    p.user_id, p.nickname, p.grade, p.mbti, p.gender,
    p.preference, p.relationship_intent, p.bio
  from public.profiles p
  where p.user_id = v_target;
end;
$$;

create or replace function public.record_candidate_decision(
  target_user uuid,
  p_decision text
)
returns table (
  matched boolean,
  views_used integer,
  views_limit integer,
  likes_used integer,
  likes_limit integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_existing text;
  v_likes integer;
  v_views integer;
  v_matched boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if target_user is null or target_user = v_uid then
    raise exception 'INVALID_TARGET';
  end if;

  if p_decision not in ('like','pass') then
    raise exception 'INVALID_DECISION';
  end if;

  -- Serialize decisions for this user/day so multiple rapid clicks cannot
  -- exceed the daily like limit.
  perform pg_advisory_xact_lock(
    hashtext(v_uid::text || ':' || v_today::text)
  );

  select d.decision
  into v_existing
  from public.daily_discovery d
  where d.user_id = v_uid
    and d.target_user = target_user
    and d.activity_date = v_today
  for update;

  if not found then
    raise exception 'PROFILE_NOT_VIEWED_TODAY';
  end if;

  if v_existing is not null then
    raise exception 'PROFILE_ALREADY_DECIDED';
  end if;

  if public.is_blocked_between(target_user) then
    raise exception 'PROFILE_BLOCKED';
  end if;

  if p_decision = 'like' then
    select count(*)::integer
    into v_likes
    from public.daily_discovery d
    where d.user_id = v_uid
      and d.activity_date = v_today
      and d.decision = 'like';

    if v_likes >= 5 then
      raise exception 'DAILY_LIKE_LIMIT_REACHED';
    end if;

    insert into public.likes(from_user, to_user)
    values (v_uid, target_user)
    on conflict (from_user, to_user) do nothing;
  end if;

  update public.daily_discovery
  set
    decision = p_decision,
    decided_at = now()
  where user_id = v_uid
    and target_user = record_candidate_decision.target_user
    and activity_date = v_today;

  if p_decision = 'like' then
    v_matched := public.is_match(target_user);
  end if;

  select
    count(*)::integer,
    count(*) filter (where d.decision = 'like')::integer
  into v_views, v_likes
  from public.daily_discovery d
  where d.user_id = v_uid
    and d.activity_date = v_today;

  return query
  select v_matched, v_views, 10, v_likes, 5;
end;
$$;

revoke all on function public.get_daily_discovery_status() from public;
revoke all on function public.get_next_candidate() from public;
revoke all on function public.record_candidate_decision(uuid, text) from public;

grant execute on function public.get_daily_discovery_status() to authenticated;
grant execute on function public.get_next_candidate() to authenticated;
grant execute on function public.record_candidate_decision(uuid, text) to authenticated;
grant execute on function public.is_match(uuid) to authenticated;
grant execute on function public.is_blocked_between(uuid) to authenticated;

commit;
