-- Everytime Match
-- 2026-10-01: replace email OTP school verification with Microsoft (Azure) OAuth.
--
-- Run after:
--   supabase/migrations/20261001_beta_readiness_school_verification.sql
--
-- Existing beta-test accounts continue to work through public.beta_testers.
-- New school verification requires:
--   1) an Azure/Microsoft identity on the Supabase user
--   2) the authenticated email domain to be exactly @sangmyung.kr

begin;

-- Keep the domain table for documentation/admin visibility, but only the
-- student Microsoft domain is considered school-verified in this migration.
update public.school_email_domains
set is_active = (domain = 'sangmyung.kr');

insert into public.school_email_domains(domain, is_active)
values ('sangmyung.kr', true)
on conflict (domain)
do update set is_active = true;

-- A school-verified account must have signed in through Microsoft's Azure
-- provider and must expose the Sangmyung student-domain email.
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
    where u.id = p_user_id
      and split_part(lower(coalesce(u.email, '')), '@', 2) = 'sangmyung.kr'
      and exists (
        select 1
        from auth.identities i
        where i.user_id = u.id
          and i.provider = 'azure'
          and split_part(lower(coalesce(i.email, '')), '@', 2) = 'sangmyung.kr'
      )
  );
$$;

create or replace function public.get_verification_kind(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if p_user_id is null then
    return 'unverified';
  end if;

  if public.is_school_verified(p_user_id) then
    return 'school_verified';
  end if;

  if public.is_beta_tester(p_user_id) then
    return 'beta_tester';
  end if;

  if exists (
    select 1
    from auth.identities i
    where i.user_id = p_user_id
      and i.provider = 'azure'
  ) then
    return 'wrong_microsoft_account';
  end if;

  return 'microsoft_required';
end;
$$;

-- can_use_beta already delegates to is_school_verified() OR beta_testers,
-- so replacing is_school_verified() above switches new users to Microsoft OAuth.
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

-- Keep helpers internal except those explicitly needed by browser/RLS.
revoke all on function public.is_school_verified(uuid) from public;
revoke all on function public.get_verification_kind(uuid) from public;
revoke all on function public.can_use_beta(uuid) from public;
revoke all on function public.get_my_access_status() from public;

grant execute on function public.can_use_beta(uuid) to authenticated;
grant execute on function public.get_my_access_status() to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
