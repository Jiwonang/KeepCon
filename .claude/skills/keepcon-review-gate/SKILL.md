---
name: keepcon-review-gate
description: "KeepCon PR을 머지해도 되는지 판정하는 스킬. 트리거 — PR을 올린 뒤, '머지해도 될까', '리뷰 확인해줘', 'CI 확인하고 머지해줘', 'CodeRabbit 결과 봐줘' 등 머지 가부를 묻는 요청. CI green 확인 + keepcon-code-reviewer 리뷰(기본 층) + CodeRabbit 상태 3분기 판정(리뷰됨/할당량 소진/미트리거)을 거쳐, 리뷰 없이 머지되는 경로를 차단한다. 후속 작업 — '다시 확인해줘', '지적 반영하고 다시'에도 사용."
---

# KeepCon 리뷰 게이트 — 리뷰 없이 머지되는 경로를 막는다

## 왜 스킬이 필요한가

**CodeRabbit 체크는 리뷰 여부와 무관하게 항상 green이다.** 관측된 사실(PR #89·#93·#94):

```text
CodeRabbit   pass   0s   "Review skipped: manual review required for this OSS repository"
```

리뷰를 실제로 돌린 PR도, 한 번도 안 돌린 PR도 똑같이 `pass`다. 그래서 **CodeRabbit은 게이트가 아니며, 필수 상태 체크로 등록해도 아무것도 막지 못한다.** 초록만 보고 머지하면 3층 방어 중 2층이 빈 채로 통과한다 — red보다 위험한 실패 양상이다(red는 보이고 미실행은 안 보인다).

이 스킬은 그 판정을 사람의 기억이 아니라 절차로 옮긴다.

## 층위 — 에이전트가 기본, CodeRabbit이 두 번째 의견

옛 규약은 CodeRabbit을 기본 리뷰 층으로 뒀지만 **실제 빈도와 맞지 않는다.** 이 저장소는 스타 10개 미만이라 자동 리뷰가 아예 안 돌고, 수동 트리거마저 할당량에 걸린다(PR #90이 써서 #92가 두 번 튕겼다). 기본 층이 자주 비는 구조다.

그래서 뒤집는다:

| 층 | 담당 | 성격 |
|---|---|---|
| 1 | CI 세 잡 (`Format · Analyze · Test` · `Firestore rules` · `Markdown lint`) | 기계 게이트 — red면 머지 불가 |
| 2 | `keepcon-code-reviewer` 에이전트 | **기본 리뷰 — 항상 돈다** |
| 3 | CodeRabbit | 두 번째 의견 — 할당량이 있을 때만 |
| 4 | 릴리스 전 `/security-review` | 주기적 |

3층이 빠져도 리뷰 없는 PR은 생기지 않는다. 대신 3층은 **다른 벤더의 다른 모델**이라는 독립성을 주므로, 돌 수 있으면 반드시 돌린다.

## 절차

### 1. CI 확인

```bash
gh pr checks <번호>
```

CI 잡이 하나라도 red면 **여기서 멈춘다.** 원인을 진단해 수정 → 커밋 → 푸시를 전부 green이 될 때까지 반복한다(CLAUDE.md의 수정 루프). `CodeRabbit` 행의 pass는 **무시한다** — 위에 적은 이유로 정보가 없다.

### 2. 기본 리뷰 (항상)

`keepcon-code-reviewer` 에이전트로 변경 diff를 리뷰한다. **작성자가 자기 코드를 리뷰하는 것이 아니라, 맥락을 공유하지 않는 에이전트가 처음부터 읽게 한다** — 잘못 읽어서 생긴 전제가 전달되지 않는 것이 이 층의 존재 이유다. 리뷰 결과나 작성 의도를 프롬프트에 넣지 않는다.

유효한 지적은 수정 → 커밋 → 푸시하고 1번으로 돌아간다.

### 3. CodeRabbit 상태 판정

세 상태 모두 코멘트를 남기므로 **코멘트 유무가 아니라 본문으로 구분한다.**

```bash
gh pr view <번호> --json comments,reviews --jq '[.comments[], .reviews[]] | map(select(.author.login=="coderabbitai").body) | if any(test("Actionable comments posted|No actionable comments")) then "REVIEWED" elif any(test("Review rate limited")) then "RATE_LIMITED" elif any(test("Review available on request")) then "NOT_TRIGGERED" else "NONE" end'
```

> ⚠️ `comments`만 보면 안 된다. CodeRabbit의 리뷰 본문은 PR에 따라 **일반 코멘트(`comments`)에 오기도 하고 리뷰(`reviews`)에 오기도 한다** — 한쪽만 조회하면 실제로 리뷰된 PR(#93·#95)이 `NOT_TRIGGERED`로 잘못 판정된다. 두 배열을 합쳐서 본다.

| 결과 | 뜻 | 할 일 |
|---|---|---|
| `REVIEWED` | 리뷰 본문이 게시됨 | 지적을 반영하고 4번으로 |
| `NOT_TRIGGERED` | 트리거를 안 함 (기본 상태) | `@coderabbitai review` 코멘트로 트리거 → 몇 분 뒤 재판정 |
| `RATE_LIMITED` | 할당량 소진 — **일시적** | **먼저 기다렸다 재트리거한다.** 폴백은 그다음 |

> ⚠️ `Review triggered`는 "접수됨"일 뿐 리뷰가 끝났다는 뜻이 아니다. 접수 응답을 리뷰 완료로 읽지 않는다.
>
> ⚠️ `REVIEWED`는 **"언젠가 리뷰됐다"는 뜻이지 "지금 head를 리뷰했다"는 뜻이 아니다.** CodeRabbit은 증분 리뷰라 이미 본 커밋을 다시 보지 않는다. 리뷰가 게시된 뒤 커밋을 더 푸시했다면 그 변경은 리뷰되지 않은 것이므로, `@coderabbitai review`로 다시 트리거한다.

`RATE_LIMITED`는 시간 창(rolling window) 제한이라 곧 풀린다. 봇이 남은 시간을 알려주며, `@coderabbitai rate limit`으로 잔량을 물어볼 수 있다. **바로 폴백으로 넘어가지 말고 안내된 시간만큼 기다렸다 다시 트리거한다.**

### 3b. 리뷰가 지금 head를 봤는지 확인 (필수)

`REVIEWED`는 "언젠가 리뷰됐다"는 뜻일 뿐이다. **리뷰 시각과 head 커밋 시각을 비교한다:**

```bash
gh pr view <번호> --json comments,reviews,commits --jq '([.comments[], .reviews[]] | map(select(.author.login=="coderabbitai") | select(.body|test("Actionable comments posted|No actionable comments")) | (.createdAt // .submittedAt)) | max) as $r | (.commits | last | .committedDate) as $c | if $r == null then "NO_REVIEW" elif $r < $c then "STALE (리뷰 \($r) < head \($c))" else "CURRENT" end'
```

`STALE`이면 **그 뒤 커밋은 리뷰되지 않았다** — `@coderabbitai review`로 재트리거한다. `CURRENT`일 때만 3층이 채워진 것이다.

이 검사가 없으면 눈으로는 못 잡는다. 도입 시점에 돌려 보니 **PR #93·#95 둘 다 `STALE`이었고, #93은 그 상태로 머지됐다** — 리뷰 게시 뒤 17분 동안 들어간 커밋은 아무도 보지 않았다. "리뷰 본문이 있는지"만 확인하는 규칙으로는 여기까지 못 간다.

### 4. 폴백 — 기다려도 안 될 때만

`RATE_LIMITED`가 재시도 뒤에도 유지되면 3층 없이 머지할 수 있다. **단, 반드시 기록을 남긴다:**

```bash
gh pr comment <번호> --body "$(cat <<'EOF'
🔁 **CodeRabbit 없이 머지 — 대체 리뷰 경로**

- CodeRabbit 상태: `RATE_LIMITED` (재트리거 후에도 유지)
- 대체 리뷰: `keepcon-code-reviewer` — 지적 N건 (🔴 a / 🟠 b / 🟡 c), 전부 반영
- CI: `Format · Analyze · Test` · `Firestore rules` · `Markdown lint` 전부 green

(사유: CodeRabbit 체크는 리뷰 여부와 무관하게 항상 pass라 게이트가 아니며, 이 기록이 어느 경로로 통과했는지를 남기는 유일한 수단이다.)
EOF
)"
```

**기록을 남기지 않으면 "그냥 머지"와 구분되지 않는다.** 나중에 이 PR이 어떤 검증을 거쳤는지 아무도 모른다.

### 5. 머지

다음이 모두 참일 때만 머지한다.

1. CI 세 잡 green (1번)
2. `keepcon-code-reviewer` 지적을 반영 완료 (2번)
3. 3번이 `REVIEWED` **이고** 3b가 `CURRENT` — 또는 4번의 폴백 기록이 PR에 남아 있음

## 하지 말 것

- `CodeRabbit` 체크가 pass인 것을 근거로 "리뷰 통과"라고 말하지 않는다.
- `Review triggered` 응답만 보고 머지하지 않는다.
- `REVIEWED`만 보고 머지하지 않는다 — **3b가 `CURRENT`인지 확인한다.** 리뷰 뒤 푸시한 커밋은 리뷰되지 않았다.
- `RATE_LIMITED`를 보자마자 폴백으로 가지 않는다 — 재시도가 먼저다.
- 폴백 경로를 기록 없이 지나가지 않는다.
- **스타가 10개 이상이 되면** 자동 리뷰가 복귀한다. 그때 3번의 `NOT_TRIGGERED` 분기는 드물어지지만 할당량 축은 그대로 남으므로 이 스킬은 유효하다.
