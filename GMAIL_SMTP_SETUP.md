# Gmail SMTP 설정

Everytime Match는 신규 사용자의 학교 이메일 인증메일을 **Gmail SMTP → Supabase Auth** 경로로 보냅니다.

사용자 흐름:

`학교 이메일 가입 → Gmail SMTP로 인증메일 발송 → 8자리 OTP 입력 → 인증 완료`

학생은 Gmail 계정을 사용할 필요가 없습니다. Gmail은 인증메일을 보내는 발신 서버 역할만 합니다.

## 1. 발신용 Gmail 준비

발신에 사용할 Google 계정에서 **2단계 인증**을 켭니다.

그 다음 Google 계정의 **앱 비밀번호**를 생성합니다.

앱 이름 예시:

`Everytime Match SMTP`

발급되는 16자리 앱 비밀번호는 Supabase SMTP Settings에만 입력합니다.

절대 다음 위치에 저장하지 않습니다.

- GitHub
- index.html
- JavaScript
- SQL migration
- README
- 채팅/메신저

## 2. Supabase Custom SMTP

Supabase Dashboard에서:

`Authentication → Emails → SMTP Settings`

Custom SMTP를 활성화하고 입력합니다.

- Sender email: 발신용 Gmail 주소
- Sender name: Everytime Match
- Host: `smtp.gmail.com`
- Port: `465`
- Username: 발신용 Gmail 전체 주소
- Password: Google 앱 비밀번호

465 연결이 환경상 문제를 일으키면 `587`도 사용할 수 있습니다.

## 3. Email Provider

`Authentication → Sign In / Providers → Email`

에서 이메일 확인이 켜져 있어야 합니다.

Everytime Match는 확인이 끝난 학교 이메일만 정상 사용자로 인정합니다.

## 4. 8자리 OTP 템플릿

`Authentication → Email Templates → Confirm sign up`

에서 [SUPABASE_EMAIL_TEMPLATE.md](./SUPABASE_EMAIL_TEMPLATE.md)의 템플릿을 사용합니다.

메일 본문에는 반드시:

`{{ .Token }}`

이 포함되어야 합니다.

프론트엔드는 이 코드를 `verifyOtp({ email, token, type: "email" })`로 확인합니다.

## 5. 학교 이메일 테스트

신규 테스트 주소로 아래 순서대로 확인합니다.

1. Everytime Match에서 학교 이메일로 새 계정 만들기
2. Supabase Users에 계정이 생성되는지 확인
3. 학교 이메일 받은편지함 확인
4. 안 보이면 스팸/정크메일함 확인
5. 메일의 8자리 코드 입력
6. `상명대 인증` 상태로 바뀌는지 확인
7. 프로필 작성 화면으로 이동하는지 확인

## 6. 발송 제한

Gmail SMTP는 초기 소규모 베타용으로 사용합니다.

사용자가 많아지면 전용 transactional email 서비스와 자체 발신 도메인으로 이전하는 것이 좋습니다.

Supabase Auth 자체의 이메일/OTP rate limit도 있으므로 공개 배포 전 Rate Limits 설정을 확인합니다.
