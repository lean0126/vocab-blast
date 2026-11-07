-- Run AFTER existing schema.sql. Safe additive upgrade; no DROP TABLE.
create extension if not exists pgcrypto;
alter table public.profiles alter column class_id drop not null;
alter table public.classes add column if not exists archived boolean not null default false;
create or replace function public.teacher_guard() returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not exists(select 1 from profiles where id=auth.uid() and role='teacher') then raise exception 'Chỉ giáo viên được phép thao tác'; end if;
end $$;
create or replace function public.teacher_dashboard() returns jsonb language plpgsql security definer set search_path=public as $$
begin
 perform teacher_guard();
 return jsonb_build_object(
 'classes',coalesce((select jsonb_agg(to_jsonb(t)) from (select c.id,c.name,c.archived,c.created_at,count(p.id)::int as students from classes c left join profiles p on p.class_id=c.id and p.role='student' group by c.id order by c.created_at desc)t),'[]'::jsonb),
 'students',coalesce((select jsonb_agg(to_jsonb(t)) from (select p.id,p.display_name,p.class_id,c.name as class_name,p.xp,p.coins,p.wins from profiles p join classes c on c.id=p.class_id where p.role='student' order by p.xp desc limit 500)t),'[]'::jsonb),
 'rewards',coalesce((select jsonb_agg(to_jsonb(t)) from (select id,title,cost,active from rewards order by id desc)t),'[]'::jsonb),
 'requests',coalesce((select jsonb_agg(to_jsonb(t)) from (select r.id,r.status,r.created_at,p.display_name,c.name as class_name,rw.title,r.cost from redemptions r join profiles p on p.id=r.user_id join classes c on c.id=p.class_id join rewards rw on rw.id=r.reward_id order by r.created_at desc limit 200)t),'[]'::jsonb),
 'coin_history',coalesce((select jsonb_agg(to_jsonb(t)) from (select l.id,p.display_name,l.delta,l.reason,l.created_at from coin_ledger l join profiles p on p.id=l.user_id order by l.created_at desc limit 50)t),'[]'::jsonb)
 );
end $$;
create or replace function public.teacher_create_class(p_name text) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare c classes%rowtype; code text;
begin
 perform teacher_guard();
 if length(trim(p_name)) not between 2 and 80 then raise exception 'Tên lớp cần 2–80 ký tự'; end if;
 code:=upper(encode(extensions.gen_random_bytes(9),'hex'));
 insert into classes(name,code_hash) values(trim(p_name),extensions.crypt(code,extensions.gen_salt('bf'))) returning * into c;
 return jsonb_build_object('id',c.id,'name',c.name,'code',code);
end $$;
create or replace function public.teacher_update_class(p_id uuid,p_name text,p_archived boolean) returns void language plpgsql security definer set search_path=public as $$
begin
 perform teacher_guard();
 if length(trim(p_name)) not between 2 and 80 then raise exception 'Tên lớp cần 2–80 ký tự'; end if;
 update classes set name=trim(p_name),archived=p_archived where id=p_id;
 if not found then raise exception 'Không tìm thấy lớp'; end if;
end $$;
create or replace function public.teacher_rotate_code(p_id uuid) returns text language plpgsql security definer set search_path=public,extensions as $$
declare code text;
begin
 perform teacher_guard();
 code:=upper(encode(extensions.gen_random_bytes(9),'hex'));
 update classes set code_hash=extensions.crypt(code,extensions.gen_salt('bf')) where id=p_id and not archived;
 if not found then raise exception 'Lớp không tồn tại hoặc đã khóa'; end if;
 return code;
end $$;
create or replace function public.teacher_save_reward(p_id bigint,p_title text,p_cost integer,p_active boolean) returns bigint language plpgsql security definer set search_path=public as $$
declare rid bigint;
begin
 perform teacher_guard();
 if length(trim(p_title)) not between 2 and 100 or p_cost not between 1 and 1000000 then raise exception 'Tên quà hoặc giá xu không hợp lệ'; end if;
 if p_id is null then insert into rewards(title,cost,active) values(trim(p_title),p_cost,p_active) returning id into rid;
 else update rewards set title=trim(p_title),cost=p_cost,active=p_active where id=p_id returning id into rid;
 end if;
 if rid is null then raise exception 'Không tìm thấy quà'; end if;
 return rid;
end $$;
create or replace function public.teacher_adjust_coins(p_user uuid,p_delta integer,p_reason text) returns integer language plpgsql security definer set search_path=public as $$
declare balance integer;
begin
 perform teacher_guard();
 if p_delta=0 or abs(p_delta)>1000 or length(trim(p_reason)) not between 5 and 120 then raise exception 'Số xu (tối đa 1000/lần) hoặc lý do không hợp lệ'; end if;
 update profiles set coins=coins+p_delta where id=p_user and role='student' and coins+p_delta>=0 returning coins into balance;
 if not found then raise exception 'Không tìm thấy học sinh hoặc số dư không đủ'; end if;
 insert into coin_ledger(user_id,delta,reason) values(p_user,p_delta,'Giáo viên: '||trim(p_reason));
 return balance;
end $$;
-- Existing reward approval function originally restricted teachers to their own class.
create or replace function public.admin_requests() returns jsonb language plpgsql security definer set search_path=public as $$
begin
 perform teacher_guard();
 return coalesce((select jsonb_agg(to_jsonb(t)) from (select r.id,r.status,r.created_at,p.display_name,rw.title,r.cost from redemptions r join profiles p on p.id=r.user_id join rewards rw on rw.id=r.reward_id order by r.created_at desc limit 200)t),'[]'::jsonb);
end $$;
create or replace function public.admin_review(p_id bigint,p_approve boolean) returns void language plpgsql security definer set search_path=public as $$
declare r redemptions%rowtype; bal integer;
begin
 perform teacher_guard();
 select * into r from redemptions where id=p_id for update;
 if not found or r.status<>'pending' then raise exception 'Yêu cầu không tồn tại hoặc đã xử lý'; end if;
 update redemptions set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now() where id=r.id;
 if not p_approve then
  update profiles set coins=coins+r.cost where id=r.user_id returning coins into bal;
  insert into coin_ledger(user_id,delta,reason) values(r.user_id,r.cost,'Hoàn xu do từ chối đổi quà #'||r.id);
 end if;
end $$;
-- Stop archived classes accepting new pupils; teacher identity remains separate from a class.
create or replace function public.join_class(p_name text,p_code text) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare c classes%rowtype; p profiles%rowtype;
begin
 if auth.uid() is null then raise exception 'Cần đăng nhập'; end if;
 if length(trim(p_name)) not between 2 and 32 then raise exception 'Tên cần 2–32 ký tự'; end if;
 select * into p from profiles where id=auth.uid();
 if found then return to_jsonb(p); end if;
 select * into c from classes where not archived and code_hash=crypt(upper(trim(p_code)),code_hash) limit 1;
 if not found then raise exception 'Mã lớp không đúng hoặc lớp đã khóa'; end if;
 insert into profiles(id,display_name,class_id) values(auth.uid(),trim(p_name),c.id) returning * into p;
 return to_jsonb(p);
end $$;
revoke all on function public.teacher_guard(),public.teacher_dashboard(),public.teacher_create_class(text),public.teacher_update_class(uuid,text,boolean),public.teacher_rotate_code(uuid),public.teacher_save_reward(bigint,text,integer,boolean),public.teacher_adjust_coins(uuid,integer,text) from public,anon;
grant execute on function public.teacher_dashboard(),public.teacher_create_class(text),public.teacher_update_class(uuid,text,boolean),public.teacher_rotate_code(uuid),public.teacher_save_reward(bigint,text,integer,boolean),public.teacher_adjust_coins(uuid,integer,text) to authenticated;
-- Guard helper is only called internally by SECURITY DEFINER functions.
