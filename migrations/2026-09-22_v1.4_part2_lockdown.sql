-- ═══════════════════════════════════════════════════════════
-- v1.4 PART 2 — 잠금: 로그인하지 않은 접근 차단
-- v1.4 PART 2 — Lockdown: block all access without a login.
-- ⚠️ 새 버전이 배포되고 로그인 테스트가 끝난 뒤에만 실행하세요.
-- ⚠️ Run ONLY after the new version is deployed and login has been tested.
--    (이 파일을 실행하면 예전 버전 사이트는 더 이상 동작하지 않습니다 · The old site stops working after this.)
-- ═══════════════════════════════════════════════════════════

-- PART 1 이후 예전 사이트에서 가입한 교사가 있으면 함께 이전 · Carry over anyone who signed up on the old site after PART 1
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

-- 예전 "누구나 읽기/쓰기" 규칙 제거 · Remove the old "anyone can read/write" rules
drop policy if exists "students rw" on students;
drop policy if exists "detentions rw" on detentions;
drop policy if exists "md_rows rw" on md_rows;
drop policy if exists "terms rw" on terms;
drop policy if exists "archives rw" on archives;
revoke all on students, detentions, md_rows, terms, archives from anon;

-- 예전 로그인/교사관리 함수 차단 (삭제하지 않고 보관) · Lock the old login/teacher functions (kept, not deleted)
revoke execute on function teacher_signup(text,text,text,text) from public, anon, authenticated;
revoke execute on function teacher_login(text,text) from public, anon, authenticated;
revoke execute on function admin_add_teacher(text,text,text,text) from public, anon, authenticated;
revoke execute on function list_teachers() from public, anon, authenticated;
revoke execute on function delete_teacher(text) from public, anon, authenticated;
revoke execute on function admin_update_teacher(text,text,text,text) from public, anon, authenticated;

-- 확인 · Check: should list ONLY the new p_... rules, nothing named "... rw"
select tablename, policyname from pg_policies where schemaname = 'public' order by tablename, policyname;
