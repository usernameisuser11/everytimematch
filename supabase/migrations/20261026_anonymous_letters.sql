begin;
create table if not exists public.event_letters(id uuid primary key default gen_random_uuid(),author_id uuid not null references auth.users(id) on delete cascade,body text not null check(char_length(btrim(body)) between 30 and 200),created_at timestamptz not null default now(),unique(author_id));
create table if not exists public.event_letter_replies(id uuid primary key default gen_random_uuid(),letter_id uuid not null references public.event_letters(id) on delete cascade,sender_id uuid not null references auth.users(id) on delete cascade,body text not null check(char_length(btrim(body)) between 1 and 200),accepted boolean not null default false,created_at timestamptz not null default now(),unique(letter_id,sender_id));
alter table public.event_letters enable row level security;
alter table public.event_letter_replies enable row level security;
revoke all on public.event_letters,public.event_letter_replies from anon,authenticated;
create or replace function public.event_write_letter(p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_id uuid;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if char_length(btrim(coalesce(p_body,''))) not between 30 and 200 then raise exception 'LETTER_LENGTH'; end if;
 if not exists(select 1 from public.profiles where user_id=v_uid and is_active) then raise exception 'PROFILE_REQUIRED'; end if;
 insert into public.event_letters(author_id,body) values(v_uid,btrim(p_body)) returning id into v_id; return v_id;
exception when unique_violation then raise exception 'LETTER_ALREADY_SENT';
end $$;
create or replace function public.event_browse_letters() returns table(letter_id uuid,letter_body text,created_at timestamptz) language sql security definer set search_path='' as $$
 select l.id,l.body,l.created_at from public.event_letters l join public.profiles p on p.user_id=l.author_id and p.is_active
 where auth.uid() is not null and l.author_id<>auth.uid()
 and exists(select 1 from public.profiles me where me.user_id=auth.uid() and me.is_active)
 and not exists(select 1 from public.blocks b where (b.blocker=auth.uid() and b.blocked=l.author_id) or (b.blocker=l.author_id and b.blocked=auth.uid()))
 and not exists(select 1 from public.event_letter_replies r where r.letter_id=l.id and r.sender_id=auth.uid())
 order by l.created_at desc limit 20;
$$;
create or replace function public.event_reply_letter(p_letter uuid,p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_author uuid; v_id uuid;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if char_length(btrim(coalesce(p_body,''))) not between 1 and 200 then raise exception 'REPLY_LENGTH'; end if;
 select author_id into v_author from public.event_letters where id=p_letter;
 if v_author is null or v_author=v_uid then raise exception 'INVALID_LETTER'; end if;
 if not exists(select 1 from public.profiles where user_id=v_uid and is_active) then raise exception 'PROFILE_REQUIRED'; end if;
 if exists(select 1 from public.blocks where (blocker=v_uid and blocked=v_author) or (blocker=v_author and blocked=v_uid)) then raise exception 'BLOCKED'; end if;
 insert into public.event_letter_replies(letter_id,sender_id,body) values(p_letter,v_uid,btrim(p_body)) returning id into v_id;return v_id;
exception when unique_violation then raise exception 'ALREADY_REPLIED';
end $$;
create or replace function public.event_my_replies() returns table(reply_id uuid,reply_body text,created_at timestamptz,accepted boolean) language sql security definer set search_path='' as $$
 select r.id,r.body,r.created_at,r.accepted from public.event_letter_replies r join public.event_letters l on l.id=r.letter_id where l.author_id=auth.uid()
 and not exists(select 1 from public.blocks b where (b.blocker=auth.uid() and b.blocked=r.sender_id) or (b.blocker=r.sender_id and b.blocked=auth.uid()))
 order by r.created_at desc limit 100;
$$;
create or replace function public.event_accept_reply(p_reply uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid();v_sender uuid;v_author uuid;v_a uuid;v_b uuid;
begin
 select l.author_id,r.sender_id into v_author,v_sender from public.event_letter_replies r join public.event_letters l on l.id=r.letter_id where r.id=p_reply for update of r;
 if v_uid is null or v_author is distinct from v_uid or v_sender is null then raise exception 'NOT_ALLOWED'; end if;
 if exists(select 1 from public.blocks where (blocker=v_uid and blocked=v_sender) or (blocker=v_sender and blocked=v_uid)) then raise exception 'BLOCKED'; end if;
 v_a:=least(v_uid,v_sender);v_b:=greatest(v_uid,v_sender);
 if exists(select 1 from public.matches where user_a=v_a and user_b=v_b and status<>'active') then raise exception 'PREVIOUS_MATCH_ENDED'; end if;
 update public.event_letter_replies set accepted=true where id=p_reply;
 insert into public.matches(user_a,user_b,status) values(v_a,v_b,'active') on conflict(user_a,user_b) do nothing;
 return true;
end $$;
revoke all on function public.event_write_letter(text),public.event_browse_letters(),public.event_reply_letter(uuid,text),public.event_my_replies(),public.event_accept_reply(uuid) from public;
grant execute on function public.event_write_letter(text),public.event_browse_letters(),public.event_reply_letter(uuid,text),public.event_my_replies(),public.event_accept_reply(uuid) to authenticated;
commit;
notify pgrst,'reload schema';