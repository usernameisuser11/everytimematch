# Supabase 연결 및 업데이트 순서

## 새 프로젝트

Supabase 프로젝트 생성 후 SQL Editor에서 아래 순서대로 실행합니다.

1. `supabase/schema.sql`
2. `supabase/migrations/20261001_discovery_limits.sql`
3. `supabase/migrations/20261001_matches_chat_reports.sql`

각 파일을 전체 복사해서 **Run** 하면 됩니다.

정상 실행 시 보통:

`Success. No rows returned`

가 표시됩니다.

## 현재 migration 역할

### 20261001_discovery_limits.sql

- 찾는 상대: 남성 / 여성 / 상관없음
- 찾는 관계: 친구 / 소개팅 / 둘 다
- 하루 프로필 10명
- 하루 관심 5개
- 같은 날 재노출 방지
- DB 함수 기반 후보 조회

### 20261001_matches_chat_reports.sql

- matches 테이블
- 기존 상호 좋아요 backfill
- mutual like 발생 시 자동 match 생성
- messages 테이블
- 매칭 당사자 전용 채팅 RLS
- 매칭 목록 RPC
- 매칭 해제 / 차단 RPC
- 프로필 신고
- 메시지 신고
- 신고 시 즉시 차단
- 기존 private_contacts 제거

## 연결 정보

프론트엔드에서 사용하는 값:

- Project URL
- Publishable key

브라우저에 넣으면 안 되는 값:

- Secret key
- service_role key
- Database password
- Database connection password/URI

Publishable key는 공개 가능한 클라이언트 키이며 실제 접근 제한은 RLS로 처리합니다.

## Authentication URL

Authentication → URL Configuration:

- Site URL: Railway 실제 주소
- Redirect URLs: Railway 실제 주소

예:
`https://everytimematch-production.up.railway.app/`

## schema cache 오류

새 RPC를 만든 직후:

`Could not find the function ... in the schema cache`

오류가 뜨면 SQL Editor에서 실행:

```sql
NOTIFY pgrst, 'reload schema';
```

## 테스트

DB 업데이트 후 `TEST_CHECKLIST.md` 순서대로 2개 이상의 계정으로 테스트합니다.
