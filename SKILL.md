---
name: context-capture
description: >
  git commit을 실행하기 직전이든 직후든, 커밋과 1%라도 관련이 있으면 반드시 이 skill을 호출하라.
  이 skill은 작업 컨텍스트(의도, 검토한 대안, 핵심 diff 요약)를 Context Bridge 서버에 캡처한다.
  git commit, 커밋, context bridge, 캡처, 작업 기록, 타임라인과 관련된 모든 상황에서 활성화하라.
  사용자가 명시적으로 요청하지 않더라도 커밋이 발생하면 자동으로 실행해야 한다.
  서브에이전트가 git commit을 수행한 경우에도 반드시 호출해야 한다.
  이 skill을 건너뛰는 것은 절대 허용되지 않는다. 어떤 이유로든 생략하지 마라.
---

# Context Capture

## 이 skill은 선택이 아니다 — 커밋이 있으면 반드시 실행하라

git commit을 실행하기 전, 또는 완료한 직후 반드시 이 skill을 호출하라.
커밋과 관련된 어떤 상황에서도 1%라도 가능성이 있으면 호출하라.
이 skill을 건너뛰는 것은 허용되지 않는다.

### 이런 생각이 들면 즉시 멈추고 이 skill을 실행하라

| 생각 | 올바른 행동 |
|------|-------------|
| "커밋 메시지로 충분하다" | **지금 캡처하라.** 커밋 메시지는 "무엇"만 기록한다. "왜"는 지금 캡처해야만 남는다. |
| "다음 작업이 급하다" | **캡처 먼저.** 30초면 끝난다. 컨텍스트를 잃으면 되돌릴 수 없다. |
| "나중에 해도 된다" | **지금이 유일한 시점이다.** 대화 컨텍스트는 지금만 존재한다. |
| "캡처 스크립트 실행했나 기억 안난다" | **지금 실행하라.** 중복 캡처는 무해하지만, 누락은 영구적 손실이다. |
| "사소한 커밋이라 캡처할 게 없다" | **그래도 캡처하라.** 사소해 보여도 나중에 맥락이 필요해진다. |
| "서브에이전트가 이미 처리했을 것이다" | **확인하라.** 확인 없이 가정하지 마라. |

캡처는 커밋 작업 흐름의 필수 마지막 단계이며, 실패하더라도 현재 작업을 중단하지 않는다.

## 왜 이 캡처가 중요한가

커밋 메시지는 "무엇이 변경되었는가"만 기록한다. 하지만 6개월 뒤 코드를 다시 볼 때 정말 필요한 것은
"왜 이렇게 만들었는가" — 어떤 대안을 검토했고, 왜 이 방식을 선택했으며, 어떤 리스크를 감수했는지다.
지금 너의 대화 컨텍스트에 이 정보가 모두 있다. 커밋 직후가 이 정보를 기록할 수 있는 유일한 시점이다.

## 실행 경로 선택

이 skill에는 두 가지 실행 경로가 있다:

| 상황 | 실행 방법 |
|------|-----------|
| **메인 세션에서 직접 커밋** | 아래 "절차" 섹션을 따른다 |
| **서브에이전트가 커밋** | "서브에이전트 커밋 처리" 섹션을 따른다 |

## 절차

### 1. 설정 파일 확인

프로젝트 루트의 `context-bridge.yml`을 Read 도구로 읽는다.

파일에서 `api_key`와 `endpoint` 두 값을 추출한다. 파일이 없거나 값이 누락되어 있으면:

> "Context Bridge 설정 파일(context-bridge.yml)이 없거나 api_key/endpoint가 누락되어 캡처를 건너뜁니다."

이 메시지를 출력하고 **캡처를 중단**한다. 현재 작업은 계속 진행한다.

### 2. 커밋 해시 및 변경 파일 추출

```bash
git rev-parse HEAD
git diff --name-only HEAD~1 HEAD
```

두 명령의 결과를 각각 `commitHash`와 `changedFiles` 필드에 사용한다.

### 3. 요약 데이터 생성

이번 작업의 대화 컨텍스트를 돌아보고 아래 필드를 생성한다.
프로젝트의 주 사용 언어(한국어, 영어 등)에 맞춰 작성한다.

**title** (필수): 작업을 한 줄로 요약한 제목. 50자 이내. 커밋 메시지보다 서술적으로.
- 좋은 예: "결제 모듈의 재시도 로직을 Exponential Backoff로 교체"
- 나쁜 예: "fix: retry logic" (너무 짧고 맥락 없음)

**intent** (필수): 이 작업을 수행한 이유와 배경. 2-5문장으로 "왜 이 변경이 필요했는가"에 답한다.
- 기존 코드의 문제점이 무엇이었는지
- 이 변경으로 어떤 개선이 이루어지는지
- 관련된 요구사항이나 이슈가 있다면 언급

**alternatives** (선택): 검토했지만 선택하지 않은 대안. 대안이 없었으면 빈 문자열.
- 각 대안에 대해: 무엇을 검토했고, 왜 선택하지 않았는지

**diffSummary** (선택): 핵심 변경 사항 요약. 의존성 변경, 알고리즘 교체, 설정 변경, 새로운 엔티티/API 추가 등 핵심 로직 위주.
- 단순 포맷팅, 임포트 정리 등은 제외
- 파일명과 변경 내용을 간결하게 나열

**commitHash** (필수): 절차 2에서 추출한 값.

**agentType** (필수): 너의 에이전트 종류에 맞는 값을 선택한다.
- Claude Code → `CLAUDE_CODE`
- Gemini CLI → `GEMINI_CLI`
- Codex -> `CODEX`
- 그 외 → `OTHER`

**changedFiles** (필수): 이번 커밋에 포함된 변경 파일 목록. `git diff --name-only HEAD~1 HEAD` 결과를 사용한다.
- 예: `["src/main/kotlin/PaymentService.kt", "src/test/kotlin/PaymentServiceTest.kt"]`

**tag** (필수): 이번 작업의 성격을 나타내는 태그. 아래 중 하나를 선택한다.
- `REFACTORING`: 기존 코드 구조 개선 (동작 변경 없음)
- `FEATURE`: 새로운 기능 추가
- `BUGFIX`: 버그 수정
- `TEST`: 테스트 추가/수정
- `DOCS`: 문서 작성/수정

### 4. capture.sh 실행

절차 3에서 생성한 데이터를 인자로 넘겨 캡처 스크립트를 실행한다.
스크립트가 설정 파일 읽기, JSON 생성, API 호출, 결과 처리를 모두 수행한다.

```bash
bash .claude/skills/context-capture/scripts/capture.sh \
  --title "여기에 title" \
  --intent "여기에 intent" \
  --commit-hash "여기에 commitHash" \
  --agent-type "CLAUDE_CODE" \
  --changed-files "file1.kt,file2.kt" \
  --tag "여기에 tag (REFACTORING|FEATURE|BUGFIX|TEST|DOCS)" \
  --alternatives "여기에 alternatives" \
  --diff-summary "여기에 diffSummary"
```

캡처 실패 시 현재 작업 흐름을 절대 중단하지 않는다. 경고만 출력하고 원래 작업을 계속한다.

## 서브에이전트 커밋 처리

서브에이전트(Agent 도구로 생성된 에이전트)는 Skill 도구에 접근할 수 없다.
따라서 서브에이전트가 git commit을 수행하는 경우, 프롬프트에 capture.sh 실행 지시를 포함한다.

서브에이전트에게 작업을 위임할 때, 프롬프트 끝에 다음 지시를 추가한다:

```
git commit 완료 후, 반드시 아래 스크립트를 실행하라:

bash .claude/skills/context-capture/scripts/capture.sh \
  --title "작업 제목 (50자 이내)" \
  --intent "왜 이 작업을 했는가 (2-5문장)" \
  --commit-hash "$(git rev-parse HEAD)" \
  --agent-type "CLAUDE_CODE" \
  --changed-files "$(git diff --name-only HEAD~1 HEAD | paste -sd',' -)" \
  --tag "REFACTORING|FEATURE|BUGFIX|TEST|DOCS 중 하나" \
  --alternatives "검토한 대안 (없으면 빈 문자열)" \
  --diff-summary "핵심 변경 사항 요약"

스크립트가 실패해도 작업을 중단하지 말고 계속 진행하라.
```

서브에이전트가 자신의 작업 컨텍스트를 가장 잘 알고 있으므로 이 방법이 가장 정확하다.

프롬프트에 캡처 지시를 포함하지 못한 경우, 서브에이전트 완료 후 컨트롤러가 위 "절차" 섹션을 따라 직접 캡처한다.
서브에이전트 결과에 커밋 해시가 포함되지 않은 경우 `git log --oneline -1`로 확인한다.

## API 상세

캡처 API의 전체 스펙은 `references/capture-api.md`를 참조한다.
