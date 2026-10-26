-- EveryTimeMatch AFTER EXAM: anonymous letters
-- Existing tables and matching continue unchanged.
-- Install in Supabase SQL Editor, then enable via:
-- update public.event_letter_settings set enabled=true, starts_at=now(), ends_at=now()+interval '7 days' where id=1;
-- Default disabled so the event cannot go public before validation.
begin;

create table if not exists public.event_letter_settings (
 id integer primary key default 1 check (id=1),
 enabled boolean not null default false,
 starts_at timestamptz not null default now(),
 ends_at timestamptz not null default (now()+interval '7 days')
);
insert into public.event_letter_settings (id,enabled) values (1,false)
on conflict (id) do nothing;

create table if not exists public.event_letters (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references auth.users(id) on delete cascade,
 body text not null check (char_length(btrim(body)) between 30 and 200),
 is_hidden boolean not null default false,
 created_at timestamptz not null default now(),
 unique (author_id)
);

create table if not exists public.event_letter_views (
 viewer_id uuid not null references auth.users(id) on delete cascade,
 letter_id uuid not null references public.event_letters(id) on delete cascade,
 viewed_date date not null,
 viewed_at timestamptz not null default now(),
 primary key (viewer_id,letter_id)
);
create index if not exists event_letter_views_daily_idx on public.event_letter_views(viewer_id, viewed_date);

create table if not exists public.event_letter_replies (
 id uuid primary key default gen_random_uuid(),
 letter_id uuid not null references public.event_letters(id) on delete cascade,
 sender_id uuid not null references auth.users(id) on delete cascade,
 body text not null check (char_length(btrim(body)) between 1 and 200),
 is_hidden boolean not null default false,
 accepted boolean not null default false,
 created_at timestamptz not null default now(),
 unique(letter_id,sender_id)
);
create unique index if not exists event_one_accepted_reply_idx on public.event_letter_replies(letter_id) where accepted;
create index if not exists event_replies_daily_idx on public.event_letter_replies(sender_id, created_at);

create table if not exists public.event_letter_mutes (
 user_id uuid not null references auth.users(id) on delete cascade,
 target_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (user_id,target_id),
 check (user_id<>target_id)
);

create table if not exists public.event_letter_reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references auth.users(id) on delete cascade,
 reported_id uuid not null references auth.users(id) on delete cascade,
 letter_id uuid references public.event_letters(id) on delete set null,
 reply_id uuid references public.event_letter_replies(id) on delete set null,
 category text not null check(category in ('괴롭힘/욕설','성적 발언','사칭','스팸/홍보','부적절한 콘텐츠','기타')),
 reason text check(reason is null or char_length(reason)<=500),
 evidence text not null,
 status text not null default 'pending' check(status in ('pending','dismissed','hidden')),
 created_at timestamptz not null default now(),
 check (reporter_id<>reported_id)
);

-- No direct browser table access; all reads/writes run through constrained RPCs.
alter table public.event_letter_settings enable row level security;
alter table public.event_letters enable row level security;
alter table public.event_letter_views enable row level security;
alter table public.event_letter_replies enable row level security;
alter table public.event_letter_mutes enable row level security;
alter table public.event_letter_reports enable row level security;
revoke all on public.event_letter_settings,public.event_letters,public.event_letter_views,
 public.event_letter_replies,public.event_letter_mutes,public.event_letter_reports
 from anon,authenticated;

create or replace function public.event_is_active()
returns boolean language sql stable security definer set search_path=''
as $$
 select coalesce((select s.enabled and now() between s.starts_at and s.ends_at
 from public.event_letter_settings s where s.id=1),false);
$$;

create or replace function public.event_require_access()
returns uuid language plpgsql stable security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if not exists(select 1 from public.get_my_access_status() a where a.access_allowed) then
   raise exception 'SCHOOL_VERIFICATION_REQUIRED';
 end if;
 if not exists(select 1 from public.profiles p
   join public.legal_consents c on c.user_id=p.user_id
   where p.user_id=v_uid and p.is_active and c.adult_confirmed
   and c.terms_version='2026-10-01' and c.privacy_version='2026-10-01') then
   raise exception 'PROFILE_OR_CONSENT_REQUIRED';
 end if;
 return v_uid;
end;
$$;

create or replace function public.event_require_open()
returns void language plpgsql stable security definer set search_path=''
as $$
begin
 if not public.event_is_active() then raise exception 'EVENT_CLOSED'; end if;
end;
$$;

create or replace function public.event_pair_allowed(p_first uuid, p_second uuid)
returns boolean language sql stable security definer set search_path=''
as $$
 select exists(
 select 1 from public.profiles a join public.profiles b on b.user_id=p_second
 where a.user_id=p_first and a.is_active and b.is_active and a.user_id<>b.user_id
 and (a.preference='상관없음' or a.preference=b.gender)
 and (b.preference='상관없음' or b.preference=a.gender)
 and (a.relationship_intent='둘 다' or b.relationship_intent='둘 다' or a.relationship_intent=b.relationship_intent)
 and not exists(select 1 from public.blocks bl where (bl.blocker=p_first and bl.blocked=p_second) or (bl.blocker=p_second and bl.blocked=p_first))
 and not exists(select 1 from public.event_letter_mutes m where (m.user_id=p_first and m.target_id=p_second) or (m.user_id=p_second and m.target_id=p_first))
 and not exists(select 1 from public.matches ma where ma.user_a=least(p_first,p_second) and ma.user_b=greatest(p_first,p_second))
 );
$$;

create or replace function public.event_status()
returns table(event_active boolean,ends_at timestamptz,my_letter_sent boolean,views_used integer,replies_used integer)
language plpgsql stable security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_today date:=(now() at time zone 'Asia/Seoul')::date;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 return query select public.event_is_active(),s.ends_at,
 exists(select 1 from public.event_letters l where l.author_id=v_uid),
 (select count(*)::integer from public.event_letter_views v where v.viewer_id=v_uid and v.viewed_date=v_today),
 (select count(*)::integer from public.event_letter_replies r where r.sender_id=v_uid and (r.created_at at time zone 'Asia/Seoul')::date=v_today)
 from public.event_letter_settings s where s.id=1;
end;
$$;

create or replace function public.event_write_letter(p_body text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_uid uuid; v_id uuid;
begin
 perform public.event_require_open();v_uid:=public.event_require_access();
 if char_length(btrim(coalesce(p_body,''))) not between 30 and 200 then raise exception 'LETTER_LENGTH'; end if;
 if p_body ~* '(https?://|www[.]|@|010[- ]?[0-9]{4}[- ]?[0-9]{4})' then raise exception 'CONTACT_NOT_ALLOWED'; end if;
 insert into public.event_letters(author_id,body) values(v_uid,btrim(p_body))
 returning id into v_id;
 return v_id;
exception when unique_violation then raise exception 'LETTER_ALREADY_SENT';
end;
$$;

-- Repeated calls give today's already assigned letters; at most five new views/day.
create or replace function public.event_browse_letters()
returns table(letter_id uuid,letter_body text,created_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid;v_today date:=(now() at time zone 'Asia/Seoul')::date;v_count integer;v_letter uuid;
begin
 perform public.event_require_open(); v_uid:=public.event_require_access();
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_uid::text),7126);
 select count(*)::integer into v_count from public.event_letter_views v where v.viewer_id=v_uid and v.viewed_date=v_today;
 while v_count<5 loop
   select l.id into v_letter from public.event_letters l
   where l.is_hidden=false and public.event_pair_allowed(v_uid,l.author_id)
   and not exists(select 1 from public.event_letter_views v where v.viewer_id=v_uid and v.letter_id=l.id)
   order by random() limit 1;
   exit when v_letter is null;
   insert into public.event_letter_views(viewer_id,letter_id,viewed_date) values(v_uid,v_letter,v_today);
   v_count:=v_count+1;
 end loop;
 return query select l.id,l.body,l.created_at from public.event_letter_views v
 join public.event_letters l on l.id=v.letter_id
 where v.viewer_id=v_uid and v.viewed_date=v_today and l.is_hidden=false
 and public.event_pair_allowed(v_uid,l.author_id)
 order by v.viewed_at limit 5;
end;
$$;

create or replace function public.event_reply_letter(p_letter uuid,p_body text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_uid uuid;v_author uuid;v_id uuid;v_used integer;
begin
 perform public.event_require_open();v_uid:=public.event_require_access();
 if char_length(btrim(coalesce(p_body,''))) not between 1 and 200 then raise exception 'REPLY_LENGTH'; end if;
 if p_body ~* '(https?://|www[.]|@|010[- ]?[0-9]{4}[- ]?[0-9]{4})' then raise exception 'CONTACT_NOT_ALLOWED'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_uid::text),7126);
 select l.author_id into v_author from public.event_letters l join public.event_letter_views v
 on v.letter_id=l.id and v.viewer_id=v_uid where l.id=p_letter and l.is_hidden=false;
 if v_author is null or not public.event_pair_allowed(v_uid,v_author) then raise exception 'LETTER_NOT_AVAILABLE'; end if;
 select count(*) into v_used from public.event_letter_replies r where r.sender_id=v_uid
 and (r.created_at at time zone 'Asia/Seoul')::date=(now() at time zone 'Asia/Seoul')::date;
 if v_used>=3 then raise exception 'DAILY_REPLY_LIMIT_REACHED'; end if;
 insert into public.event_letter_replies(letter_id,sender_id,body)
 values(p_letter,v_uid,btrim(p_body)) returning id into v_id;
 return v_id;
exception when unique_violation then raise exception 'ALREADY_REPLIED';
end;
$$;

create or replace function public.event_my_replies()
returns table(reply_id uuid,reply_body text,created_at timestamptz,accepted boolean,expires_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare v_uid uuid;
begin
 v_uid:=public.event_require_access();
 return query select r.id,r.body,r.created_at,r.accepted,r.created_at+interval '48 hours'
 from public.event_letter_replies r join public.event_letters l on l.id=r.letter_id
 where l.author_id=v_uid and l.is_hidden=false and r.is_hidden=false
 and not exists(select 1 from public.blocks b where (b.blocker=v_uid and b.blocked=r.sender_id) or (b.blocker=r.sender_id and b.blocked=v_uid))
 and not exists(select 1 from public.event_letter_mutes m where (m.user_id=v_uid and m.target_id=r.sender_id) or (m.user_id=r.sender_id and m.target_id=v_uid))
 order by r.created_at desc limit 100;
end;
$$;

-- Only one reply per letter can become a match, protecting against concurrent approvals.
create or replace function public.event_accept_reply(p_reply uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_uid uuid;v_sender uuid;v_author uuid;v_letter uuid;v_at timestamptz;v_existing text;
begin
 perform public.event_require_open();v_uid:=public.event_require_access();
 select r.letter_id into v_letter from public.event_letter_replies r where r.id=p_reply and r.is_hidden=false;
 if v_letter is null then raise exception 'NOT_ALLOWED'; end if;
 perform 1 from public.event_letters l where l.id=v_letter and l.is_hidden=false for update;
 if not found then raise exception 'LETTER_NOT_AVAILABLE'; end if;
 select l.author_id,r.sender_id,r.created_at into v_author,v_sender,v_at
 from public.event_letter_replies r join public.event_letters l on l.id=r.letter_id where r.id=p_reply;
 if v_author<>v_uid or v_sender is null then raise exception 'NOT_ALLOWED'; end if;
 if v_at+interval '48 hours'<now() then raise exception 'REPLY_EXPIRED'; end if;
 if not public.event_pair_allowed(v_uid,v_sender) then raise exception 'PAIR_NOT_AVAILABLE'; end if;
 if exists(select 1 from public.event_letter_replies r where r.letter_id=v_letter and r.accepted) then raise exception 'LETTER_ALREADY_MATCHED'; end if;
 update public.event_letter_replies r set accepted=true where r.id=p_reply;
 insert into public.matches(user_a,user_b,status)
 values(least(v_uid,v_sender),greatest(v_uid,v_sender),'active');
 return true;
end;
$$;

create or replace function public.event_report_letter(p_letter uuid,p_category text,p_reason text default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_uid uuid;v_author uuid;v_body text;v_id uuid;
begin
 v_uid:=public.event_require_access();
 if p_category not in ('괴롭힘/욕설','성적 발언','사칭','스팸/홍보','부적절한 콘텐츠','기타') then raise exception 'INVALID_REPORT_CATEGORY'; end if;
 if char_length(coalesce(p_reason,''))>500 then raise exception 'REASON_TOO_LONG'; end if;
 select l.author_id,l.body into v_author,v_body from public.event_letters l
 join public.event_letter_views v on v.letter_id=l.id and v.viewer_id=v_uid where l.id=p_letter;
 if v_author is null or v_author=v_uid then raise exception 'NOT_ALLOWED'; end if;
 if exists(select 1 from public.event_letter_reports er where er.reporter_id=v_uid and er.letter_id=p_letter) then raise exception 'ALREADY_REPORTED'; end if;
 insert into public.event_letter_reports(reporter_id,reported_id,letter_id,category,reason,evidence)
 values(v_uid,v_author,p_letter,p_category,nullif(btrim(p_reason),''),v_body) returning id into v_id;
 insert into public.event_letter_mutes(user_id,target_id) values(v_uid,v_author) on conflict do nothing;
 return v_id;
end;
$$;

create or replace function public.event_report_reply(p_reply uuid,p_category text,p_reason text default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_uid uuid;v_sender uuid;v_body text;v_id uuid;
begin
 v_uid:=public.event_require_access();
 if p_category not in ('괴롭힘/욕설','성적 발언','사칭','스팸/홍보','부적절한 콘텐츠','기타') then raise exception 'INVALID_REPORT_CATEGORY'; end if;
 if char_length(coalesce(p_reason,''))>500 then raise exception 'REASON_TOO_LONG'; end if;
 select r.sender_id,r.body into v_sender,v_body from public.event_letter_replies r
 join public.event_letters l on l.id=r.letter_id where r.id=p_reply and l.author_id=v_uid;
 if v_sender is null then raise exception 'NOT_ALLOWED'; end if;
 if exists(select 1 from public.event_letter_reports er where er.reporter_id=v_uid and er.reply_id=p_reply) then raise exception 'ALREADY_REPORTED'; end if;
 insert into public.event_letter_reports(reporter_id,reported_id,reply_id,category,reason,evidence)
 values(v_uid,v_sender,p_reply,p_category,nullif(btrim(p_reason),''),v_body) returning id into v_id;
 insert into public.event_letter_mutes(user_id,target_id) values(v_uid,v_sender) on conflict do nothing;
 return v_id;
end;
$$;


-- Moderators see evidence and may hide abusive content without exposing identities publicly.
create or replace function public.event_admin_reports()
returns table(report_id uuid,report_type text,content_id uuid,category text,reason text,evidence text,created_at timestamptz,status text)
language plpgsql security definer set search_path=''
as $$
begin
 if auth.uid() is null or not public.is_admin(auth.uid()) then raise exception 'ADMIN_REQUIRED'; end if;
 return query select r.id,
 case when r.letter_id is not null then 'letter' else 'reply' end,
 coalesce(r.letter_id,r.reply_id),r.category,r.reason,r.evidence,r.created_at,r.status
 from public.event_letter_reports r order by r.created_at desc limit 100;
end;
$$;

create or replace function public.event_admin_review_report(p_report uuid,p_action text)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_letter uuid; v_reply uuid;
begin
 if auth.uid() is null or not public.is_admin(auth.uid()) then raise exception 'ADMIN_REQUIRED'; end if;
 if p_action not in ('dismiss','hide') then raise exception 'INVALID_ACTION'; end if;
 select r.letter_id,r.reply_id into v_letter,v_reply from public.event_letter_reports r
 where r.id=p_report and r.status='pending' for update;
 if not found then raise exception 'REPORT_NOT_PENDING'; end if;
 if p_action='hide' then
   if v_letter is not null then update public.event_letters set is_hidden=true where id=v_letter; end if;
   if v_reply is not null then update public.event_letter_replies set is_hidden=true where id=v_reply; end if;
 end if;
 update public.event_letter_reports set status=case when p_action='hide' then 'hidden' else 'dismissed' end where id=p_report;
 return true;
end;
$$;

revoke all on function public.event_is_active(),public.event_require_access(),
 public.event_require_open(),public.event_pair_allowed(uuid,uuid),
 public.event_status(),public.event_write_letter(text),public.event_browse_letters(),
 public.event_reply_letter(uuid,text),public.event_my_replies(),public.event_accept_reply(uuid),
 public.event_report_letter(uuid,text,text),public.event_report_reply(uuid,text,text),
 public.event_admin_reports(),public.event_admin_review_report(uuid,text) from public, anon, authenticated;
grant execute on function public.event_status(),public.event_write_letter(text),
 public.event_browse_letters(),public.event_reply_letter(uuid,text),public.event_my_replies(),
 public.event_accept_reply(uuid),public.event_report_letter(uuid,text,text),
 public.event_report_reply(uuid,text,text),public.event_admin_reports(),
 public.event_admin_review_report(uuid,text) to authenticated;
commit;
notify pgrst,'reload schema';
