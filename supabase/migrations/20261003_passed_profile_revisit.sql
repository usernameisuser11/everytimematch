-- Everytime Match
-- 2026-10-03: passed-profile revisit
-- Users can revisit profiles they passed during the current discovery window
-- and send a like later without bypassing the existing 5-like limit.
--
-- Normal mode: today's passed profiles.
-- 50-member event: profiles passed during the active 48-hour event.

begin;

create or replace function public.get_passed_profiles()
returns table (
  user_id uuid,
  nickname text,
  grade text,
  mbti text,
  gender text,
  preference text,
  relationship_intent text,
  bio text,
  verification_status text,
  passed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_me public.profiles%rowtype;
  v_event_start timestamptz;
  v_event_end timestamptz;
  v_event_active boolean := false;
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

  select e.starts_at, e.ends_at
  into v_event_start, v_event_end
  from public.app_events e
  where e.event_key = 'fifty_members';

  v_event_active := v_event_start is not null
    and now() >= v_event_start
    and now() < v_event_end;

  return query
  with latest_pass as (
    select distinct on (d.target_user)
      d.target_user,
      d.decided_at
    from public.daily_discovery d
    where d.user_id = v_uid
      and d.decision = 'pass'
      and (
        (v_event_active and d.viewed_at >= v_event_start and d.viewed_at < v_event_end)
        or
        (not v_event_active and d.activity_date = v_today)
      )
    order by d.target_user, d.decided_at desc nulls last
  )
  select
    p.user_id,
    p.nickname,
    p.grade,
    p.mbti,
    p.gender,
    p.preference,
    p.relationship_intent,
    p.bio,
    public.get_verification_kind(p.user_id),
    lp.decided_at
  from latest_pass lp
  join public.profiles p on p.user_id = lp.target_user
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
      from public.likes l
      where l.from_user = v_uid
        and l.to_user = p.user_id
    )
  order by lp.decided_at desc nulls last;
end;
$$;

create or replace function public.like_passed_candidate(p_target_user uuid)
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
  v_activity_date date;
  v_me public.profiles%rowtype;
  v_event_start timestamptz;
  v_event_end timestamptz;
  v_event_active boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not public.can_use_beta(v_uid) then
    raise exception 'SCHOOL_VERIFICATION_REQUIRED';
  end if;

  if p_target_user is null or p_target_user = v_uid then
    raise exception 'INVALID_TARGET';
  end if;

  select p.*
  into v_me
  from public.profiles p
  where p.user_id = v_uid
    and p.is_active = true;

  if not found then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.user_id = p_target_user
      and p.is_active = true
      and public.can_use_beta(p.user_id)
      and (v_me.preference = '상관없음' or p.gender = v_me.preference)
      and (p.preference = '상관없음' or v_me.gender = p.preference)
      and (
        v_me.relationship_intent = '둘 다'
        or p.relationship_intent = '둘 다'
        or v_me.relationship_intent = p.relationship_intent
      )
  ) then
    raise exception 'TARGET_NOT_AVAILABLE';
  end if;

  if public.is_blocked_between(p_target_user) then
    raise exception 'PROFILE_BLOCKED';
  end if;

  if exists (
    select 1
    from public.likes l
    where l.from_user = v_uid
      and l.to_user = p_target_user
  ) then
    raise exception 'PROFILE_ALREADY_LIKED';
  end if;

  select e.starts_at, e.ends_at
  into v_event_start, v_event_end
  from public.app_events e
  where e.event_key = 'fifty_members';

  v_event_active := v_event_start is not null
    and now() >= v_event_start
    and now() < v_event_end;

  select d.activity_date
  into v_activity_date
  from public.daily_discovery d
  where d.user_id = v_uid
    and d.target_user = p_target_user
    and d.decision = 'pass'
    and (
      (v_event_active and d.viewed_at >= v_event_start and d.viewed_at < v_event_end)
      or
      (not v_event_active and d.activity_date = v_today)
    )
  order by d.viewed_at desc
  limit 1
  for update;

  if not found then
    raise exception 'PASSED_PROFILE_NOT_FOUND';
  end if;

  -- Temporarily restore the candidate to undecided and delegate to the same
  -- decision RPC used by the main discovery screen. If the like limit is hit,
  -- the exception rolls this update back, so the profile stays in pass history.
  update public.daily_discovery d
  set decision = null,
      decided_at = null
  where d.user_id = v_uid
    and d.target_user = p_target_user
    and d.activity_date = v_activity_date;

  return query
  select *
  from public.record_candidate_decision(p_target_user, 'like');
end;
$$;

revoke all on function public.get_passed_profiles() from public;
revoke all on function public.like_passed_candidate(uuid) from public;

grant execute on function public.get_passed_profiles() to authenticated;
grant execute on function public.like_passed_candidate(uuid) to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
