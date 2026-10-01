-- Everytime Match
-- 2026-10-01: beta readiness - school email verification, test-account compatibility,
-- blocked-user management, and self-service account deletion.
--
-- Run after:
--   1) supabase/schema.sql
--   2) supabase/migrations/20261001_discovery_limits.sql
--   3) supabase/migrations/20261001_matches_chat_reports.sql
--
-- Existing Auth users are automatically preserved as beta testers.
-- New users must confirm an allowed Sangmyung email before using matching/chat.

begin;

-- =========================================================
-- 1. Allowed Sangmyung email domains
-- =========================================================

create table if not exists public.school_email_domains (
  domain text primary key,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.school_email_domains(domain, is_active)
values
  ('sangmyung.kr', true),
  ('smu.ac.kr', true),
  ('sangmyung.ac.kr', true)
on conflict (domain)
do update set is_active = excluded.is_active;

alter table public.school_email_domains enable row level security;
revoke all on table public.school_email_domains from anon, authenticated;

-- =========================================================
-- 2. Preserve all accounts that already existed before this migration
-- =========================================================

create table if not exists public.beta_testers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  note text,
  created_at timestamptz not null default now()
);

insert into public.beta_testers(user_id, note)
select u.id, 'Existing account before school-verification rollout'
from auth.users u
on conflict (user_id) do nothing;

alter table public.beta_testers enable row level security;
revoke all on table public.beta_testers from anon, authenticated;

-- =========================================================
-- 3. Verification helpers
-- =========================================================

create or replace function public.is_school_verified(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users u
    join public.school_email_domains d
      on d.domain = split_part(lower(coalesce(u.email, '')), '@', 2)
     and d.is_active = true
    where u.id = p_user_id
      and u.email_confirmed_at is not null
  );
$$;

create or replace function public.is_beta_tester(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.beta_testers b
    where b.user_id = p_user_id
  );
$$;

create or replace function public.can_use_beta(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    p_user_id is not null
    and (
      public.is_school_verified(p_user_id)
      or public.is_beta_tester(p_user_id)
    );
$$;

create or replace function public.get_verification_kind(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_email text;
  v_confirmed timestamptz;
  v_domain text;
begin
  if p_user_id is null then
    return 'unverified';
  end if;

  select u.email, u.email_confirmed_at
  into v_email, v_confirmed
  from auth.users u
  where u.id = p_user_id;

  if not found then
    return 'unverified';
  end if;

  v_domain := split_part(lower(coalesce(v_email, '')), '@', 2);

  if v_confirmed is not null
     and exists (
       select 1
       from public.school_email_domains d
       where d.domain = v_domain
         and d.is_active = true
     ) then
    return 'school_verified';
  end if;

  if public.is_beta_tester(p_user_id) then
    return 'beta_tester';
  end if;

  if exists (
    select 1
    from public.school_email_domains d
    where d.domain = v_domain
      and d.is_active = true
  ) then
    return 'email_unconfirmed';
  end if;

  return 'unsupported_email';
end;
$$;

create or replace function public.get_my_access_status()
returns table (
  access_allowed boolean,
  verification_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    public.can_use_beta(auth.uid()),
    public.get_verification_kind(auth.uid());
$$;

-- =========================================================
-- 4. Profile writes require school verification or beta-test allowlist
-- =========================================================

drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile"
on public.profiles for insert
to authenticated
with check (
  auth.uid() = user_id
  and public.can_use_beta(auth.uid())
);

drop policy if exists "update own profile" on public.profiles;
create policy "update own profile"
on public.profiles for update
to authenticated
using (
  auth.uid() = user_id
  and public.can_use_beta(auth.uid())
)
with check (
  auth.uid() = user_id
  and public.can_use_beta(auth.uid())
);

drop policy if exists "create own block" on public.blocks;
create policy "create own block"
on public.blocks for insert
to authenticated
with check (
  auth.uid() = blocker
  and public.can_use_beta(auth.uid())
);

-- =========================================================
-- 5. Discovery: only verified/beta users can browse or be shown
-- =========================================================

drop function if exists public.get_next_candidate();

create function public.get_next_candidate()
returns table (
  user_id uuid,
  nickname text,
  grade text,
  mbti text,
  gender text,
  preference text,
  relationship_intent text,
  bio text,
  verification_status text
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

  if not public.can_use_beta(v_uid) then
    raise exception 'SCHOOL_VERIFICATION_REQUIRED';
  end if;

  select p.*
  into v_me
  from public.profiles p
  where p.user_id = v_uid
    and p.is_active = true;

  if not found then
    return;
  end if;

  -- Refresh keeps the current undecided profile and does not consume another view.
  return query
  select
    p.user_id,
    p.nickname,
    p.grade,
    p.mbti,
    p.gender,
    p.preference,
    p.relationship_intent,
    p.bio,
    public.get_verification_kind(p.user_id)
  from public.daily_discovery d
  join public.profiles p on p.user_id = d.target_user
  where d.user_id = v_uid
    and d.activity_date = v_today
    and d.decision is null
    and p.is_active = true
    and public.can_use_beta(p.user_id)
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
    and public.can_use_beta(p.user_id)
    and (v_me.preference = '상관없음' or p.gender = v_me.preference)
    and (p.preference = '상관없음' or v_me.gender = p.preference)
    and (
      v_me.relationship_intent = '둘 다'
      or p.relationship_intent = '둘 다'
      or v_me.relationship_intent = p.relationship_intent
    )
    and not public.is_blocked_between(p.user_id)
    and not exists (
      select 1
      from public.daily_discovery d
      where d.user_id = v_uid
        and d.target_user = p.user_id
        and d.activity_date = v_today
    )
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
    p.user_id,
    p.nickname,
    p.grade,
    p.mbti,
    p.gender,
    p.preference,
    p.relationship_intent,
    p.bio,
    public.get_verification_kind(p.user_id)
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
  v_target_user uuid := target_user;
  v_existing text;
  v_likes integer;
  v_views integer;
  v_matched boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not public.can_use_beta(v_uid) then
    raise exception 'SCHOOL_VERIFICATION_REQUIRED';
  end if;

  if v_target_user is null or v_target_user = v_uid then
    raise exception 'INVALID_TARGET';
  end if;

  if not public.can_use_beta(v_target_user) then
    raise exception 'TARGET_NOT_VERIFIED';
  end if;

  if p_decision not in ('like','pass') then
    raise exception 'INVALID_DECISION';
  end if;

  perform pg_advisory_xact_lock(
    hashtext(v_uid::text || ':' || v_today::text)
  );

  select d.decision
  into v_existing
  from public.daily_discovery d
  where d.user_id = v_uid
    and d.target_user = v_target_user
    and d.activity_date = v_today
  for update;

  if not found then
    raise exception 'PROFILE_NOT_VIEWED_TODAY';
  end if;

  if v_existing is not null then
    raise exception 'PROFILE_ALREADY_DECIDED';
  end if;

  if public.is_blocked_between(v_target_user) then
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
    values (v_uid, v_target_user)
    on conflict (from_user, to_user) do nothing;
  end if;

  update public.daily_discovery d
  set
    decision = p_decision,
    decided_at = now()
  where d.user_id = v_uid
    and d.target_user = v_target_user
    and d.activity_date = v_today;

  if p_decision = 'like' then
    v_matched := public.is_match(v_target_user);
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

-- =========================================================
-- 6. Matching/chat access also requires verified/beta access
-- =========================================================

create or replace function public.can_access_match(p_match_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.can_use_beta(auth.uid())
    and exists (
      select 1
      from public.matches m
      where m.id = p_match_id
        and m.status = 'active'
        and (m.user_a = auth.uid() or m.user_b = auth.uid())
        and public.can_use_beta(
          case when m.user_a = auth.uid() then m.user_b else m.user_a end
        )
    );
$$;

drop function if exists public.get_my_matches();

create function public.get_my_matches()
returns table (
  match_id uuid,
  other_user_id uuid,
  nickname text,
  grade text,
  mbti text,
  relationship_intent text,
  bio text,
  verification_status text,
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
    public.get_verification_kind(p.user_id),
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
  where public.can_use_beta(auth.uid())
    and public.can_use_beta(p.user_id)
    and m.status = 'active'
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
-- 7. Reports require an eligible account
-- =========================================================

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

  if not public.can_use_beta(v_uid) then
    raise exception 'SCHOOL_VERIFICATION_REQUIRED';
  end if;

  if p_reported is null or p_reported = v_uid then
    raise exception 'INVALID_TARGET';
  end if;

  if not public.can_use_beta(p_reported) then
    raise exception 'TARGET_NOT_VERIFIED';
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
-- 8. Block list / unblock
-- =========================================================

create or replace function public.get_blocked_users()
returns table (
  blocked_user_id uuid,
  nickname text,
  grade text,
  blocked_at timestamptz,
  verification_status text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    b.blocked,
    p.nickname,
    p.grade,
    b.created_at,
    public.get_verification_kind(b.blocked)
  from public.blocks b
  left join public.profiles p on p.user_id = b.blocked
  where b.blocker = auth.uid()
  order by b.created_at desc;
$$;

create or replace function public.unblock_user(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not public.can_use_beta(v_uid) then
    raise exception 'SCHOOL_VERIFICATION_REQUIRED';
  end if;

  delete from public.blocks
  where blocker = v_uid
    and blocked = p_user_id;

  return found;
end;
$$;

-- =========================================================
-- 9. Self-service account deletion
-- =========================================================

create or replace function public.delete_my_account()
returns boolean
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  delete from auth.users
  where id = v_uid;

  return true;
end;
$$;

-- =========================================================
-- 10. Permissions
-- =========================================================

revoke all on function public.is_school_verified(uuid) from public;
revoke all on function public.is_beta_tester(uuid) from public;
revoke all on function public.can_use_beta(uuid) from public;
revoke all on function public.get_verification_kind(uuid) from public;
revoke all on function public.get_my_access_status() from public;
revoke all on function public.get_next_candidate() from public;
revoke all on function public.record_candidate_decision(uuid, text) from public;
revoke all on function public.can_access_match(uuid) from public;
revoke all on function public.get_my_matches() from public;
revoke all on function public.submit_report(uuid, text, text, uuid) from public;
revoke all on function public.get_blocked_users() from public;
revoke all on function public.unblock_user(uuid) from public;
revoke all on function public.delete_my_account() from public;

grant execute on function public.is_school_verified(uuid) to authenticated;
grant execute on function public.is_beta_tester(uuid) to authenticated;
grant execute on function public.can_use_beta(uuid) to authenticated;
grant execute on function public.get_verification_kind(uuid) to authenticated;
grant execute on function public.get_my_access_status() to authenticated;
grant execute on function public.get_next_candidate() to authenticated;
grant execute on function public.record_candidate_decision(uuid, text) to authenticated;
grant execute on function public.can_access_match(uuid) to authenticated;
grant execute on function public.get_my_matches() to authenticated;
grant execute on function public.submit_report(uuid, text, text, uuid) to authenticated;
grant execute on function public.get_blocked_users() to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;
grant execute on function public.delete_my_account() to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
