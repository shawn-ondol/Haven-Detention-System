-- ═══════════════════════════════════════════════════════════
-- 기존 프로젝트 (nojzejrynscsujeodoha, Haven과 공유) — 6단계: Detention 정리
-- OLD shared project — STEP 6: remove Detention leftovers.
-- ⚠️ 기존(옛) 프로젝트 SQL Editor에서 실행 · Run in the OLD project, NOT lvhyatyjnycyilbzmuwx.
--
-- 지우는 것 · Removes:
--   public 테이블 7개 (teachers, students, detentions, md_rows, terms, archives, profiles)와 RLS 규칙
--   Detention 함수 11개, 트리거 on_auth_user_created (public.handle_new_user를 가리킬 때만)
--   Detention 계정 18개 (hmd-…@haven.or.kr)
-- 남기는 것 · Keeps:
--   haven 스키마 전체, haven_on_auth_user_created 트리거, Haven 계정 (heewon.kye 포함 —
--   잘못 생긴 Detention 프로필은 public.profiles와 함께 사라짐), pgcrypto 확장
--
-- 데이터는 새 프로젝트와 백업(E:\홈페이지\backups\supabase-nojzejrynscsujeodoha-2026-10-13)에 있음.
-- 아래 안전장치 중 하나라도 어긋나면 오류를 내고 아무것도 지우지 않음 (전체가 한 트랜잭션).
-- Any failed guard raises and rolls back everything.
-- ═══════════════════════════════════════════════════════════

-- ── 1) 미리보기 (읽기만 함) · Preview, read-only — 먼저 이 부분만 실행해서 확인해도 됨 ──
select 'detention accounts' as what, count(*)::text as n from auth.users where email like 'hmd-%@haven.or.kr'
union all select 'students',   count(*)::text from public.students
union all select 'detentions', count(*)::text from public.detentions
union all select 'md_rows',    count(*)::text from public.md_rows
union all select 'hmd accounts with a Haven profile', count(*)::text
  from auth.users u join haven.profiles p on p.id = u.id where u.email like 'hmd-%@haven.or.kr'
union all select 'trigger ' || tgname, tgfoid::regproc::text
  from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal;
-- 예상 · Expected: 18 / 166 / 153 / 231 / 0,
--   trigger haven_on_auth_user_created -> haven.handle_new_user,
--   trigger on_auth_user_created -> handle_new_user (public 것)

-- ── 2) 정리 · Cleanup ──
begin;

do $$
begin
  -- 10/13 이후 옛 DB에 새 기록이 생겼다면 멈춤 (새 프로젝트로 옮겨야 할 데이터)
  -- Stop if anything was written to the old DB after the 10/13 cutover.
  if (select count(*) from public.students)   <> 166
  or (select count(*) from public.detentions) <> 153
  or (select count(*) from public.md_rows)    <> 231 then
    raise exception 'STOP: 옛 DB의 Detention 데이터 개수가 백업과 다름 · row counts changed since the backup';
  end if;
  if (select count(*) from auth.users where email like 'hmd-%@haven.or.kr') <> 18 then
    raise exception 'STOP: Detention 계정 수가 18개가 아님 · expected 18 hmd- accounts';
  end if;
  if exists (select 1 from auth.users u join haven.profiles p on p.id = u.id
             where u.email like 'hmd-%@haven.or.kr') then
    raise exception 'STOP: Haven 프로필이 있는 hmd- 계정이 있음 · an hmd- account has a Haven profile';
  end if;
end $$;

-- 트리거: Detention 것일 때만 삭제 · Drop the trigger only if it is still Detention's
do $$
begin
  if exists (select 1 from pg_trigger
             where tgrelid = 'auth.users'::regclass and tgname = 'on_auth_user_created'
               and tgfoid = 'public.handle_new_user'::regproc) then
    drop trigger on_auth_user_created on auth.users;
  end if;
end $$;

-- 계정 18개 (identities·sessions는 자동으로 같이 삭제) · 18 accounts; identities/sessions cascade
delete from auth.users where email like 'hmd-%@haven.or.kr';

-- 테이블 (RLS 규칙도 같이 삭제됨) · Tables, with their policies
drop table if exists public.md_rows, public.detentions, public.students, public.terms,
                     public.archives, public.profiles, public.teachers;

-- 함수 · Functions
drop function if exists public.handle_new_user();
drop function if exists public.is_approved();
drop function if exists public.is_admin();
drop function if exists public.admin_set_password(uuid, text);
drop function if exists public.admin_delete_user(uuid);
drop function if exists public.teacher_signup(text, text, text, text);
drop function if exists public.teacher_login(text, text);
drop function if exists public.admin_add_teacher(text, text, text, text);
drop function if exists public.list_teachers();
drop function if exists public.delete_teacher(text);
drop function if exists public.admin_update_teacher(text, text, text, text);

commit;

-- ── 3) 확인 · Check ──
-- 예상 · Expected: public tables 0, public functions 0, hmd accounts 0,
--   accounts left = Haven 계정 수 (백업 시점 4개 + 그 뒤 가입자),
--   trigger 줄은 haven_on_auth_user_created -> haven.handle_new_user 하나만
select 'public tables' as what, count(*)::text as n from pg_tables where schemaname = 'public'
union all select 'public functions', count(*)::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('handle_new_user','is_approved','is_admin','admin_set_password',
    'admin_delete_user','teacher_signup','teacher_login','admin_add_teacher','list_teachers','delete_teacher','admin_update_teacher')
union all select 'hmd accounts', count(*)::text from auth.users where email like 'hmd-%@haven.or.kr'
union all select 'accounts left', count(*)::text from auth.users
union all select 'haven profiles', count(*)::text from haven.profiles
union all select 'trigger ' || tgname, tgfoid::regproc::text
  from pg_trigger where tgrelid = 'auth.users'::regclass and not tgisinternal;
