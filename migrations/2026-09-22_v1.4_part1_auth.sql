-- ═══════════════════════════════════════════════════════════
-- v1.4 PART 1 — Supabase 로그인 도입 (추가만 함, 기존 사이트는 계속 동작)
-- v1.4 PART 1 — Adds Supabase login. Additive only: the current live site keeps working.
-- Supabase SQL Editor에 전체 붙여넣고 한 번 실행 · Paste all of this and run once.
-- ═══════════════════════════════════════════════════════════

-- ── 1. 교사 프로필 (Supabase 계정과 1:1) · Teacher profiles, one per Supabase account ──
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  login_id text not null,
  first_name text not null default '',
  last_name text not null default '',
  role text not null default 'teacher' check (role in ('admin','teacher')),
  status text not null default 'pending' check (status in ('pending','approved')),
  created_at timestamptz default now()
);
create unique index if not exists profiles_login_id_key on profiles (lower(login_id));
alter table profiles enable row level security;

-- 새 계정 → 자동으로 "승인 대기" 프로필 생성 · New account → pending profile (role/status never come from the user)
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
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ── 2. 권한 확인 함수 · Permission helpers ──
create or replace function is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'approved');
$$;
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and status = 'approved' and role = 'admin');
$$;

-- ── 3. 로그인한 사용자용 규칙 (PART 2 전까지는 기존 공개 규칙도 함께 유효)
--       Rules for logged-in users (the old open rules stay active until PART 2) ──
grant select, insert, update, delete on students, detentions, md_rows, terms, archives to authenticated;
grant select, update on profiles to authenticated;

drop policy if exists "p_students_read" on students;
drop policy if exists "p_students_admin" on students;
create policy "p_students_read"  on students for select to authenticated using (is_approved());
create policy "p_students_admin" on students for all    to authenticated using (is_admin()) with check (is_admin());

drop policy if exists "p_terms_read" on terms;
drop policy if exists "p_terms_admin" on terms;
create policy "p_terms_read"  on terms for select to authenticated using (is_approved());
create policy "p_terms_admin" on terms for all    to authenticated using (is_admin()) with check (is_admin());

drop policy if exists "p_archives_read" on archives;
drop policy if exists "p_archives_admin" on archives;
create policy "p_archives_read"  on archives for select to authenticated using (is_approved());
create policy "p_archives_admin" on archives for all    to authenticated using (is_admin()) with check (is_admin());

-- 교사: 발급/조회 가능, 수정은 관리자만, 삭제는 관리자 또는 자동발급(Skip 되돌리기)만
-- Teachers: issue + view; edit = admin; delete = admin, or auto-issued records (Undo skip)
drop policy if exists "p_det_read" on detentions;
drop policy if exists "p_det_insert" on detentions;
drop policy if exists "p_det_update" on detentions;
drop policy if exists "p_det_delete" on detentions;
create policy "p_det_read"   on detentions for select to authenticated using (is_approved());
create policy "p_det_insert" on detentions for insert to authenticated with check (is_approved());
create policy "p_det_update" on detentions for update to authenticated using (is_admin()) with check (is_admin());
create policy "p_det_delete" on detentions for delete to authenticated using (is_admin() or (is_approved() and is_auto));

-- MD 출석/스킵/인정/되돌리기는 교사도 사용 · Attendance / skip / excuse / undo are used by teachers too
drop policy if exists "p_md_all" on md_rows;
create policy "p_md_all" on md_rows for all to authenticated using (is_approved()) with check (is_approved());

-- 프로필: 본인 것만 보기, 관리자는 전체 보기/수정 (본인이 스스로 승인·권한 변경 불가)
-- Profiles: see your own; admin sees/edits all (nobody can approve or promote themselves)
drop policy if exists "p_prof_read" on profiles;
drop policy if exists "p_prof_admin_update" on profiles;
create policy "p_prof_read"         on profiles for select to authenticated using (id = auth.uid() or is_admin());
create policy "p_prof_admin_update" on profiles for update to authenticated using (is_admin()) with check (is_admin());

-- ── 4. 관리자 기능 · Admin functions ──
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
revoke execute on function admin_delete_user(uuid) from public, anon;
revoke execute on function is_approved() from public, anon;
revoke execute on function is_admin() from public, anon;
grant execute on function admin_set_password(uuid, text) to authenticated;
grant execute on function admin_delete_user(uuid) to authenticated;
grant execute on function is_approved() to authenticated;
grant execute on function is_admin() to authenticated;

-- ── 5. 기존 교사 계정 이전 (비밀번호 그대로 유지, 자동 승인)
--       Move existing teacher accounts over — same passwords, already approved ──
do $$
declare t record; uid uuid; em text;
begin
  for t in select * from teachers loop
    em := 'hmd-' || encode(convert_to(lower(t.id), 'UTF8'), 'hex') || '@haven.or.kr';
    continue when exists (select 1 from auth.users where email = em);
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change_token_new, email_change)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em, t.password_hash, now(),
            '{"provider":"email","providers":["email"]}',
            jsonb_build_object('login_id', t.id, 'first_name', t.first_name, 'last_name', t.last_name),
            now(), now(), '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text,
            jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true),
            'email', now(), now(), now());
    update profiles set status = 'approved', role = t.role where id = uid;
  end loop;
end $$;

-- 확인 · Check: one row per existing teacher, all "approved", Admin with role "admin"
select login_id, role, status from profiles order by role, login_id;
