-- Everytime Match
-- 2026-10-03: administrator profile console
-- Selected admin accounts can browse all ACTIVE public profiles at once
-- and send unlimited likes through a dedicated server-side RPC.
--
-- This migration deliberately does not guess which Auth user is the owner.
-- Add the exact owner account to public.admin_users after applying it.

begin;

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;
revoke all on table public.admin_users from anon, authenticated;

create or replace function public.is_admin(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    p_user_id is not null
    and exists (
      select 1
      from public.admin_users a
      where a.user_id = p_user_id
    );
$$;

create or replace function public.get_my_admin_status()
returns table (
  is_admin boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin(auth.uid());
$$;

create or replace function public.get_admin_profiles()
returns table (
  user_id uuid,
  nickname text,
  grade text,
  mbti text,
  gender text,
  relationship_intent text,
  bio text,
  verification_status text,
  liked_by_me boolean,
  matched_with_me boolean,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not public.is_admin(v_uid) then
    raise exception 'ADMIN_REQUIRED';
  end if;

  return query
  select
    p.user_id,
    p.nickname,
    p.grade,
    p.mbti,
    p.gender,
    p.relationship_intent,
    p.bio,
    public.get_verification_kind(p.user_id),
    exists (
      select 1
      from public.likes l
      where l.from_user = v_uid
        and l.to_user = p.user_id
    ) as liked_by_me,
    public.is_match(p.user_id) as matched_with_me,
    p.created_at
  from public.profiles p
  where p.user_id <> v_uid
    and p.is_active = true
    and public.can_use_beta(p.user_id)
  order by p.created_at desc, p.nickname asc;
end;
$$;

create or replace function public.admin_send_like(p_target_user uuid)
returns table (
  matched boolean,
  already_liked boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_exists boolean := false;
  v_matched boolean := false;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not public.is_admin(v_uid) then
    raise exception 'ADMIN_REQUIRED';
  end if;

  if p_target_user is null or p_target_user = v_uid then
    raise exception 'INVALID_TARGET';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.user_id = p_target_user
      and p.is_active = true
      and public.can_use_beta(p.user_id)
  ) then
    raise exception 'TARGET_NOT_AVAILABLE';
  end if;

  -- Blocks still prevent an admin account from sending a personal like.
  if public.is_blocked_between(p_target_user) then
    raise exception 'PROFILE_BLOCKED';
  end if;

  select exists (
    select 1
    from public.likes l
    where l.from_user = v_uid
      and l.to_user = p_target_user
  )
  into v_exists;

  if not v_exists then
    insert into public.likes(from_user, to_user)
    values (v_uid, p_target_user);
  end if;

  v_matched := public.is_match(p_target_user);

  return query
  select v_matched, v_exists;
end;
$$;

revoke all on function public.is_admin(uuid) from public;
revoke all on function public.get_my_admin_status() from public;
revoke all on function public.get_admin_profiles() from public;
revoke all on function public.admin_send_like(uuid) from public;

grant execute on function public.get_my_admin_status() to authenticated;
grant execute on function public.get_admin_profiles() to authenticated;
grant execute on function public.admin_send_like(uuid) to authenticated;

commit;

NOTIFY pgrst, 'reload schema';

-- Activate the exact owner account after this migration:
--
-- insert into public.admin_users(user_id)
-- select id
-- from auth.users
-- where lower(email) = lower('YOUR-ADMIN-EMAIL@example.com')
-- on conflict (user_id) do nothing;
