# Supabase 연결 및 업데이트 순서

## 새 프로젝트

Supabase 프로젝트 생성 후 SQL Editor에서 아래 순서대로 실행합니다.

1. `supabase/schema.sql`
2. `supabase/migrations/20261001_discovery_limits.sql`
3. `supabase/migrations/20261001_matches_chat_reports.sql`
4. `supabase/migrations/20261001_beta_readiness_school_verification.sql`

각 파일을 전체 복사해서 **Run** 하면 됩니다.

정상 실행 시 보통:

`Success. No rows returned`

가 표시됩니다.

## 4번째 migration 역할

`20261001_beta_readiness_school_verification.sql`

- 상명대 이메일 도메인 allowlist
- 이메일 확인 완료 여부 검사
- 학교 인증 안 된 신규 계정의 프로필/매칭/채팅 차단
- 기존 Auth 계정을 beta tester로 자동 보존
- 후보 및 매칭 목록에 인증 상태 제공
- 차단 목록 조회
- 차단 해제
- 본인 회원 탈퇴
- 주요 DB 함수에도 학교 인증 조건 적용

## 허용 도메인

현재 설정:
- sangmyung.kr
- smu.ac.kr
- sangmyung.ac.kr

학교 인증은 이메일 주소 자체를 프로필에 저장하지 않고 Auth 정보에서 확인합니다.

## Authentication 설정

Authentication → URL Configuration:

- Site URL: Railway 실제 주소
- Redirect URLs: Railway 실제 주소

예:
`https://everytimematch-production.up.railway.app/`

Authentication → Providers → Email에서 이메일 확인 기능이 켜져 있어야 학교 인증 흐름이 정상적으로 작동합니다.

## 기존 테스트 계정

4번째 migration을 실행하는 시점에 이미 존재하는 Auth 계정은 자동으로 `beta_testers`에 등록됩니다.

따라서 기존 지인 테스트 계정은 일반 이메일이어도 계속 테스트할 수 있습니다.
새로 만드는 계정부터는 학교 이메일 인증이 필요합니다.

## schema cache 오류

새 RPC를 만든 직후:

`Could not find the function ... in the schema cache`

오류가 뜨면 SQL Editor에서 실행:

```sql
NOTIFY pgrst, 'reload schema';
```

## 보안

브라우저에 넣어도 되는 값:
- Project URL
- Publishable key

브라우저에 넣으면 안 되는 값:
- Secret key
- service_role key
- Database password
- Database connection URI

DB 업데이트 후 `TEST_CHECKLIST.md` 순서대로 테스트합니다.
