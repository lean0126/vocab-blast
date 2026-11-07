-- VOCAB BLAST ARENA ONLINE / Supabase PostgreSQL
-- Run once in SQL Editor. Change class code before distributing it.
create extension if not exists pgcrypto;
create table if not exists public.classes(id uuid primary key default gen_random_uuid(), name text not null, code_hash text not null, created_at timestamptz default now());
create table if not exists public.profiles(id uuid primary key references auth.users(id) on delete cascade, display_name text not null check(char_length(display_name) between 2 and 32), class_id uuid not null references public.classes(id), role text not null default 'student' check(role in ('student','teacher')), xp integer not null default 0 check(xp>=0), coins integer not null default 0 check(coins>=0), wins integer not null default 0 check(wins>=0), created_at timestamptz default now());
create table if not exists public.questions(id bigint generated always as identity primary key, vi text not null, en text not null, distractors text[] not null check(array_length(distractors,1)=3));
create table if not exists public.rooms(id uuid primary key default gen_random_uuid(), code text not null unique, class_id uuid not null references public.classes(id), owner_id uuid not null references public.profiles(id), mode text not null check(mode in ('solo','group')), status text not null default 'waiting' check(status in ('waiting','playing','finished')), question_ids bigint[] not null default '{}', started_at timestamptz, created_at timestamptz default now(), settled boolean not null default false);
create table if not exists public.room_players(room_id uuid references public.rooms(id) on delete cascade, user_id uuid references public.profiles(id) on delete cascade, score integer not null default 0, joined_at timestamptz default now(), primary key(room_id,user_id));
create table if not exists public.answers(room_id uuid not null references public.rooms(id) on delete cascade, user_id uuid not null references public.profiles(id), question_no integer not null, selected text not null, correct boolean not null, awarded integer not null, answered_at timestamptz default now(), primary key(room_id,user_id,question_no));
create table if not exists public.rewards(id bigint generated always as identity primary key, title text not null, cost integer not null check(cost>0), active boolean not null default true);
create table if not exists public.redemptions(id bigint generated always as identity primary key, user_id uuid not null references public.profiles(id), reward_id bigint not null references public.rewards(id), cost integer not null, status text not null default 'pending' check(status in ('pending','approved','rejected')), created_at timestamptz default now(), reviewed_at timestamptz);
create table if not exists public.coin_ledger(id bigint generated always as identity primary key, user_id uuid not null references public.profiles(id), delta integer not null, reason text not null, created_at timestamptz default now());
create index if not exists idx_profiles_class on public.profiles(class_id,xp desc);
create index if not exists idx_rooms_class on public.rooms(class_id,created_at desc);
create index if not exists idx_redemptions_status on public.redemptions(status);

alter table public.classes enable row level security;
alter table public.profiles enable row level security;
alter table public.questions enable row level security;
alter table public.rooms enable row level security;
alter table public.room_players enable row level security;
alter table public.answers enable row level security;
alter table public.rewards enable row level security;
alter table public.redemptions enable row level security;
alter table public.coin_ledger enable row level security;
-- No direct table access from browser; only carefully checked RPCs.
revoke all on public.classes,public.profiles,public.questions,public.rooms,public.room_players,public.answers,public.rewards,public.redemptions,public.coin_ledger from anon,authenticated;

create or replace function public.my_profile() returns jsonb language sql security definer set search_path=public as $$
 select to_jsonb(p) from profiles p where p.id=auth.uid()
$$;
create or replace function public.join_class(p_name text,p_code text) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare c classes%rowtype; p profiles%rowtype;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập'; end if;
 if length(trim(p_name)) not between 2 and 32 then raise exception 'Tên cần 2–32 ký tự'; end if;
 select * into p from profiles where id=auth.uid();
 if found then return to_jsonb(p); end if;
 select * into c from classes where code_hash=crypt(upper(trim(p_code)),code_hash) limit 1;
 if not found then raise exception 'Mã lớp không đúng'; end if;
 insert into profiles(id,display_name,class_id) values(auth.uid(),trim(p_name),c.id) returning * into p;
 return to_jsonb(p);
end $$;
create or replace function public.is_teacher(p_class uuid) returns boolean language sql security definer set search_path=public as $$
 select exists(select 1 from profiles where id=auth.uid() and class_id=p_class and role='teacher')
$$;
create or replace function public.leaderboard() returns jsonb language plpgsql security definer set search_path=public as $$
declare c uuid;
begin
 select class_id into c from profiles where id=auth.uid();
 if c is null then raise exception 'Chưa vào lớp'; end if;
 return coalesce((select jsonb_agg(to_jsonb(t)) from (select display_name,xp,coins,wins from profiles where class_id=c and role='student' order by xp desc,wins desc limit 100)t),'[]'::jsonb);
end $$;
create or replace function public.create_room(p_mode text) returns jsonb language plpgsql security definer set search_path=public as $$
declare p profiles%rowtype; r rooms%rowtype; c text; attempts int:=0;
begin
 select * into p from profiles where id=auth.uid(); if not found then raise exception 'Chưa vào lớp'; end if;
 if p_mode not in ('solo','group') then raise exception 'Chế độ không hợp lệ'; end if;
 loop
  c:=upper(substr(encode(gen_random_bytes(5),'hex'),1,6));
  begin
   insert into rooms(code,class_id,owner_id,mode) values(c,p.class_id,p.id,p_mode) returning * into r;
   exit;
  exception when unique_violation then attempts:=attempts+1; if attempts>5 then raise; end if;
  end;
 end loop;
 insert into room_players(room_id,user_id) values(r.id,p.id);
 return jsonb_build_object('code',r.code,'id',r.id);
end $$;
create or replace function public.join_room(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
declare p profiles%rowtype; r rooms%rowtype; n integer;
begin
 select * into p from profiles where id=auth.uid(); if not found then raise exception 'Chưa vào lớp'; end if;
 select * into r from rooms where code=upper(trim(p_code)) and class_id=p.class_id and status='waiting' for update;
 if not found then raise exception 'Không tìm thấy phòng đang chờ trong lớp'; end if;
 select count(*) into n from room_players where room_id=r.id;
 if n >= case when r.mode='solo' then 2 else 30 end then raise exception 'Phòng đã đầy'; end if;
 insert into room_players(room_id,user_id) values(r.id,p.id) on conflict do nothing;
 return jsonb_build_object('code',r.code,'id',r.id);
end $$;
create or replace function public.start_room(p_code text) returns void language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype; n int; ids bigint[];
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or r.owner_id<>auth.uid() or r.status<>'waiting' then raise exception 'Chỉ chủ phòng đang chờ được bắt đầu'; end if;
 select count(*) into n from room_players where room_id=r.id;
 if n<2 then raise exception 'Cần ít nhất 2 người'; end if;
 select array_agg(id) into ids from (select id from questions order by random() limit 10)t;
 if coalesce(array_length(ids,1),0)<10 then raise exception 'Cần nhập ít nhất 10 câu hỏi'; end if;
 update rooms set status='playing',question_ids=ids,started_at=now() where id=r.id;
end $$;
-- All players get the same ordered questions, but never receive the correct answer before finishing.
create or replace function public.room_state(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype; qno int; q questions%rowtype; answered boolean; opts jsonb; people jsonb; me profiles%rowtype;
begin
 select * into me from profiles where id=auth.uid();
 select * into r from rooms where code=upper(trim(p_code)) and class_id=me.class_id;
 if not found or not exists(select 1 from room_players where room_id=r.id and user_id=auth.uid()) then raise exception 'Bạn không thuộc phòng'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('name',p.display_name,'score',rp.score,'id',rp.user_id) order by rp.score desc),'[]'::jsonb) into people from room_players rp join profiles p on p.id=rp.user_id where rp.room_id=r.id;
 if r.status='playing' and now()>=r.started_at+interval '210 seconds' then
   update rooms set status='finished' where id=r.id; r.status:='finished';
 end if;
 if r.status='playing' then
  qno:=least(10,1+floor(extract(epoch from now()-r.started_at)/21)::int);
  select * into q from questions where id=r.question_ids[qno];
  select exists(select 1 from answers where room_id=r.id and user_id=auth.uid() and question_no=qno) into answered;
  -- deterministic rotation of options, shared among all clients
  opts:=to_jsonb(case (q.id % 4) when 0 then array[q.en,q.distractors[1],q.distractors[2],q.distractors[3]] when 1 then array[q.distractors[1],q.en,q.distractors[2],q.distractors[3]] when 2 then array[q.distractors[1],q.distractors[2],q.en,q.distractors[3]] else array[q.distractors[1],q.distractors[2],q.distractors[3],q.en] end);
  return jsonb_build_object('status',r.status,'mode',r.mode,'owner',r.owner_id,'players',people,'question_no',qno,'question',q.vi,'options',opts,'answered',answered,'deadline',r.started_at+make_interval(secs=>qno*21),'server_time',now());
 end if;
 return jsonb_build_object('status',r.status,'mode',r.mode,'owner',r.owner_id,'players',people,'server_time',now());
end $$;
create or replace function public.submit_answer(p_code text,p_selected text) returns jsonb language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype; q questions%rowtype; qno int; ok boolean; pts int; old answers%rowtype;
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or r.status<>'playing' then raise exception 'Trận chưa bắt đầu hoặc đã kết thúc'; end if;
 if not exists(select 1 from room_players where room_id=r.id and user_id=auth.uid()) then raise exception 'Không thuộc phòng'; end if;
 if now()>=r.started_at+interval '210 seconds' then raise exception 'Hết giờ'; end if;
 qno:=1+floor(extract(epoch from now()-r.started_at)/21)::int;
 if qno not between 1 and 10 then raise exception 'Hết giờ'; end if;
 select * into old from answers where room_id=r.id and user_id=auth.uid() and question_no=qno;
 if found then return jsonb_build_object('correct',old.correct,'points',old.awarded,'duplicate',true); end if;
 select * into q from questions where id=r.question_ids[qno];
 if p_selected is null or p_selected<>all(array[q.en,q.distractors[1],q.distractors[2],q.distractors[3]]) then
   -- check correct or one of the distractors
   if p_selected is distinct from q.en then raise exception 'Đáp án không hợp lệ'; end if;
 end if;
 ok:=(p_selected=q.en);
 pts:=case when ok then 100 + greatest(0,20-floor(extract(epoch from now()-(r.started_at+make_interval(secs=>(qno-1)*21))))::int)*5 else 0 end;
 insert into answers(room_id,user_id,question_no,selected,correct,awarded) values(r.id,auth.uid(),qno,p_selected,ok,pts);
 update room_players set score=score+pts where room_id=r.id and user_id=auth.uid();
 return jsonb_build_object('correct',ok,'points',pts);
end $$;
-- Settlement occurs once, on demand, after the 210-second match duration.
create or replace function public.finish_room(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
declare r rooms%rowtype; winner uuid; rec record; gain int;
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or not exists(select 1 from room_players where room_id=r.id and user_id=auth.uid()) then raise exception 'Không thuộc phòng'; end if;
 if r.status='waiting' then raise exception 'Trận chưa bắt đầu'; end if;
 if r.started_at+interval '210 seconds'>now() then raise exception 'Trận chưa kết thúc'; end if;
 -- Locking rooms serializes settlement. Use a separate settled flag to prevent double credit.
 if r.settled then return public.room_state(p_code); end if;
 select user_id into winner from room_players where room_id=r.id order by score desc,joined_at asc limit 1;
 for rec in select user_id,score from room_players where room_id=r.id loop
   gain:=least(60,10+rec.score/100);
   update profiles set xp=xp+rec.score,coins=coins+gain,wins=wins+case when rec.user_id=winner then 1 else 0 end where id=rec.user_id;
   insert into coin_ledger(user_id,delta,reason) values(rec.user_id,gain,'Hoàn thành trận '||r.code);
 end loop;
 update rooms set status='finished',settled=true where id=r.id;
 return public.room_state(p_code);
end $$;
create or replace function public.list_rewards() returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from profiles where id=auth.uid()) then raise exception 'Chưa vào lớp'; end if;
 return coalesce((select jsonb_agg(to_jsonb(r)) from (select id,title,cost from rewards where active order by cost)r),'[]'::jsonb);
end $$;
create or replace function public.redeem_reward(p_reward bigint) returns void language plpgsql security definer set search_path=public as $$
declare r rewards%rowtype; p profiles%rowtype;
begin
 select * into p from profiles where id=auth.uid() for update;
 if not found then raise exception 'Chưa vào lớp'; end if;
 select * into r from rewards where id=p_reward and active;
 if not found then raise exception 'Quà không hợp lệ'; end if;
 if p.coins<r.cost then raise exception 'Không đủ xu'; end if;
 update profiles set coins=coins-r.cost where id=p.id;
 insert into coin_ledger(user_id,delta,reason) values(p.id,-r.cost,'Đặt quà '||r.title);
 insert into redemptions(user_id,reward_id,cost) values(p.id,r.id,r.cost);
end $$;
create or replace function public.my_redemptions() returns jsonb language sql security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object('title',rw.title,'cost',r.cost,'status',r.status,'created_at',r.created_at) order by r.created_at desc),'[]'::jsonb) from redemptions r join rewards rw on rw.id=r.reward_id where r.user_id=auth.uid()
$$;
create or replace function public.admin_requests() returns jsonb language plpgsql security definer set search_path=public as $$
declare c uuid;
begin
 select class_id into c from profiles where id=auth.uid() and role='teacher'; if c is null then raise exception 'Chỉ giáo viên'; end if;
 return coalesce((select jsonb_agg(to_jsonb(t)) from (select r.id,r.status,r.created_at,p.display_name,rw.title,r.cost from redemptions r join profiles p on p.id=r.user_id join rewards rw on rw.id=r.reward_id where p.class_id=c order by r.created_at desc limit 100)t),'[]'::jsonb);
end $$;
create or replace function public.admin_review(p_id bigint,p_approve boolean) returns void language plpgsql security definer set search_path=public as $$
declare r redemptions%rowtype; p profiles%rowtype;
begin
 select * into r from redemptions where id=p_id for update;
 if not found or r.status<>'pending' then raise exception 'Yêu cầu không còn chờ duyệt'; end if;
 select * into p from profiles where id=r.user_id;
 if not public.is_teacher(p.class_id) then raise exception 'Chỉ giáo viên'; end if;
 update redemptions set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now() where id=r.id;
 if not p_approve then
  update profiles set coins=coins+r.cost where id=p.id;
  insert into coin_ledger(user_id,delta,reason) values(p.id,r.cost,'Hoàn xu do từ chối quà');
 end if;
end $$;
-- The following RPCs are callable only by logged-in (including anonymous-auth) users.
grant execute on function public.my_profile(),public.join_class(text,text),public.is_teacher(uuid),public.leaderboard(),public.create_room(text),public.join_room(text),public.start_room(text),public.room_state(text),public.submit_answer(text,text),public.finish_room(text),public.list_rewards(),public.redeem_reward(bigint),public.my_redemptions(),public.admin_requests(),public.admin_review(bigint,boolean) to authenticated;
revoke execute on function public.my_profile(),public.join_class(text,text),public.is_teacher(uuid),public.leaderboard(),public.create_room(text),public.join_room(text),public.start_room(text),public.room_state(text),public.submit_answer(text,text),public.finish_room(text),public.list_rewards(),public.redeem_reward(bigint),public.my_redemptions(),public.admin_requests(),public.admin_review(bigint,boolean) from public,anon;
-- Starter questions; teachers can extend with INSERT in SQL Editor.
insert into public.questions(vi,en,distractors) values
('Quả táo','Apple',array['Banana','Orange','Mango']),('Con mèo','Cat',array['Dog','Bird','Cow']),('Trường học','School',array['Hospital','Market','Library']),('Giáo viên','Teacher',array['Student','Doctor','Farmer']),('Quyển sách','Book',array['Pen','Desk','Bag']),('Màu xanh lá','Green',array['Blue','Red','Yellow']),('Gia đình','Family',array['Friend','Neighbor','Class']),('Hạnh phúc','Happy',array['Sad','Angry','Tired']),('Bơi lội','Swim',array['Run','Jump','Dance']),('Buổi sáng','Morning',array['Evening','Night','Noon']),('Máy tính','Computer',array['Television','Telephone','Camera']),('Bệnh viện','Hospital',array['School','Cinema','Airport']),('Thư viện','Library',array['Kitchen','Bedroom','Garden']),('Cầu vồng','Rainbow',array['Sunshine','Thunder','Cloud']),('Nguy hiểm','Dangerous',array['Safe','Friendly','Quiet']),('Khám phá','Discover',array['Forget','Destroy','Borrow']),('Môi trường','Environment',array['Equipment','Entertainment','Education']),('Sức khỏe','Health',array['Wealth','Strength','History']),('Trách nhiệm','Responsibility',array['Possibility','Opportunity','Activity']),('Kiến thức','Knowledge',array['Language','Homework','Journey']);
insert into public.rewards(title,cost) values ('Huy hiệu chăm học',100),('Phiếu đề xuất phần quà nhỏ',300),('Phiếu đề xuất phần quà đặc biệt',700);
-- Create class with YOUR secret code (change before use):
-- insert into public.classes(name,code_hash) values ('Lớp tiếng Anh cô Trinh',crypt('TRINH2026',gen_salt('bf')));
-- Teacher: sign up with email/password in Supabase Auth, then join_class with class code,
-- then promote the correct Auth user UUID using SQL Editor:
-- update public.profiles set role='teacher' where id='PASTE-TEACHER-AUTH-UUID';
