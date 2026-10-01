# Microsoft 학교계정 인증 설정 — 사용 중단

이 방식은 상명대 Entra 테넌트의 앱 등록/외부 앱 동의 정책에 의존해 초기 베타에 적합하지 않아 사용하지 않습니다.

현재 Everytime Match의 신규 사용자 인증 방식은:

`학교 이메일 가입 → Gmail SMTP 인증메일 수신 → 8자리 OTP 입력 → 인증 완료`

입니다.

현재 설정 문서:

- [GMAIL_SMTP_SETUP.md](./GMAIL_SMTP_SETUP.md)
- [SUPABASE_EMAIL_TEMPLATE.md](./SUPABASE_EMAIL_TEMPLATE.md)

과거 Microsoft migration을 이미 DB에 실행했다면:

`supabase/migrations/20261001_restore_email_otp_verification.sql`

을 SQL Editor에서 한 번 실행해 이메일 인증 방식으로 복구합니다.
