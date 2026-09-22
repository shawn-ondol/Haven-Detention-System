-- v1.3 — Supabase SQL Editor에 전체 붙여넣고 한 번 실행하세요 · Paste all of this into the Supabase SQL Editor and run once

-- 1) 관리자: 교사 이름 수정 / 비밀번호 재설정 · Admin: rename teacher / reset password
--    p_pw가 null이면 비밀번호는 그대로 유지 · null password = keep current one
create or replace function admin_update_teacher(p_id text, p_first text, p_last text, p_pw text)
returns void
language plpgsql security definer as $$
begin
  update teachers
     set first_name = p_first,
         last_name = p_last,
         password_hash = case when p_pw is null or p_pw = '' then password_hash
                              else crypt(p_pw, gen_salt('bf')) end
   where id = p_id and role <> 'admin';
end; $$;

grant execute on function admin_update_teacher(text,text,text,text) to anon;

-- 2) 스킵된 MD가 있는 원래 기록을 삭제할 때 오류 나던 문제 수정
--    Deleting a detention whose MD was skipped failed, because the auto-issued
--    MD row still pointed at the skipped row. Now that link is cleared instead.
alter table md_rows drop constraint if exists md_rows_rescheduled_from_fkey;
alter table md_rows add constraint md_rows_rescheduled_from_fkey
  foreign key (rescheduled_from) references md_rows(id) on delete set null;

-- 확인용 · Check: both rows below should come back
select 'function ok' as check, proname from pg_proc where proname = 'admin_update_teacher'
union all
select 'fk ok', confdeltype::text from pg_constraint where conname = 'md_rows_rescheduled_from_fkey';
