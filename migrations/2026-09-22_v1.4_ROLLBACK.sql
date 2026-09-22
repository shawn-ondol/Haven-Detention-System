-- 비상용: PART 2 이후 문제가 생겨 예전 방식으로 되돌려야 할 때만 실행
-- Emergency only: undoes PART 2 so the old (v1.3) site works again. Data is not touched.
create policy "students rw" on students for all using (true) with check (true);
create policy "detentions rw" on detentions for all using (true) with check (true);
create policy "md_rows rw" on md_rows for all using (true) with check (true);
create policy "terms rw" on terms for all using (true) with check (true);
create policy "archives rw" on archives for all using (true) with check (true);
grant select, insert, update, delete on students, detentions, md_rows, terms, archives to anon;
grant execute on function teacher_signup(text,text,text,text) to anon;
grant execute on function teacher_login(text,text) to anon;
grant execute on function admin_add_teacher(text,text,text,text) to anon;
grant execute on function list_teachers() to anon;
grant execute on function delete_teacher(text) to anon;
grant execute on function admin_update_teacher(text,text,text,text) to anon;
