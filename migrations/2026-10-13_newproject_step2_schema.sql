-- ═══════════════════════════════════════════════════════════
-- 새 Supabase 프로젝트 (lvhyatyjnycyilbzmuwx) — 2단계: Detention 스키마
-- New Supabase project — STEP 2: Detention schema
-- 새 프로젝트의 SQL Editor에 전체 붙여넣고 한 번 실행 · Paste all of this into the NEW project's SQL Editor and run once.
--
-- = supabase_schema.sql + v1.3 + v1.4 part1 + part2 의 최종 상태.
--   예전 teachers 테이블과 옛 로그인 함수(v1.4에서 잠금됨)는 만들지 않음 — 앱이 쓰지 않음.
-- = Final state after supabase_schema.sql + v1.3 + v1.4 part 1/2. The legacy teachers table
--   and old login RPCs (locked since v1.4, unused by the app) are intentionally left out.
-- ═══════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;

-- ── 테이블 · Tables ──
create table students (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  grade text,
  class text,
  created_at timestamptz default now()
);

create table detentions (
  id uuid primary key default gen_random_uuid(),
  student_name text not null,
  grade text,
  class text,
  given_by text,
  recorded_by text,
  issue_date date not null,
  period text,
  reasons text[] default '{}',
  detail text,
  is_auto boolean default false,
  created_at timestamptz default now()
);

create table md_rows (
  id uuid primary key default gen_random_uuid(),
  detention_id uuid not null references detentions(id) on delete cascade,
  md_date date not null,
  status text not null default 'active' check (status in ('active','skipped','excused')),
  attended boolean default false,
  packet_on_time boolean default false,
  packet_after_hours boolean default false,
  supervisor text,
  rescheduled_from uuid,
  created_at timestamptz default now(),
  constraint md_rows_rescheduled_from_fkey
    foreign key (rescheduled_from) references md_rows(id) on delete set null
);

create table terms (
  term_id text primary key,
  start_date date,
  end_date date,
  school_holidays date[] default '{}',
  added_holidays jsonb default '{}',
  removed_holidays date[] default '{}',
  extra_saturdays date[] default '{}',
  updated_at timestamptz default now()
);

create table archives (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  archived_at timestamptz default now(),
  total_count int default 0,
  student_count int default 0,
  detentions_snapshot jsonb,
  md_rows_snapshot jsonb
);

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  login_id text not null,
  first_name text not null default '',
  last_name text not null default '',
  role text not null default 'teacher' check (role in ('admin','teacher')),
  status text not null default 'pending' check (status in ('pending','approved')),
  created_at timestamptz default now()
);
create unique index profiles_login_id_key on profiles (lower(login_id));

alter table students   enable row level security;
alter table detentions enable row level security;
alter table md_rows    enable row level security;
alter table terms      enable row level security;
alter table archives   enable row level security;
alter table profiles   enable row level security;

-- ── 새 계정 → "승인 대기" 프로필 · New account → pending profile ──
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles(id, login_id, first_name, last_name)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'login_id', new.email),
          coalesce(new.raw_user_meta_data->>'first_name', ''),
          coalesce(new.raw_user_meta_data->>'last_name', ''));
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ── 권한 확인 함수 · Permission helpers ──
create or replace function is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'approved');
$$;
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'approved' and role = 'admin');
$$;

-- ── 테이블 권한: 로그인 사용자만, anon은 없음 · Table grants: logged-in only, nothing for anon ──
revoke all on students, detentions, md_rows, terms, archives, profiles from anon;
grant select, insert, update, delete on students, detentions, md_rows, terms, archives to authenticated;
grant select, update on profiles to authenticated;

-- ── RLS 규칙 · Policies ──
create policy "p_students_read"  on students for select to authenticated using (is_approved());
create policy "p_students_admin" on students for all    to authenticated using (is_admin()) with check (is_admin());

create policy "p_terms_read"  on terms for select to authenticated using (is_approved());
create policy "p_terms_admin" on terms for all    to authenticated using (is_admin()) with check (is_admin());

create policy "p_archives_read"  on archives for select to authenticated using (is_approved());
create policy "p_archives_admin" on archives for all    to authenticated using (is_admin()) with check (is_admin());

create policy "p_det_read"   on detentions for select to authenticated using (is_approved());
create policy "p_det_insert" on detentions for insert to authenticated with check (is_approved());
create policy "p_det_update" on detentions for update to authenticated using (is_admin()) with check (is_admin());
create policy "p_det_delete" on detentions for delete to authenticated using (is_admin() or (is_approved() and is_auto));

create policy "p_md_all" on md_rows for all to authenticated using (is_approved()) with check (is_approved());

create policy "p_prof_read"         on profiles for select to authenticated using (id = auth.uid() or is_admin());
create policy "p_prof_admin_update" on profiles for update to authenticated using (is_admin()) with check (is_admin());

-- ── 관리자 기능 · Admin functions ──
create or replace function admin_set_password(p_uid uuid, p_pw text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_admin() then raise exception 'NOT_ADMIN'; end if;
  if length(coalesce(p_pw,'')) < 6 then raise exception 'PW_TOO_SHORT'; end if;
  update auth.users set encrypted_password = crypt(p_pw, gen_salt('bf')), updated_at = now() where id = p_uid;
end; $$;

create or replace function admin_delete_user(p_uid uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'NOT_ADMIN'; end if;
  if exists (select 1 from profiles where id = p_uid and role = 'admin') then raise exception 'CANNOT_DELETE_ADMIN'; end if;
  delete from auth.users where id = p_uid;
end; $$;

revoke execute on function admin_set_password(uuid, text) from public, anon;
revoke execute on function admin_delete_user(uuid)        from public, anon;
revoke execute on function is_approved()                  from public, anon;
revoke execute on function is_admin()                     from public, anon;
revoke execute on function handle_new_user()              from public, anon, authenticated;
grant execute on function admin_set_password(uuid, text) to authenticated;
grant execute on function admin_delete_user(uuid)        to authenticated;
grant execute on function is_approved()                  to authenticated;
grant execute on function is_admin()                     to authenticated;

-- 확인 · Check: 6 tables, 13 policies, trigger present
select 'tables'   as what, count(*)::text as n from pg_tables   where schemaname = 'public'
union all select 'policies', count(*)::text from pg_policies where schemaname = 'public'
union all select 'trigger',  tgname        from pg_trigger  where tgname = 'on_auth_user_created';
