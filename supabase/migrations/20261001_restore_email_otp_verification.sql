-- Everytime Match
-- 2026-10-01: restore school email OTP verification after Microsoft OAuth experiment.
--
-- Safe to run once even if the Microsoft OAuth migration was never applied.
-- Existing beta tester accounts remain allowed.

begin;

insert into public.school_email_domains(domain, is_active)
values
  ('sangmyung.kr', true),
  ('smu.ac.kr', true),
  ('sangmyung.ac.kr', true)
on conflict (domain)
do update set is_active = true;

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

revoke all on function public.is_school_verified(uuid) from public;
revoke all on function public.get_verification_kind(uuid) from public;
revoke all on function public.can_use_beta(uuid) from public;
revoke all on function public.get_my_access_status() from public;

grant execute on function public.can_use_beta(uuid) to authenticated;
grant execute on function public.get_my_access_status() to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
