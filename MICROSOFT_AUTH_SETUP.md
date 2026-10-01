# Microsoft 상명대 계정 인증 설정

Everytime Match는 신규 사용자 학교 인증을 **Microsoft (Azure) OAuth** 방식으로 처리합니다.

사용자 흐름:

`Microsoft로 상명대 인증 → Microsoft 로그인 → Everytime Match 복귀 → @sangmyung.kr + Azure identity 서버 검증 → 인증 완료`

사용자의 Microsoft 비밀번호는 Everytime Match에 전달되거나 저장되지 않습니다.

## 1. Microsoft Entra에서 앱 등록

Microsoft Entra 관리 화면에서 App registration을 하나 만듭니다.

권장 이름:

`Everytime Match`

Redirect URI 유형:

`Web`

Redirect URI:

```
https://mrbuxqaeqvuevplpssgi.supabase.co/auth/v1/callback
```

Supported account types는 실제 상명대 테넌트에서 앱 등록이 가능하다면 해당 조직 전용(single tenant)이 가장 강합니다.

학교 정책 때문에 상명대 테넌트에서 앱 등록이 불가능한 경우에는 multi-tenant 앱을 사용하고,
Everytime Match DB에서 `@sangmyung.kr` + Azure identity를 다시 검사하는 현재 구조를 사용할 수 있습니다.

## 2. Client ID / Client Secret

등록한 앱 Overview에서 Application (client) ID를 확인합니다.

Certificates & secrets에서:

- New client secret 생성
- **Secret ID가 아니라 Value 값** 복사

Secret 값은 GitHub나 프론트엔드 코드에 넣지 않습니다.

## 3. Supabase에서 Azure Provider 활성화

Supabase Dashboard:

`Authentication → Providers → Azure (Microsoft)`

다음 값 입력:

- Enable Azure
- Client ID
- Client Secret

학교 Microsoft tenant ID를 알고 있고 single-tenant 구성을 사용한다면 Tenant URL:

```
https://login.microsoftonline.com/<tenant-id>
```

그렇지 않으면 기본 common tenant로 먼저 테스트할 수 있습니다.

## 4. Everytime Match Redirect URL

Supabase Dashboard:

`Authentication → URL Configuration`

Site URL:

```
https://everytimematch-production.up.railway.app/
```

Redirect URLs에도 같은 주소를 허용합니다.

프론트엔드는 Azure provider와 `email` scope를 요청하고, 로그인 뒤 Railway 주소로 돌아옵니다.

## 5. DB migration 실행

SQL Editor에서 실행:

```
supabase/migrations/20261001_microsoft_school_oauth.sql
```

이 migration은 신규 학교 인증을 다음 조건으로 바꿉니다.

- Supabase Auth identity provider가 `azure`
- Auth 이메일이 정확히 `@sangmyung.kr`
- Azure identity 이메일도 `@sangmyung.kr`

기존 베타 테스트 계정은 `beta_testers` allowlist 때문에 계속 로그인할 수 있습니다.

## 6. Microsoft email claim 보안

공개 베타 전에는 Microsoft Entra 앱에서 `email`과 `xms_edov` optional claim 설정을 검토합니다.

## 7. 실제 테스트

1. 로그아웃
2. `Microsoft로 상명대 인증` 클릭
3. `학번@sangmyung.kr` 선택
4. Microsoft 로그인 완료
5. Railway 앱으로 자동 복귀
6. `✓ 상명대 Microsoft 계정 인증이 완료되었습니다.` 확인
7. 프로필 작성
8. 후보 카드에서 `✓ 상명대 인증` 배지 확인

개인 Outlook 계정 또는 다른 조직 계정으로 로그인한 경우 Auth 로그인 자체는 성공할 수 있지만 Everytime Match DB 검증에서 이용을 차단합니다.

## 8. 중요한 제한

Microsoft Entra의 **App registrations 기능 자체가 학교 정책으로 막혀 있을 수 있습니다.**

이 경우 학교 관리자 승인/등록 없이는 Azure OAuth 앱을 만들 수 있으므로, 코드만으로 우회하지 않고 다른 학교 인증 방식으로 돌아가야 합니다.
