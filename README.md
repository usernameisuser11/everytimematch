# Everytime Match

상명대 구성원을 대상으로 아이디어를 검증 중인 **간단한 캠퍼스 매칭 웹서비스 프로토타입**입니다.

## 핵심 흐름

`상명대 이메일 인증 → 최소 프로필 → 후보 보기 → 관심/넘기기 → 상호 관심 자동 매칭 → 내부 채팅`

운영자가 직접 사용자를 수동으로 매칭하지 않습니다.

## 현재 구현 방향

- Microsoft 학교계정 인증
  - 사용자는 `학번@sangmyung.kr` Microsoft 계정으로 로그인
  - 로그인 후 DB에서 Azure identity + @sangmyung.kr을 다시 검증
  - SMTP / 이메일 OTP 불필요
- 기존 테스트 계정은 beta tester로 자동 보존
- 찾는 상대: 남성 / 여성 / 상관없음
- 찾는 관계: 친구 / 소개팅 / 둘 다
- 하루 프로필 10명
- 하루 관심 5개
- 같은 날 이미 본 사람 재노출 방지
- 상호 관심 시 자동 매칭
- 매칭 목록 유지
- 매칭된 사용자끼리 내부 텍스트 채팅
- 외부 Instagram / 카카오 ID 수집 제거
- 신고 시 즉시 차단
- 채팅 메시지 단위 신고 가능
- 매칭 해제 / 차단 / 차단 해제
- 회원 탈퇴
- Supabase RLS 적용

## 개인정보 방향

- 외부 연락처 수집 안 함
- 이메일/인증정보는 Supabase Auth에 분리
- 상대에게 이메일 원문은 공개하지 않고 인증 배지만 표시
- 일반 관리자 화면에서는 최소 프로필/운영 정보만 표시하는 방향
- 채팅은 매칭된 당사자만 접근 가능하도록 RLS 적용
- 서비스 운영에 필요하지 않은 개인정보는 처음부터 수집하지 않음

> 일반적인 RLS만으로는 데이터베이스 최고 권한 운영자까지 채팅 원문 접근을 기술적으로 막을 수 없습니다.
> 운영자도 기술적으로 채팅 내용을 읽을 수 없게 하려면 추후 E2EE를 별도로 검토합니다.

## 기술 구성

- Frontend: HTML / CSS / JavaScript
- Hosting: Railway
- Database/Auth: Supabase
- Security: Supabase RLS

## DB 적용 순서

새 프로젝트:

1. `supabase/schema.sql`
2. `supabase/migrations/20261001_discovery_limits.sql`
3. `supabase/migrations/20261001_matches_chat_reports.sql`
4. `supabase/migrations/20261001_beta_readiness_school_verification.sql`
5. `supabase/migrations/20261001_microsoft_school_oauth.sql`

기존 프로젝트도 위 migration 파일을 순서대로 추가 실행하면 됩니다.

## 현재 테스트 포인트

- Microsoft 로그인 버튼
- @sangmyung.kr 학교계정 인증
- 개인 Microsoft 계정 이용 차단
- OAuth 복귀 후 자동 인증 완료
- 기존 테스트 계정 계속 사용 가능
- 프로필 저장
- 인증 배지 표시
- 하루 프로필/관심 제한
- 서로 다른 성별 조합 및 동성 친구 찾기
- 자동 매칭
- 매칭 목록
- 내부 채팅
- 신고/차단
- 차단 해제
- 회원 탈퇴

## 문서

- [제품 방향 / 기능 결정](./PRODUCT_DECISIONS.md)
- [개인정보 / 채팅 설계](./PRIVACY_AND_CHAT_PLAN.md)
- [기능 테스트 체크리스트](./TEST_CHECKLIST.md)
- [참고 GitHub 프로젝트](./RESEARCH_MATCHING_REPOS.md)
- [Supabase 설정](./SUPABASE_SETUP.md)
- [Microsoft 학교계정 인증 설정](./MICROSOFT_AUTH_SETUP.md)

아직 정식 서비스 운영이 확정된 프로젝트는 아니며, 소규모 베타로 실제 사용 흐름을 검증하는 것을 목표로 합니다.
