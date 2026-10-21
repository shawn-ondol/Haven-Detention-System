# Detention System → 별도 Supabase 프로젝트 이전 기록

## 배경 (2026-10-13)

- Haven 홈페이지(haven-web)와 Detention System이 Supabase 프로젝트
  `nojzejrynscsujeodoha` 하나를 같이 쓰고 있음.
  - Haven: `haven` 스키마, Storage 버킷 13개(전부 Haven 것), 계정 4개
  - Detention: `public` 스키마(teachers, students, detentions, md_rows, terms,
    archives, profiles), 계정 18개(`login_id@haven.or.kr` 형식), Storage 없음
- 로그인 계정 목록(auth.users)이 공유돼서 생기는 문제:
  - Detention의 `on_auth_user_created` 트리거가 Haven 트리거를 덮어써 Haven
    가입 오류 발생 (Haven ver 3.14.0에서 수습)
  - Haven 트리거는 모든 새 계정에 Haven 프로필을 만듦 → Detention 새 가입자가
    Haven 지원자로 섞일 위험
  - 이메일 하나 = 두 사이트 공통 계정 하나, 비밀번호 재설정도 공유
- 결정: Detention을 새 Supabase 프로젝트로 옮긴다 (Haven은 그대로).
  Detention은 `index.html` 하나에 URL·anon key가 박혀 있어 옮기기 쉬움.

## 단계

| # | 단계 | 담당 | 상태 |
|---|---|---|---|
| 0 | 백업 | Claude / 사용자 | ✅ 완료 (Detention 테이블은 SQL Editor CSV로) |
| 1 | 새 Supabase 프로젝트 생성 (기존과 같은 Region, 무료 플랜 2개 제한 확인, DB 비밀번호 보관) | 사용자 | ✅ 2026-10-13 — `lvhyatyjnycyilbzmuwx` |
| 2 | 새 프로젝트에 Detention 스키마 구성 (`supabase_schema.sql` + `migrations/`, 실제 운영 DB와 비교) | Claude가 SQL 준비 → 사용자가 SQL Editor에서 실행 | ✅ 2026-10-13 — `migrations/2026-10-13_newproject_step2_schema.sql` |
| 3 | 데이터 이전: 테이블 6+1개, 계정 18개 (기존 비밀번호 해시·ID 그대로 → 교사들은 차이 못 느낌) | Claude가 SQL 준비 → 사용자 실행 | ✅ 2026-10-13 — 백업 폴더 `detention_step3_data.sql` (비밀번호 해시 포함 — 배포 폴더에 두지 말 것) |
| 4 | `index.html`의 SUPABASE_URL / ANON_KEY 교체 + `vercel.json` CSP connect-src 교체 → Vercel 재배포 | Claude 수정, 사용자 배포 | ✅ 2026-10-13 — 커밋 3b2920c |
| 5 | 검증: 교사 로그인·데이터 확인 | 사용자 | ⬜ |
| 6 | (안정화 후) 기존 프로젝트에서 Detention 테이블·함수·트리거·계정 18개 정리 | Claude가 SQL 준비 → 사용자 실행 | ✅ 2026-10-21 — `migrations/2026-10-21_oldproject_step6_cleanup.sql` |

**2026-10-21: 이전 완료.** 기존 프로젝트에는 이제 Detention 흔적이 없음 (Haven 전용).
아래 "되돌리기"는 6단계 이후로는 쓸 수 없음 — 옛 프로젝트에 테이블·계정이 없음.

(기록용) 6단계 전까지는 기존 프로젝트가 그대로였으므로, 문제가 생기면 `index.html` 두 줄만
되돌리면 원상복구됨.

## 0. 백업 현황

위치: `E:\홈페이지\backups\supabase-nojzejrynscsujeodoha-2026-10-13\` (약 460MB,
`SUMMARY.txt` 참고)

- ✅ Haven 전체 테이블 데이터 (`db/haven/*.json`)
- ✅ Storage 13개 버킷 파일 전부 (508개)
- ✅ 계정 22개 목록 (비밀번호 해시 제외)
- ❌ Detention 테이블 (`public.*`) — v1.4 lockdown으로 service_role도 읽기
  권한이 없어 API로 백업 불가. **1단계 전에** SQL Editor에서 백업해야 함.
- ❌ 스키마·함수·RLS·트리거·비밀번호 해시 — 전체 백업(pg_dump)은 DB 비밀번호
  필요 (Project Settings → Database). 또는 Pro 플랜이면 Database → Backups.

## 진행 기록

### 2026-10-13
- 0단계 완료: SQL Editor에서 Detention 테이블 + 계정 정보를 CSV로 내보냄 →
  백업 폴더 `detention_public.csv` (비밀번호 해시 포함)
  - teachers 17 (옛 방식, v1.4부터 안 씀), students 166, detentions 153,
    md_rows 231, terms 2, archives 0, profiles 19, 계정 19
  - 19번째 계정 `heewon.kye@haven.or.kr` = 오늘 가입한 **Haven 지원자 학부모**.
    Detention 트리거 때문에 Detention 'pending' 프로필이 잘못 생긴 것 → 이전 대상에서 제외
    (6단계 정리 때 기존 프로젝트의 이 사람 Detention 프로필만 지우고 계정은 Haven에 남겨야 함)
- 1단계 완료: 새 프로젝트 `https://lvhyatyjnycyilbzmuwx.supabase.co` (anon key는 4단계에서 index.html에 넣음)
- 2·3단계 SQL 준비:
  - 옛 `teachers` 테이블과 옛 로그인 함수 6개는 새 프로젝트에 만들지 않음 (앱이 안 씀, 데이터는 백업에 있음)
  - 새 프로젝트 Auth 설정: **Confirm email 끄기** 필요 (가입 이메일이 가짜 `hmd-…@haven.or.kr`이라)

- 2·3단계 실행 완료 (사용자, SQL Editor) — 확인 결과 정상
- 배포 직전 검증: 기존/새 프로젝트에서 테이블별 md5 해시 비교 → 5개 전부 동일
  (백업 이후 기존 DB에 새로 기록된 것 없음)
- 4단계: `index.html` SUPABASE_URL/ANON_KEY, `vercel.json` CSP connect-src를 새 프로젝트로 교체

### 되돌리기 (4단계 이후 문제 생기면)
`index.html`과 `vercel.json`의 값을 아래로 되돌리고 push:
- URL: `https://nojzejrynscsujeodoha.supabase.co`
- anon key: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5vanplanJ5bnNjc3VqZW9kb2hhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM4ODg5OTEsImV4cCI6MjA5OTQ2NDk5MX0.UrSn8OZMOgz-Km-rwdLmrnvPZm0Me0owB9nHJubp_Yw`
- 단, 새 프로젝트에 기록된 데이터는 기존 프로젝트로 옮겨야 함

## 다음에 할 일

1. ✅ push 완료 (3b2920c) → Vercel 배포 성공, 라이브 사이트가 새 프로젝트 사용 확인 (2026-10-13)
2. 5단계 검증: Admin + 교사 1명 로그인, 디텐션 목록·MD 날짜 확인, 테스트 기록 1건
3. (며칠 안정화 후) 6단계: 기존 프로젝트 정리 SQL — heewon.kye 계정은 지우지 말고 Detention 프로필만 삭제
   - 2026-10-21 SQL 준비: `migrations/2026-10-21_oldproject_step6_cleanup.sql` (옛 프로젝트에서 실행).
     한 트랜잭션 + 안전장치(행 수 166/153/231, hmd- 계정 18개, Haven 프로필 없음, 트리거가
     public.handle_new_user일 때만 삭제). haven-web은 public 스키마를 쓰지 않음을 확인함.
   - ✅ 2026-10-21 사용자 실행 완료 — 미리보기·확인 결과 모두 예상대로 (public 테이블/함수 0,
     hmd- 계정 0, auth.users 트리거는 haven_on_auth_user_created 하나만 남음)
