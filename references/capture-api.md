# Context Bridge Capture API Reference

## 엔드포인트

```
POST /api/v1/captures
```

## 인증

`X-API-Key` 헤더에 프로젝트 API Key를 포함한다.

## 요청 본문

Content-Type: application/json

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| title | string | Y | 작업 제목 (50자 이내 권장) |
| intent | string | Y | 작업 의도 — 왜 이 작업을 했는가 |
| alternatives | string | N | 검토한 대안과 기각 사유 |
| diffSummary | string | N | 핵심 변경 사항 요약 |
| commitHash | string | Y | git 커밋 해시 |
| agentType | string | Y | CLAUDE_CODE, GEMINI_CLI, CODEX, OTHER 중 하나 |
| userRequestId | string | Y | 사용자 요청 식별자 (UUID) |
| userRequestPrompt | string | Y | 사용자가 요청한 원문 |
| changedFiles | string[] | Y | 커밋에 포함된 변경 파일 목록 |
| tag | string | Y | REFACTORING, FEATURE, BUGFIX, TEST, DOCS 중 하나 |

### 요청 예시

```json
{
  "title": "결제 모듈 재시도 로직을 Exponential Backoff로 교체",
  "intent": "기존 Fixed Retry 방식은 서버 과부하 시 동시 재시도가 몰려 장애를 악화시키는 문제가 있었다. Exponential Backoff + Jitter를 적용하여 재시도 요청을 분산시키고 서버 복구 시간을 확보한다.",
  "alternatives": "Fixed Retry 간격을 늘리는 방안을 검토했으나, 트래픽 패턴에 따라 여전히 동시 요청이 몰릴 수 있어 기각. Circuit Breaker 패턴도 검토했으나 현재 단계에서는 과도한 복잡성이라 판단.",
  "diffSummary": "PaymentRetryService.kt: retry 로직을 FixedDelay에서 ExponentialBackoff로 교체. application.yml: retry.maxAttempts=5, retry.initialInterval=1000 설정 추가.",
  "commitHash": "a1b2c3d4e5f6",
  "agentType": "CLAUDE_CODE",
  "userRequestId": "550e8400-e29b-41d4-a716-446655440000",
  "userRequestPrompt": "결제 모듈 재시도 로직을 exponential backoff로 바꿔줘",
  "changedFiles": ["src/main/kotlin/PaymentRetryService.kt", "src/main/resources/application.yml"],
  "tag": "FEATURE"
}
```

## 응답

### 성공 (201 Created)

```json
{
  "success": true,
  "response": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "projectId": "project-uuid",
    "title": "결제 모듈 재시도 로직을 Exponential Backoff로 교체.",
    "createdAt": "2026-03-27T14:30:00"
  },
  "error": null
}
```

### 에러 응답

| HTTP 상태 | 원인 | 설명 |
|-----------|------|------|
| 400 | 필수 필드 누락 | title, intent, commitHash, agentType, userRequestId, userRequestPrompt, changedFiles, tag 중 하나 이상 누락 |
| 401 | API Key 무효 | Key가 없거나, 잘못되었거나, 비활성화됨 |
| 404 | 프로젝트 없음 | API Key에 연결된 프로젝트가 삭제되었거나 존재하지 않음 |
| 429 | Rate Limit 초과 | 프로젝트당 분당 60회 제한 초과 |
| 5xx | 서버 오류 | 서버 내부 오류 |

### 에러 응답 형식

```json
{
  "success": false,
  "response": null,
  "error": {
    "message": "에러 설명",
    "status": 401
  }
}
```

## Rate Limit

- 프로젝트당 분당 60회
- 초과 시 429 응답 반환
