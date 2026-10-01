-- Everytime Match
-- 2026-10-01: public beta hardening
-- - legal consent records
-- - robust report schema/RPC for candidate, match, and message reports

begin;

-- =========================================================
-- 1. Legal consent records
-- =========================================================

create table if not exists public.legal_consents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  terms_version text not null,
  privacy_version text not null,
  adult_confirmed boolean not null default false,
  accepted_at timestamptz not null default now()
);

alter table public.legal_consents enable row level security;

revoke all on table public.legal_consents from anon, authenticated;
grant select, insert, update on table public.legal_consents to authenticated;

drop policy if exists "read own legal consent" on public.legal_consents;
create policy "read own legal consent"
on public.legal_consents for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "insert own legal consent" on public.legal_consents;
create policy "insert own legal consent"
on public.legal_consents for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "update own legal consent" on public.legal_consents;
create policy "update own legal consent"
on public.legal_consents for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Existing beta users are not auto-consented.
-- They will be asked to agree in the UI on their next visit.

-- =========================================================
-- 2. Ensure report columns exist
-- =========================================================

alter table public.reports
  add column if not exists category text;

alter table public.reports
  add column if not exists match_id uuid;

alter table public.reports
  add column if not exists message_id uuid;

alter table public.reports
  add column if not exists status text not null default 'pending';

create index if not exists reports_reported_created_idx
  on public.reports(reported, created_at desc);

create index if not exists reports_status_created_idx
  on public.reports(status, created_at desc);

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
        or category in (
          '괴롭힘/욕설',
          '성적 발언',
          '사칭',
          '스팸/홍보',
          '부적절한 콘텐츠',
          '기타'
        )
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

-- =========================================================
-- 3. Recreate report RPC
-- =========================================================

drop function if exists public.submit_report(uuid, text, text);
drop function if exists public.submit_report(uuid, text, text, uuid);

create function public.submit_report(
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
  v_allowed boolean := false;
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

  if not exists (select 1 from auth.users u where u.id = p_reported) then
    raise exception 'REPORT_TARGET_NOT_AVAILABLE';
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

  -- Message report: verify that the reported message was actually sent by
  -- the target inside a match that involved the reporter.
  if p_message_id is not null then
    select msg.match_id
    into v_match_id
    from public.messages msg
    join public.matches m on m.id = msg.match_id
    where msg.id = p_message_id
      and msg.sender_id = p_reported
      and (m.user_a = v_uid or m.user_b = v_uid)
      and (m.user_a = p_reported or m.user_b = p_reported)
    limit 1;

    if not found then
      raise exception 'INVALID_REPORT_MESSAGE';
    end if;

    v_allowed := true;
  else
    -- Match/profile report: first accept a current or previous counterpart.
    select m.id
    into v_match_id
    from public.matches m
    where (m.user_a = v_uid and m.user_b = p_reported)
       or (m.user_a = p_reported and m.user_b = v_uid)
    order by m.matched_at desc
    limit 1;

    if found then
      v_allowed := true;
    else
      -- Candidate report before matching: the target must have actually been
      -- shown to the reporter through discovery.
      select exists (
        select 1
        from public.daily_discovery d
        where d.user_id = v_uid
          and d.target_user = p_reported
      )
      into v_allowed;
    end if;
  end if;

  if not v_allowed then
    raise exception 'REPORT_TARGET_NOT_AVAILABLE';
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

  -- If reported directly from discovery, mark the current undecided item as
  -- passed so it cannot be acted on again later.
  update public.daily_discovery
  set
    decision = coalesce(decision, 'pass'),
    decided_at = coalesce(decided_at, now())
  where user_id = v_uid
    and target_user = p_reported
    and decision is null;

  return v_report_id;
end;
$$;

revoke all on function public.submit_report(uuid, text, text, uuid) from public;
grant execute on function public.submit_report(uuid, text, text, uuid) to authenticated;

commit;

NOTIFY pgrst, 'reload schema';
