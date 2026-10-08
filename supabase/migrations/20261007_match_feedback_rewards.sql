begin;

create table if not exists public.match_feedback (
  user_id uuid primary key references auth.users(id) on delete cascade,
  usage_intent text not null check (usage_intent in ('dating','friends','both','unsure')),
  conversation_status text not null check (conversation_status in ('not_matched','no_chat','brief','ongoing')),
  contact_exchanged text not null default 'skip' check (contact_exchanged in ('yes','no','skip')),
  met_offline text not null default 'skip' check (met_offline in ('yes','no','skip')),
  still_in_touch text not null default 'skip' check (still_in_touch in ('yes','no','unsure','skip')),
  improvement text null check (improvement is null or char_length(improvement) <= 600),
  submitted_at timestamptz not null default now(),
  reward_date date not null default ((now() at time zone 'Asia/Seoul')::date),
  reward_views integer not null default 5 check (reward_views = 5),
  reward_likes integer not null default 3 check (reward_likes = 3)
);
alter table public.match_feedback enable row level security;
revoke all on table public.match_feedback from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_match_feedback_status()
 RETURNS TABLE(submitted boolean, reward_active boolean, reward_date date, bonus_views integer, bonus_likes integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid:=auth.uid(); v_today date:=(now() at time zone 'Asia/Seoul')::date;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  return query select f.user_id is not null, f.user_id is not null and f.reward_date=v_today, f.reward_date, coalesce(f.reward_views,0), coalesce(f.reward_likes,0)
  from (select v_uid as user_id) me left join public.match_feedback f on f.user_id=me.user_id;
end; $function$;

CREATE OR REPLACE FUNCTION public.submit_match_feedback(p_usage_intent text, p_conversation_status text, p_contact_exchanged text, p_met_offline text, p_still_in_touch text, p_improvement text DEFAULT NULL::text)
 RETURNS TABLE(bonus_views integer, bonus_likes integer, reward_date date)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid:=auth.uid(); v_reward_date date:=(now() at time zone 'Asia/Seoul')::date;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if not public.can_use_beta(v_uid) then raise exception 'SCHOOL_VERIFICATION_REQUIRED'; end if;
 if p_usage_intent not in ('dating','friends','both','unsure') then raise exception 'INVALID_FEEDBACK_INTENT'; end if;
 if p_conversation_status not in ('not_matched','no_chat','brief','ongoing') then raise exception 'INVALID_FEEDBACK_CONVERSATION'; end if;
 if coalesce(p_contact_exchanged,'skip') not in ('yes','no','skip') then raise exception 'INVALID_FEEDBACK_CONTACT'; end if;
 if coalesce(p_met_offline,'skip') not in ('yes','no','skip') then raise exception 'INVALID_FEEDBACK_MEETING'; end if;
 if coalesce(p_still_in_touch,'skip') not in ('yes','no','unsure','skip') then raise exception 'INVALID_FEEDBACK_CONTACT_STATUS'; end if;
 if p_improvement is not null and char_length(p_improvement)>600 then raise exception 'FEEDBACK_TOO_LONG'; end if;
 insert into public.match_feedback(user_id,usage_intent,conversation_status,contact_exchanged,met_offline,still_in_touch,improvement,reward_date)
 values(v_uid,p_usage_intent,p_conversation_status,coalesce(p_contact_exchanged,'skip'),coalesce(p_met_offline,'skip'),coalesce(p_still_in_touch,'skip'),nullif(btrim(p_improvement),''),v_reward_date)
 on conflict(user_id) do nothing;
 if not found then raise exception 'FEEDBACK_ALREADY_SUBMITTED'; end if;
 return query select 5,3,v_reward_date;
end; $function$;

CREATE OR REPLACE FUNCTION public.get_match_feedback_admin_stats()
 RETURNS TABLE(total_responses integer, intent_dating integer, intent_friends integer, intent_both integer, intent_unsure integer, conversation_not_matched integer, conversation_no_chat integer, conversation_brief integer, conversation_ongoing integer, contact_exchanged_yes integer, met_offline_yes integer, still_in_touch_yes integer, suggestion_count integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if not exists(select 1 from public.admin_users a where a.user_id=v_uid) then raise exception 'ADMIN_REQUIRED'; end if;
 return query select
 count(*)::integer,
 count(*) filter(where f.usage_intent='dating')::integer,
 count(*) filter(where f.usage_intent='friends')::integer,
 count(*) filter(where f.usage_intent='both')::integer,
 count(*) filter(where f.usage_intent='unsure')::integer,
 count(*) filter(where f.conversation_status='not_matched')::integer,
 count(*) filter(where f.conversation_status='no_chat')::integer,
 count(*) filter(where f.conversation_status='brief')::integer,
 count(*) filter(where f.conversation_status='ongoing')::integer,
 count(*) filter(where f.contact_exchanged='yes')::integer,
 count(*) filter(where f.met_offline='yes')::integer,
 count(*) filter(where f.still_in_touch='yes')::integer,
 count(*) filter(where f.improvement is not null and btrim(f.improvement)<>'')::integer
 from public.match_feedback f;
end; $function$;

CREATE OR REPLACE FUNCTION public.get_daily_discovery_status()
 RETURNS TABLE(views_used integer, views_limit integer, likes_used integer, likes_limit integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_start timestamptz;
  v_end timestamptz;
  v_active boolean := false;
  v_bonus_views integer := 0;
  v_bonus_likes integer := 0;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select coalesce(f.reward_views,0), coalesce(f.reward_likes,0)
  into v_bonus_views, v_bonus_likes
  from public.match_feedback f
  where f.user_id=v_uid and f.reward_date=v_today;
  v_bonus_views:=coalesce(v_bonus_views,0);
  v_bonus_likes:=coalesce(v_bonus_likes,0);

  select e.starts_at, e.ends_at
  into v_start, v_end
  from public.app_events e
  where e.event_key = 'fifty_members';

  v_active :=
    v_start is not null
    and now() >= v_start
    and now() < v_end;

  if v_active then

    return query
    select
      count(*)::integer,

      -- 이벤트 중 프로필 제한 사실상 없음
      2147483647::integer,

      count(*) filter (
        where d.decision = 'like'
          and d.decided_at >= v_start
          and d.decided_at < v_end
      )::integer,

      (5 + v_bonus_likes)::integer

    from public.daily_discovery d
    where d.user_id = v_uid
      and d.viewed_at >= v_start
      and d.viewed_at < v_end;

  else

    return query
    select
      count(*)::integer,
      (10 + v_bonus_views)::integer,
      count(*) filter (
        where d.decision = 'like'
      )::integer,
      (5 + v_bonus_likes)::integer

    from public.daily_discovery d
    where d.user_id = v_uid
      and d.activity_date = v_today;

  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_discovery_event_status()
 RETURNS TABLE(event_active boolean, starts_at timestamp with time zone, ends_at timestamp with time zone, likes_used integer, likes_limit integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_start timestamptz;
  v_end timestamptz;
  v_active boolean := false;
  v_likes integer := 0;
  v_today date := (now() at time zone 'Asia/Seoul')::date;
  v_bonus_likes integer := 0;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select coalesce(f.reward_likes,0) into v_bonus_likes
  from public.match_feedback f
  where f.user_id=v_uid and f.reward_date=v_today;
  v_bonus_likes:=coalesce(v_bonus_likes,0);

  select e.starts_at, e.ends_at
  into v_start, v_end
  from public.app_events e
  where e.event_key = 'fifty_members';

  v_active :=
    v_start is not null
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
  select
    v_active,
    v_start,
    v_end,
    v_likes,
    (5 + v_bonus_likes);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_next_candidate()
 RETURNS TABLE(user_id uuid, nickname text, grade text, mbti text, gender text, preference text, relationship_intent text, bio text, verification_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_today date := (now() at time zone 'Asia/Seoul')::date;

  v_views integer;
  v_target uuid;

  v_me public.profiles%rowtype;

  v_event_start timestamptz;
  v_event_end timestamptz;
  v_event_active boolean := false;
  v_bonus_views integer := 0;
begin

  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not public.can_use_beta(v_uid) then
    raise exception 'SCHOOL_VERIFICATION_REQUIRED';
  end if;

  select coalesce(f.reward_views,0) into v_bonus_views
  from public.match_feedback f
  where f.user_id=v_uid and f.reward_date=v_today;
  v_bonus_views:=coalesce(v_bonus_views,0);


  -- 이벤트 확인
  select e.starts_at, e.ends_at
  into v_event_start, v_event_end
  from public.app_events e
  where e.event_key = 'fifty_members';

  v_event_active :=
    v_event_start is not null
    and now() >= v_event_start
    and now() < v_event_end;


  -- 내 프로필
  select p.*
  into v_me
  from public.profiles p
  where p.user_id = v_uid
    and p.is_active = true;

  if not found then
    return;
  end if;


  -- 아직 결정하지 않은 프로필이 있으면
  -- 새로고침해도 같은 프로필 반환
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

  join public.profiles p
    on p.user_id = d.target_user

  where d.user_id = v_uid
    and d.decision is null

    and (
      (
        v_event_active
        and d.viewed_at >= v_event_start
        and d.viewed_at < v_event_end
      )
      or
      (
        not v_event_active
        and d.activity_date = v_today
      )
    )

    and p.is_active = true
    and public.can_use_beta(p.user_id)
    and not public.is_blocked_between(p.user_id)

  order by d.viewed_at desc
  limit 1;


  if found then
    return;
  end if;


  -- 일반 기간에는 하루 10명 제한
  if not v_event_active then

    select count(*)::integer
    into v_views

    from public.daily_discovery d

    where d.user_id = v_uid
      and d.activity_date = v_today;


    if v_views >= (10 + v_bonus_views) then
      return;
    end if;

  end if;


  -- 새로운 후보
  select p.user_id
  into v_target

  from public.profiles p

  where p.user_id <> v_uid

    and p.is_active = true

    and public.can_use_beta(p.user_id)


    -- 내가 찾는 성별
    and (
      v_me.preference = '상관없음'
      or p.gender = v_me.preference
    )


    -- 상대가 찾는 성별
    and (
      p.preference = '상관없음'
      or v_me.gender = p.preference
    )


    -- 관계 목적 일치
    and (
      v_me.relationship_intent = '둘 다'
      or p.relationship_intent = '둘 다'
      or v_me.relationship_intent = p.relationship_intent
    )


    -- 차단 사용자 제외
    and not public.is_blocked_between(p.user_id)


    -- 이벤트 기간에는 이벤트 중 봤던 사람 다시 표시 X
    -- 일반 기간에는 오늘 봤던 사람 다시 표시 X
    and not exists (

      select 1

      from public.daily_discovery d

      where d.user_id = v_uid
        and d.target_user = p.user_id

        and (

          (
            v_event_active
            and d.viewed_at >= v_event_start
            and d.viewed_at < v_event_end
          )

          or

          (d.activity_date >= v_today - 3)

        )

    )


    -- 이미 호감을 보낸 사람은 다시 표시하지 않음
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


  insert into public.daily_discovery (
    user_id,
    target_user,
    activity_date
  )

  values (
    v_uid,
    v_target,
    v_today
  )

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
$function$;

CREATE OR REPLACE FUNCTION public.record_candidate_decision(target_user uuid, p_decision text)
 RETURNS TABLE(matched boolean, views_used integer, views_limit integer, likes_used integer, likes_limit integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare

  v_uid uuid := auth.uid();

  v_today date :=
    (now() at time zone 'Asia/Seoul')::date;

  v_target_user uuid :=
    target_user;

  v_existing text;

  v_activity_date date;

  v_likes integer;

  v_views integer;

  v_matched boolean := false;

  v_event_start timestamptz;

  v_event_end timestamptz;

  v_event_active boolean := false;
  v_bonus_views integer := 0;
  v_bonus_likes integer := 0;

begin


  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;


  if not public.can_use_beta(v_uid) then
    raise exception 'SCHOOL_VERIFICATION_REQUIRED';
  end if;

  select coalesce(f.reward_views,0), coalesce(f.reward_likes,0)
  into v_bonus_views, v_bonus_likes
  from public.match_feedback f
  where f.user_id=v_uid and f.reward_date=v_today;
  v_bonus_views:=coalesce(v_bonus_views,0);
  v_bonus_likes:=coalesce(v_bonus_likes,0);


  if v_target_user is null
     or v_target_user = v_uid then

    raise exception 'INVALID_TARGET';

  end if;


  if not public.can_use_beta(v_target_user) then
    raise exception 'TARGET_NOT_VERIFIED';
  end if;


  if p_decision not in ('like','pass') then
    raise exception 'INVALID_DECISION';
  end if;


  -- 이벤트 확인
  select e.starts_at, e.ends_at

  into
    v_event_start,
    v_event_end

  from public.app_events e

  where e.event_key = 'fifty_members';


  v_event_active :=
    v_event_start is not null
    and now() >= v_event_start
    and now() < v_event_end;


  -- 동시에 여러 번 호감 버튼을 눌러
  -- 5개 제한을 뚫는 것 방지
  perform pg_advisory_xact_lock(

    hashtext(

      v_uid::text
      || ':'
      ||

      case

        when v_event_active
        then v_event_start::text

        else v_today::text

      end

    )

  );


  select
    d.activity_date,
    d.decision

  into
    v_activity_date,
    v_existing

  from public.daily_discovery d

  where d.user_id = v_uid

    and d.target_user = v_target_user

    and (

      (
        v_event_active
        and d.viewed_at >= v_event_start
        and d.viewed_at < v_event_end
      )

      or

      (
        not v_event_active
        and d.activity_date = v_today
      )

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


  -- 호감 처리
  if p_decision = 'like' then


    -- 이벤트 중
    if v_event_active then

      select count(*)::integer

      into v_likes

      from public.daily_discovery d

      where d.user_id = v_uid

        and d.decision = 'like'

        and d.decided_at >= v_event_start

        and d.decided_at < v_event_end;


      -- 48시간 전체에서 5개 제한
      if v_likes >= (5 + v_bonus_likes) then
        raise exception 'EVENT_LIKE_LIMIT_REACHED';
      end if;


    -- 일반 기간
    else

      select count(*)::integer

      into v_likes

      from public.daily_discovery d

      where d.user_id = v_uid

        and d.activity_date = v_today

        and d.decision = 'like';


      if v_likes >= (5 + v_bonus_likes) then
        raise exception 'DAILY_LIKE_LIMIT_REACHED';
      end if;


    end if;


    insert into public.likes (
      from_user,
      to_user
    )

    values (
      v_uid,
      v_target_user
    )

    on conflict (
      from_user,
      to_user
    )

    do nothing;


  end if;


  update public.daily_discovery d

  set
    decision = p_decision,
    decided_at = now()

  where d.user_id = v_uid

    and d.target_user = v_target_user

    and d.activity_date = v_activity_date;


  if p_decision = 'like' then

    v_matched :=
      public.is_match(v_target_user);

  end if;


  -- 이벤트 중 사용량
  if v_event_active then


    select

      count(*)::integer,

      count(*) filter (

        where d.decision = 'like'

          and d.decided_at >= v_event_start

          and d.decided_at < v_event_end

      )::integer


    into
      v_views,
      v_likes


    from public.daily_discovery d


    where d.user_id = v_uid

      and d.viewed_at >= v_event_start

      and d.viewed_at < v_event_end;


    return query

    select
      v_matched,
      v_views,
      2147483647,
      v_likes,
      (5 + v_bonus_likes);


  -- 일반 기간
  else


    select

      count(*)::integer,

      count(*) filter (
        where d.decision = 'like'
      )::integer


    into
      v_views,
      v_likes


    from public.daily_discovery d


    where d.user_id = v_uid

      and d.activity_date = v_today;


    return query

    select
      v_matched,
      v_views,
      (10 + v_bonus_views),
      v_likes,
      (5 + v_bonus_likes);


  end if;

end;
$function$;

revoke all on function public.get_match_feedback_status() from public, anon;
revoke all on function public.submit_match_feedback(text,text,text,text,text,text) from public, anon;
revoke all on function public.get_match_feedback_admin_stats() from public, anon;
grant execute on function public.get_match_feedback_status() to authenticated;
grant execute on function public.submit_match_feedback(text,text,text,text,text,text) to authenticated;
grant execute on function public.get_match_feedback_admin_stats() to authenticated;

revoke all on function public.get_daily_discovery_status() from public, anon;
revoke all on function public.get_discovery_event_status() from public, anon;
revoke all on function public.get_next_candidate() from public, anon;
revoke all on function public.record_candidate_decision(uuid,text) from public, anon;
grant execute on function public.get_daily_discovery_status() to authenticated;
grant execute on function public.get_discovery_event_status() to authenticated;
grant execute on function public.get_next_candidate() to authenticated;
grant execute on function public.record_candidate_decision(uuid,text) to authenticated;

commit;
NOTIFY pgrst, 'reload schema';
