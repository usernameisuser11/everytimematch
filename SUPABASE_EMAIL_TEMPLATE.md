# Supabase 가입 인증메일 템플릿

Everytime Match는 가입 후 메일에 포함된 **8자리 인증코드**를 웹에서 직접 입력하는 흐름을 사용합니다.

Supabase Dashboard:

**Authentication → Email Templates → Confirm sign up**

에서 아래처럼 설정합니다.

## Subject

```
[Everytime Match] 상명대 이메일 인증코드
```

## Body

```html
<div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#202124">
  <h2 style="margin:0 0 16px">Everytime Match 학교 인증</h2>

  <p style="line-height:1.6">
    아래 8자리 인증코드를 Everytime Match 화면에 입력해주세요.
  </p>

  <div style="
    margin:24px 0;
    padding:18px;
    border-radius:14px;
    background:#fff3f5;
    text-align:center;
    font-size:32px;
    font-weight:800;
    letter-spacing:8px;
  ">
    {{ .Token }}
  </div>

  <p style="font-size:13px;line-height:1.6;color:#666">
    메일이 받은편지함에 없다면 스팸메일함 또는 정크메일함도 확인해주세요.
  </p>

  <p style="font-size:12px;line-height:1.6;color:#999">
    직접 코드 입력이 어려운 경우 아래 링크로도 인증할 수 있습니다.
  </p>

  <p>
    <a href="{{ .ConfirmationURL }}">이메일 인증하기</a>
  </p>
</div>
```

## 프론트 동작

1. 상명대 이메일 + 비밀번호로 가입
2. 가입 인증메일 발송
3. 웹에서 8자리 코드 입력
4. `verifyOtp({ email, token, type: "email" })` 호출
5. 성공 시 이메일 확인 완료 + 로그인 세션 생성
6. 프로필 작성으로 이동

## 주의

- 인증코드는 8자리입니다.
- 인증코드와 링크를 이메일에 같이 넣어도 됩니다.
- 인증 메일이 정크/스팸함으로 분류될 수 있다는 안내를 가입 화면과 인증코드 화면에 표시합니다.
- 공개 베타 단계에서 메일 도달률 문제가 계속되면 Supabase 기본 메일 발송 대신 Custom SMTP 도입을 검토합니다.
