# Everytime Match

상명대 학생을 대상으로 아이디어를 검증 중인 **간단한 캠퍼스 매칭 웹서비스 프로토타입**입니다.

## 핵심 흐름

`학교 인증 → 최소 프로필 → 후보 보기 → 관심/넘기기 → 상호 관심 자동 매칭 → 내부 채팅`

운영자가 직접 사용자를 수동으로 매칭하지 않습니다.

## 현재 구현 방향

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
- 매칭 해제 / 차단
- Supabase RLS 적용

## 개인정보 방향

- 외부 연락처 수집 안 함
- 이메일/인증정보는 Supabase Auth에 분리
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

기존 프로젝트도 위 migration 파일을 순서대로 추가 실행하면 됩니다.

## 현재 테스트 포인트

- 프로필 저장
- 하루 프로필/관심 제한
- 서로 다른 성별 조합 및 동성 친구 찾기
- 기존 상호 좋아요의 매칭 목록 복구
- 새 상호 좋아요의 자동 매칭
- 내부 채팅 전송/조회
- 매칭 해제
- 차단
- 프로필 신고
- 채팅 메시지 신고
- 신고 후 상대가 후보/매칭/채팅에서 제거되는지

## 문서

- [제품 방향 / 기능 결정](./PRODUCT_DECISIONS.md)
- [개인정보 / 채팅 설계](./PRIVACY_AND_CHAT_PLAN.md)
- [기능 테스트 체크리스트](./TEST_CHECKLIST.md)
- [참고 GitHub 프로젝트](./RESEARCH_MATCHING_REPOS.md)
- [Supabase 설정](./SUPABASE_SETUP.md)

아직 정식 서비스 운영이 확정된 프로젝트는 아니며, 소규모 베타로 실제 사용 흐름을 검증하는 것을 목표로 합니다.
