# Everytime Match

상명대 학생을 대상으로 아이디어를 검증 중인 **간단한 캠퍼스 매칭 웹서비스 프로토타입**입니다.

## 서비스 방향

복잡한 소개팅 앱보다 아래 흐름에 집중합니다.

`학교 인증 → 최소 프로필 → 후보 보기 → 관심/넘기기 → 상호 관심 자동 매칭 → 내부 채팅`

운영자가 직접 사용자를 수동으로 매칭하지 않습니다.

## 최소 프로필

- 닉네임
- 학년
- 성별
- 찾는 상대
- 한 줄 소개
- MBTI (선택)
- 관심사 최대 3개 (추가 후보)
- 사진 1장 (추가 후보)

## 개인정보 방향

- 외부 Instagram / 카카오 ID 수집은 제거하는 방향
- 매칭 후 서비스 내부 채팅 사용
- 관리자 화면에도 최소 프로필/운영 정보만 표시
- 이메일/인증정보는 Supabase Auth에 분리
- Supabase RLS 유지
- 불필요한 개인정보는 처음부터 수집하지 않음

> 일반적인 RLS만으로는 데이터베이스 최고 권한 운영자까지 채팅 원문 접근을 기술적으로 막을 수 없습니다.
> 운영자도 기술적으로 채팅 내용을 읽을 수 없게 하려면 추후 E2EE를 별도로 검토합니다.

## 현재 기술 구성

- Frontend: HTML / CSS / JavaScript
- Hosting: Railway
- Database/Auth: Supabase
- Security: Supabase RLS

## 현재 진행 상태

- Railway 배포 완료
- Supabase 프로젝트 생성 완료
- 초기 DB schema 적용 완료
- Supabase Auth 연결 완료
- 프로필/좋아요/차단/신고 연결 진행 중
- 현재 알려진 이슈: `permission denied for table profiles`

## 다음 구현 순서

1. profiles 권한 오류 해결
2. 외부 연락처 입력 제거
3. matches 테이블 및 자동 매칭 강화
4. 내부 텍스트 채팅 추가
5. 채팅 RLS 적용
6. 신고/차단 연결
7. 학교 인증
8. 관리자 최소정보 화면
9. 소규모 베타 테스트

## 문서

- [제품 방향 / 기능 결정](./PRODUCT_DECISIONS.md)
- [개인정보 / 채팅 설계](./PRIVACY_AND_CHAT_PLAN.md)
- [참고 GitHub 프로젝트](./RESEARCH_MATCHING_REPOS.md)
- [Supabase 설정](./SUPABASE_SETUP.md)

아직 기능과 운영 여부가 확정된 프로젝트는 아니며 사용자 의견을 참고하면서 최소 기능부터 검증하는 것을 목표로 합니다.
