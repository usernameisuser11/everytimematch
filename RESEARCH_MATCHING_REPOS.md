# Everytime Match — GitHub reference research

2026-09-30 기준으로, **대학생/캠퍼스 소개팅 + Supabase + 상호 좋아요/매칭 + 간단한 모바일 UX**에 참고할 만한 공개 GitHub 프로젝트를 모아둔 문서입니다.

> 주의: 아래 프로젝트는 구조와 아이디어를 참고하기 위한 목록입니다. 실제 코드를 가져오기 전에는 각 저장소의 LICENSE를 반드시 확인합니다.

## 가장 먼저 볼 것

### 1. CampusHearts
- Repo: https://github.com/jjf2009/CampusHearts
- 성격: 대학 전용 소개팅 앱
- Stack: Next.js + Supabase + Auth + RLS + Storage
- 참고 포인트:
  - 대학 이메일 전용 가입
  - 이메일 OTP 로그인
  - 프로필 탐색
  - 관심 요청
  - 수락/매칭 후에만 연락처 공개
  - 프로필 사진 Storage
  - RLS로 접근 제어
- Everytime Match와 컨셉이 가장 가까운 편.
- 특히 `supabase/migrations/0001_init.sql`의 RLS/요청 구조를 참고할 가치가 큼.

### 2. Linkup Dating App
- Repo: https://github.com/Itsme23476/linkup-dating-app
- 성격: Tinder 스타일 풀스택 앱
- Stack: React Native + Supabase
- 참고 포인트:
  - 상호 swipe 시 DB에서 자동 match 생성
  - matching을 서버/DB에서 원자적으로 처리
  - 이미 본 사람/차단한 사람 후보에서 제외
  - 매치 이후에만 메시지 접근 가능
  - RLS 전반 적용
- 우리 서비스에서는 복잡한 랭킹/채팅은 빼고 **상호 좋아요 자동 매칭 로직** 위주로 참고.

### 3. College Dating App
- Repo: https://github.com/SachinKishorS/college-dating-app
- 성격: 대학생 소개팅 가입 페이지
- Stack: React + Supabase Auth
- 참고 포인트:
  - 특정 대학 이메일 도메인 검증
  - 짧은 가입 절차
  - 이메일/비밀번호 검증
  - 가입 → 프로필 작성으로 바로 연결
- Everytime Match의 학교 인증 UX를 단순하게 만들 때 참고.

### 4. DASOM
- Backend: https://github.com/SiwonHae/DASOM_BE
- Frontend: https://github.com/GHYoungKyun/DASOM_FE
- 성격: 한국 대학생 소개팅 서비스
- Stack: Spring Boot + MariaDB
- 참고 포인트:
  - 한국 대학생을 대상으로 설계
  - UnivCert를 이용한 대학 메일 인증
  - 카카오/네이버 로그인
- 기능을 그대로 가져오기보다 **한국 대학 인증 흐름** 조사용으로 적합.

### 5. StreamMatch / Tinder Supabase Clone
- Repo: https://github.com/JomJom789/NEXT-PT-tinder-supabase-clone-stream
- Stack: Next.js + Supabase + Stream
- 참고 포인트:
  - profiles / likes / matches 구조
  - Supabase Auth/RLS
  - fake profile seeder
  - 모바일 UI
- 우리에게 특히 유용한 부분은 **테스트용 가짜 사용자 생성**과 DB 구조.

---

## 매칭/좋아요 구조 참고

### 6. Dating App — Swipe, Match & Chat
- Repo: https://github.com/Ritesh00007/dating-app-swipe-match-chat
- Stack: React + TypeScript + Node + SQLite
- 참고 포인트:
  - Like / Pass
  - mutual like 자동 감지
  - Match 목록
  - 깔끔한 카드 구조
- Supabase는 아니지만 화면 흐름 참고에 좋음.

### 7. Fullstack Tinder Clone
- Repo: https://github.com/Draviener/fullstack-tinder-clone
- Stack: React + TypeScript + NestJS + GraphQL
- 참고 포인트:
  - Like/Dislike
  - Match 생성
  - 프로필 조건 설정
- 기능 범위가 넓어서 우리 MVP에는 필요한 부분만 참고.

### 8. Dating App with Next.js + Supabase + Stream
- Repo: https://github.com/Bright-devops/Dating-App-building-using-Nextjs-supabase-and-Stream
- Stack: Next.js + Supabase + Stream
- 참고 포인트:
  - Supabase 기반 dating app 구성
  - 프로필 매칭
  - 실시간 기능 구조
- 채팅은 현재 Everytime Match에는 불필요.

### 9. DesiiMatch
- Repo: https://github.com/aceh970126/desii-match
- Stack: React Native + Expo + Supabase
- 참고 포인트:
  - Auth
  - onboarding
  - interests
  - discover
  - likes
  - Supabase Realtime
- 우리가 관심사를 최대 3개 정도 넣게 된다면 UX 참고.

### 10. Spark Dating App
- Repo: https://github.com/Goddy36-A/spark-dating-app
- Stack: Kotlin + Supabase
- 참고 포인트:
  - auth / onboarding / discovery / matching / safety가 기능별로 분리돼 있음
  - 신고/차단 safety 구조
  - Supabase migration / RLS
- 앱 자체는 너무 크지만 **신고·차단·운영 안전성** 참고에 좋음.

---

## 캠퍼스/학생 전용 서비스 참고

### 11. Campus Love
- Repo: https://github.com/JoseDFlorez/CampusLove
- 성격: 대학 환경 전용 dating app
- Stack: .NET + PostgreSQL
- 참고 포인트:
  - 대학생 특화 데이터 구조
  - 관심사 및 학과/지역 구조
- 우리 MVP에는 항목이 너무 많아질 수 있으므로 DB 아이디어만 참고.

### 12. CampusCrush
- Repo: https://github.com/beckynator/CampusCrush
- 성격: 같은 캠퍼스 학생끼리 만나는 서비스
- 참고 포인트:
  - 캠퍼스 한정 컨셉
- 구현보다 아이디어/브랜딩 참고용.

### 13. DateDrop Korea
- Repo: https://github.com/JseSeo/datingWeb
- 성격: 한국 대학생 대상 주간 소개팅 매칭 웹서비스
- Stack: React/Vite + FastAPI + Railway
- 참고 포인트:
  - 국내 대학생 대상
  - 주간 단위 매칭
  - 프론트/백엔드 분리
  - Railway 배포
- 우리와 배포 환경이 비슷해서 추가 조사 가치가 있음.

---

## UI만 참고

### 14. Dating App UI React Native
- Repo: https://github.com/joestackss/Dating-App-UI-React-Native
- 참고 포인트:
  - 카드 중심 모바일 UI
  - 소개팅 앱 화면 구성
- 로직보다는 모바일 카드 비주얼 참고.

### 15. Tinder Clone
- Repo: https://github.com/shlok2740/tinder-clone
- Stack: Next.js + Tailwind
- 참고 포인트:
  - 프로필 카드 UI
  - Tinder 스타일 화면
- 블록체인 관련 부분은 우리 프로젝트에 불필요.

---

## Supabase를 단순하게 쓰는 방식 참고

### 16. is-campus-match
- Repo: https://github.com/TideOrca/is-campus-match
- Stack: HTML/CSS/JS + Supabase + RLS
- 소개팅 앱은 아니지만, **별도 백엔드 없이 정적 웹 + Supabase** 구조.
- Everytime Match 현재 구조와 기술적으로 매우 유사.
- 참고 포인트:
  - CDN으로 supabase-js 사용
  - 정적 프론트 → Supabase 직접 접근
  - RLS 중요성
  - service_role을 브라우저에 넣지 않는 구조
- 현재 우리 구조 디버깅에 꽤 유용함.

### 17. Lume
- Repo: https://github.com/dakshdrall/Lume
- 성격: 대학생 전용 dating waitlist
- Stack: Next.js + Supabase
- 참고 포인트:
  - 18+ 체크
  - 개인정보/약관 UX
  - rate limit
  - bot/스팸 방지
  - 관리자용 구조
- MVP 이후 공개 베타 시 안전장치 참고.

---

## 내일 Everytime Match에서 실제로 가져올 아이디어

### MVP에 유지
1. 학교 이메일 인증
2. 닉네임
3. 학년
4. 성별
5. 찾는 상대
6. 한 줄 소개
7. MBTI 선택
8. 인스타 또는 카카오 오픈채팅
9. 후보 여러 명 보기
10. 관심 / 넘기기
11. 상호 관심 시 자동 매칭
12. 매칭 후 연락처 공개
13. 신고
14. 차단
15. 프로필 삭제

### 추가해도 복잡하지 않은 후보
- 사진 1장
- 관심사 최대 3개
- 이미 넘기거나 좋아요한 사람 재노출 방지
- 하루 추천 수 제한 (예: 5~10명)
- 매칭 목록 페이지
- 학교 인증 완료 배지

### 지금은 넣지 않을 것
- 앱 내 채팅
- 영상통화
- AI 궁합
- 복잡한 점수/랭킹
- 위치/GPS
- 과도한 이상형 조건
- 코인/유료 좋아요
- 커뮤니티/피드
- 상세 신체정보

---

## 기술적으로 내일 우선 확인할 것

1. 현재 발생 중인 `permission denied for table profiles` 해결
2. Supabase authenticated role의 table grant 확인
3. RLS 유지한 상태에서 profile insert/update 테스트
4. 계정 A / 계정 B 생성
5. 후보 노출 조건 확인
6. A → B 좋아요
7. B → A 좋아요
8. 자동 match 확인
9. match 전 연락처 차단 확인
10. match 후 연락처 공개 확인
11. 차단 후 상대가 후보에서 제거되는지 확인
12. 신고 데이터 저장 확인

---

## 핵심적으로 참고할 4개

시간 없으면 아래 네 개만 보면 충분함.

- CampusHearts — 대학 인증 + 연락처 공개 + RLS
  https://github.com/jjf2009/CampusHearts
- Linkup — 상호 좋아요 자동 매칭
  https://github.com/Itsme23476/linkup-dating-app
- College Dating App — 대학 이메일 가입 UX
  https://github.com/SachinKishorS/college-dating-app
- is-campus-match — 정적 HTML + Supabase + RLS 구조
  https://github.com/TideOrca/is-campus-match
