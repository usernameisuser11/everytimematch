-- Everytime Match
-- 2026-10-03: 50-member milestone event
-- - Starts automatically when the 50th active, beta-accessible profile exists
-- - Runs for exactly 48 hours
-- - Removes the 10-profile/day discovery cap during the event
-- - Keeps mutual preference, relationship-intent, verification, block/report safeguards
-- - Limits likes to 5 total across the whole 48-hour event

begin;

create table if not exists public.app_events (
  event_key text primary key,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

alter table public.app_events enable row level security;
revoke all on table public.app_events from anon, authenticated;

create or replace function public.maybe_start_fifty_member_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if exists (
    select 1 from public.app_events e
    where e.event_key = 'fifty_members'
  ) then
    return new;
  end if;

  select count(*)::integer
  into v_count
  from public.profiles p
  where p.is_active = true
    and public.can_use_beta(p.user_id);

  if v_count >= 50 then
    insert into public.app_events(event_key, starts_at, ends_at)
    values ('fifty_members', now(), now() + interval '48 hours')
    on conflict (event_key) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists start_fifty_member_event_on_profile on public.profiles;
create trigger start_fifty_member_event_on_profile
after insert or update of is_active on public.profiles
for each row
execute function public.maybe_start_fifty_member_event();

-- If this migration is applied after the service already reached 50 profiles,
-- start the event at migration time instead of waiting for profile #51.
insert into public.app_events(event_key, starts_at, ends_at)
select 'fifty_members', now(), now() + interval '48 hours'
where (
  select count(*)
  from public.profiles p
  where p.is_active = true
    and public.can_use_beta(p.user_id)
) >= 50
on conflict (event_key) do nothing;

create or replace function public.get_discovery_event_status()
returns table (
  event_active boolean,
  starts_at timestamptz,
  ends_at timestamptz,
  likes_used integer,
  likes_limit integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_start timestamptz;
  v_end timestamptz;
  v_active boolean := false;
  v_likes integer := 0;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select e.starts_at, e.ends_at
  into v_start, v_end
  from public.app_events e
  where e.event_key = 'fifty_members';

  v_active := v_start is not null
    and now() >= v_start
    and now() < v_end;

  if v_active then
    select count(*)::integer
    into v_likes
    from public.daily_discovery d
    where d.user_id = v_uid
      and d.decision = 'like'
      and d.decided_at >= v_start
      and d.decided_at < v_end;
  end if;

  return query
  select v_active, v_start, v_end, v_likes, 5;
end;
$$;

create or replace function public.get_daily_discovery_status()
returns table (
  views_used integer,
  views_limit integer,
  likes_used integer,
  likes_limit integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_start timestamptz;
  v_end timestamptz;
  v_active boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select e.starts_at, e.ends_at
  into v_start, v_end
  from public.app_events e
  where e.event_key = 'fifty_members';

  v_active := v_start is not null
    and now() >= v_start
    and now() < v_end;

  if v_active then
    return query
    select
      count(*)::integer,
      2147483647::integer,
      count(*) filter (
        where d.decision = 'like'
          and d.decided_at >= v_start
          and d.decided_at < v_end
      )::integer,
      5::integer
    from public.daily_discovery d
    where d.user_id = v_uid
      and d.viewed_at >= v_start
      and d.viewed_at < v_end;
  else
    return query
    select
      count(*)::integer,
      10::integer,
      count(*) filter (where d.decision = 'like')::integer,
      5::integer
    from public.daily_discovery d
    where d.user_id = v_uid
      and d.activity_date = v_today;
  end if;
end;
$$;

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

  select e.starts_at, e.ends_at
  into v_event_start, v_event_end
  from public.app_events e
  where e.event_key = 'fifty_members';

  v_event_active := v_event_start is not null
    and now() >= v_event_start
    and now() < v_event_end;

  select p.*
  into v_me
  from public.profiles p
  where p.user_id = v_uid
    and p.is_active = true;

  if not found then
    return;
  end if;

  -- Refresh keeps the current undecided profile and does not consume another view.
  -- During the event, an undecided profile remains valid even if midnight passes.
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
    and d.decision is null
    and (
      (v_event_active and d.viewed_at >= v_event_start and d.viewed_at < v_event_end)
      or
      (not v_event_active and d.activity_date = v_today)
    )
    and p.is_active = true
    and public.can_use_beta(p.user_id)
    and not public.is_blocked_between(p.user_id)
  order by d.viewed_at desc
  limit 1;

  if found then
    return;
  end if;

  if not v_event_active then
    select count(*)::integer
    into v_views
    from public.daily_discovery d
    where d.user_id = v_uid
      and d.activity_date = v_today;

    if v_views >= 10 then
      return;
    end if;
  end if;

  select p.user_id
  into v_target
  from public.profiles p
  where p.user_id <> v_uid
    and p.is_active = true
    and public.can_use_beta(p.user_id)

    -- Preserve mutual discovery/privacy conditions during the event.
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
        and (
          (v_event_active and d.viewed_at >= v_event_start and d.viewed_at < v_event_end)
          or
          (not v_event_active and d.activity_date = v_today)
        )
    )

    -- A profile already liked before or during the event is never shown again.
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
  v_activity_date date;
  v_likes integer;
  v_views integer;
  v_matched boolean := false;
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

  if v_target_user is null or v_target_user = v_uid then
    raise exception 'INVALID_TARGET';
  end if;

  if not public.can_use_beta(v_target_user) then
    raise exception 'TARGET_NOT_VERIFIED';
  end if;

  if p_decision not in ('like','pass') then
    raise exception 'INVALID_DECISION';
  end if;

  select e.starts_at, e.ends_at
  into v_event_start, v_event_end
  from public.app_events e
  where e.event_key = 'fifty_members';

  v_event_active := v_event_start is not null
    and now() >= v_event_start
    and now() < v_event_end;

  perform pg_advisory_xact_lock(
    hashtext(
      v_uid::text || ':' ||
      case when v_event_active then v_event_start::text else v_today::text end
    )
  );

  select d.activity_date, d.decision
  into v_activity_date, v_existing
  from public.daily_discovery d
  where d.user_id = v_uid
    and d.target_user = v_target_user
    and (
      (v_event_active and d.viewed_at >= v_event_start and d.viewed_at < v_event_end)
      or
      (not v_event_active and d.activity_date = v_today)
    )
  order by d.viewed_at desc
  limit 1
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
    if v_event_active then
      select count(*)::integer
      into v_likes
      from public.daily_discovery d
      where d.user_id = v_uid
        and d.decision = 'like'
        and d.decided_at >= v_event_start
        and d.decided_at < v_event_end;

      if v_likes >= 5 then
        raise exception 'EVENT_LIKE_LIMIT_REACHED';
      end if;
    else
      select count(*)::integer
      into v_likes
      from public.daily_discovery d
      where d.user_id = v_uid
        and d.activity_date = v_today
        and d.decision = 'like';

      if v_likes >= 5 then
        raise exception 'DAILY_LIKE_LIMIT_REACHED';
      end if;
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
    and d.activity_date = v_activity_date;

  if p_decision = 'like' then
    v_matched := public.is_match(v_target_user);
  end if;

  if v_event_active then
    select
      count(*)::integer,
      count(*) filter (
        where d.decision = 'like'
          and d.decided_at >= v_event_start
          and d.decided_at < v_event_end
      )::integer
    into v_views, v_likes
    from public.daily_discovery d
    where d.user_id = v_uid
      and d.viewed_at >= v_event_start
      and d.viewed_at < v_event_end;

    return query
    select v_matched, v_views, 2147483647, v_likes, 5;
  else
    select
      count(*)::integer,
      count(*) filter (where d.decision = 'like')::integer
    into v_views, v_likes
    from public.daily_discovery d
    where d.user_id = v_uid
      and d.activity_date = v_today;

    return query
    select v_matched, v_views, 10, v_likes, 5;
  end if;
end;
$$;

revoke all on function public.maybe_start_fifty_member_event() from public;
revoke all on function public.get_discovery_event_status() from public;
revoke all on function public.get_daily_discovery_status() from public;
revoke all on function public.get_next_candidate() from public;
revoke all on function public.record_candidate_decision(uuid, text) from public;

grant execute on function public.get_discovery_event_status() to authenticated;
grant execute on function public.get_daily_discovery_status() to authenticated;
grant execute on function public.get_next_candidate() to authenticated;
grant execute on function public.record_candidate_decision(uuid, text) to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
