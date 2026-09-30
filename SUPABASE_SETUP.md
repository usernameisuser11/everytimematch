# Supabase 연결 순서

현재 Railway에 올라간 `index.html`은 브라우저 localStorage만 사용하는 데모입니다.
아래 순서로 Supabase를 붙이면 실제 사용자 데이터/좋아요/매칭을 저장할 수 있습니다.

## 1. Supabase 프로젝트 만들기

1. Supabase Dashboard에 로그인
2. **New project** 선택
3. 프로젝트 이름 예시: `everytimematch`
4. 강한 Database password 설정
5. 가까운 Region 선택
6. Free plan으로 생성

Database password는 프론트엔드 코드에 절대 넣지 않습니다.

## 2. 테이블 + 보안 정책 만들기

1. Supabase Dashboard에서 **SQL Editor** 열기
2. 이 저장소의 `supabase/schema.sql` 전체 내용을 붙여넣기
3. Run 실행
4. 오류 없이 완료되는지 확인

이 스키마는 다음을 만듭니다.

- `profiles`: 공개 가능한 프로필
- `private_contacts`: 인스타/오픈채팅 연락수단
- `likes`: 관심 표시
- `blocks`: 차단
- `reports`: 신고
- RLS 정책: 로그인한 사용자만 접근
- 연락처는 **서로 좋아요가 성립한 경우에만** 상대 값을 읽을 수 있음

## 3. 연결 정보 확인

프로젝트 상단의 **Connect** 또는
**Settings > API Keys**에서 아래 두 값만 확인합니다.

- Project URL
- Publishable key (`sb_publishable_...`)

### 보내도 되는 값
- Project URL
- Publishable key

### 절대로 공유하거나 브라우저 코드에 넣으면 안 되는 값
- Secret key (`sb_secret_...`)
- Database password
- Database connection password/URI

Publishable key는 브라우저용 키이며, 실제 데이터 접근 권한은 RLS 정책으로 제한합니다.

## 4. 다음 작업

Project URL + Publishable key가 준비되면 프론트엔드를 다음 구조로 변경합니다.

1. 이메일 회원가입 / 로그인
2. 로그인 사용자 ID와 프로필 연결
3. 프로필 DB 저장
4. DB에서 실제 상대 목록 조회
5. 좋아요 DB 저장
6. 상대도 좋아요를 눌렀는지 확인
7. 상호 좋아요일 때만 상대 연락수단 조회
8. 신고 / 차단 실제 DB 처리
9. 계정/프로필 삭제

## 학교 인증

초기 베타에서는 일반 이메일 Auth로 기능을 먼저 검증하고,
상명대 이메일 도메인을 확정한 뒤 가입 단계에서 학교 이메일 인증을 제한하는 방향으로 확장할 수 있습니다.
