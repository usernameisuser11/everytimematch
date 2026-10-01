# Everytime Match 개인정보 및 채팅 설계

최종 업데이트: 2026-10-01

## 목표

필요한 정보만 수집하고, 일반적인 운영 과정에서는 운영자도 민감한 세부정보를 볼 필요가 없도록 설계합니다.

## 기본 원칙

- 수집하지 않아도 되는 정보는 받지 않기
- 공개 프로필과 인증 정보를 분리
- 사용자 본인 데이터만 수정 가능
- 매칭/차단 관계에 따라 읽기 권한 제한
- 관리자 화면도 최소 정보만 제공
- Supabase RLS 유지

## 현재 데이터 구조

### profiles
- user_id
- nickname
- grade
- gender
- preference
- relationship_intent
- mbti
- bio
- is_active
- timestamps

### daily_discovery
- user_id
- target_user
- activity_date
- viewed_at
- decision
- decided_at

하루 프로필/좋아요 제한을 DB에서 강제하기 위한 기록입니다.

### likes
- from_user
- to_user
- created_at

### matches
- id
- user_a
- user_b
- status
- matched_at
- ended_at

상호 좋아요가 생기면 자동 생성됩니다.

### messages
- id
- match_id
- sender_id
- content
- created_at
- read_at

활성 매칭 당사자만 읽고 보낼 수 있도록 RLS를 적용합니다.

### blocks
- blocker
- blocked
- created_at

### reports
- reporter
- reported
- category
- reason
- match_id
- message_id
- status
- created_at

## 외부 연락처 제거

다음 정보는 더 이상 수집하지 않는 방향입니다.
- Instagram ID
- 카카오톡 ID
- 전화번호

매칭 이후 Everytime Match 내부 채팅을 사용합니다.

## 신고와 채팅 개인정보

프로필 신고:
- 신고 사유와 추가 설명 저장
- 신고와 동시에 상대 차단

메시지 신고:
- 사용자가 신고한 특정 message_id만 신고 기록에 연결
- 전체 대화 로그를 관리자 UI에 기본 노출하지 않는 방향

신고 후:
- 활성 매칭 종료
- 상대 차단
- 서로의 좋아요 제거
- 후보/매칭/채팅에서 더 이상 노출되지 않음

## 운영자가 채팅을 볼 수 있는지

RLS를 적용하면 일반 사용자가 다른 사람의 채팅을 볼 수 없고,
관리자 UI에서도 채팅을 숨길 수 있습니다.

다만 Supabase 프로젝트의 DB 최고 권한을 가진 운영자는 기술적으로 저장된 평문 메시지를 조회할 수 있습니다.

운영자도 기술적으로 채팅 내용을 읽을 수 없게 하려면 추후 종단간 암호화(E2EE)가 필요합니다.

## 관리자에게 보이는 정보

운영에 필요한 최소 정보:
- 내부 사용자 ID
- 닉네임
- 학년
- 성별
- MBTI
- 관계 목적
- 학교 인증 여부
- 가입일
- 신고 횟수
- 계정 상태

기본 관리자 UI에서 숨길 정보:
- 이메일 전체 주소
- 인증 관련 민감정보
- 개인 채팅 전체 원문
- 외부 연락처
- 불필요한 접속 정보

## 초기에는 저장하지 않을 정보

- 전화번호
- 집 주소
- GPS 위치
- 실명
- 외부 SNS ID
- 상세 신체정보

## 이후 검토

- 관리자 신고 검토함
- 신고 누적 기반 일시정지
- 학교 이메일 인증 강화
- E2EE
- 데이터 보관/삭제 정책
- 개인정보 처리방침 / 이용약관
