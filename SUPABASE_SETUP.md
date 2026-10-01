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


## 가입 인증코드

Everytime Match는 가입 인증메일의 8자리 OTP를 웹 화면에서 직접 입력하는 방식을 사용합니다.

Supabase Dashboard에서:

**Authentication → Email Templates → Confirm sign up**

으로 이동한 뒤 이메일 본문에 `{{ .Token }}`을 포함해야 합니다.

권장 Subject/HTML은 [SUPABASE_EMAIL_TEMPLATE.md](./SUPABASE_EMAIL_TEMPLATE.md)에 정리되어 있습니다.

메일이 받은편지함에 보이지 않을 수 있으므로 UI에는 **스팸메일함 / 정크메일함 확인 안내**를 표시합니다.


## Gmail SMTP 연결

공개 베타에서는 Supabase 기본 SMTP 대신 Gmail SMTP를 사용합니다.

Authentication → Emails → SMTP Settings에서 Custom SMTP를 활성화하고 다음 값을 사용합니다.

- Sender email: 발신용 Gmail 주소
- Sender name: Everytime Match
- Host: `smtp.gmail.com`
- Port: `465` 또는 `587`
- Username: 발신용 Gmail 전체 주소
- Password: Google 계정에서 발급한 16자리 앱 비밀번호

Google 계정은 2단계 인증이 켜져 있어야 앱 비밀번호를 만들 수 있습니다.

앱 비밀번호는 저장소나 브라우저 코드에 넣지 않고 Supabase SMTP Settings에만 입력합니다.

상세 순서는 [GMAIL_SMTP_SETUP.md](./GMAIL_SMTP_SETUP.md)를 참고하세요.

## Microsoft OAuth migration을 이미 실행한 경우

이전에 Microsoft 학교계정 인증 migration을 실행했다면 SQL Editor에서 다음 파일을 한 번 실행해 이메일 인증 방식으로 복구합니다.

`supabase/migrations/20261001_restore_email_otp_verification.sql`

Microsoft migration을 실행하지 않았다면 이 복구 migration은 필수는 아닙니다.
