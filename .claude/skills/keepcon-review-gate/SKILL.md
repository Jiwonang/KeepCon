---
name: keepcon-review-gate
description: "KeepCon PR을 머지해도 되는지 판정하는 스킬. 트리거 — PR을 올린 뒤, '머지해도 될까', '리뷰 확인해줘', 'CI 확인하고 머지해줘', 'CodeRabbit 결과 봐줘' 등 머지 가부를 묻는 요청. CI green 확인 + keepcon-code-reviewer 리뷰(기본 층 — 푸시 전에 끝났는지 확인하고, 없으면 실행) + CodeRabbit 상태 3분기 판정(리뷰됨/할당량 소진/미트리거)을 거쳐, 리뷰 없이 머지되는 경로를 차단한다. 후속 작업 — '다시 확인해줘', '지적 반영하고 다시'에도 사용."
---

# KeepCon 리뷰 게이트 — 리뷰 없이 머지되는 경로를 막는다

## 왜 스킬이 필요한가

**CodeRabbit 체크는 리뷰 여부와 무관하게 항상 green이다.** 관측된 사실(PR #89·#93·#94):

```text
CodeRabbit   pass   0s   "Review skipped: manual review required for this OSS repository"
```

리뷰를 실제로 돌린 PR도, 한 번도 안 돌린 PR도 똑같이 `pass`다. 그래서 **CodeRabbit은 게이트가 아니며, 필수 상태 체크로 등록해도 아무것도 막지 못한다.** 초록만 보고 머지하면 방어 층 하나가 빈 채로 통과한다 — red보다 위험한 실패 양상이다(red는 보이고 미실행은 안 보인다).

이 스킬은 그 판정을 사람의 기억이 아니라 절차로 옮긴다.

## 층위 — 에이전트가 기본, CodeRabbit이 두 번째 의견

옛 규약은 CodeRabbit을 기본 리뷰 층으로 뒀지만 **실제 빈도와 맞지 않는다.** 이 저장소는 스타 10개 미만이라 자동 리뷰가 아예 안 돌고, 수동 트리거마저 할당량에 걸린다(PR #90이 써서 #92가 두 번 튕겼다). 기본 층이 자주 비는 구조다.

그래서 뒤집는다:

번호는 **도는 순서**다(CLAUDE.md의 "코드 리뷰(4층 중첩)"과 같은 번호를 쓴다).

| 층 | 담당 | 언제 | 성격 |
|---|---|---|---|
| 1 | `/code-review` (내장) | 커밋 **전** | 일반적 정확성·단순화 |
| 2 | `keepcon-code-reviewer` 에이전트 | 커밋 후·푸시 **전** | **기본 리뷰 — 항상 돈다** |
| 3 | CI 세 잡 (`Format · Analyze · Test` · `Firestore rules` · `Markdown lint`) | PR 후 | 자동 실행. **다만 룰셋 필수 체크는 `Format · Analyze · Test` 하나뿐** — 나머지 둘은 red여도 머지가 막히지 않으니 눈으로 확인한다 |
| 4 | CodeRabbit | PR 후 (지적이 나오면 반영 후 1회 더) | 두 번째 의견 — 할당량이 있을 때만 |
| — | 릴리스 전 `/security-review` | 주기적 | |

4층이 빠져도 리뷰 없는 PR은 생기지 않는다. 대신 4층은 **다른 벤더의 다른 모델**이라는 독립성을 주므로, 돌 수 있으면 반드시 돌린다.

## 이 스킬보다 먼저 오는 것 — 에이전트 리뷰는 **푸시 전**에 돈다

게이트는 PR이 올라온 뒤 "머지해도 되는가"를 판정한다. 그런데 **기본 리뷰(2층)는 그보다 앞,
커밋 후·푸시 전에 돌아야 한다.** 작업 순서는 이렇다.

```text
/code-review          ← 커밋 전 (내장 — 일반적 정확성·단순화)
커밋
로컬 검증              ← bash tool/verify.sh   (판단 없이 한 번에)
keepcon-code-reviewer ← 푸시 전 (전용 — 저장소 맥락·실행 검증·뮤테이션)
반영 → 푸시 → PR   ← **PR 본문에 `에이전트 리뷰: <리뷰한 SHA>`를 적는다**(5번에서 대조)
[여기부터 이 스킬] CI → CodeRabbit → 3b(SHA) → (STALE이면 반영 후 재트리거) → 머지
```

**왜 푸시 전인가 — 두 가지 실측 근거.**

1. **CodeRabbit 슬롯이 라운드 수만큼 곱해진다.** PR을 올린 뒤 리뷰하고 고치면 head가 움직여
   봇 리뷰가 `STALE`이 되고, 라운드마다 재트리거가 필요하다. 이 계정의 실효 한도는 **시간당
   1건**이고 **계정 단위 공유 풀**이라 다른 PR과 슬롯을 다툰다 — PR #95·#101 모두 리뷰
   2라운드를 받는 데 트리거를 각각 5회·3회 썼고(나머지는 `RATE_LIMITED`로 튕겼다),
   2026-08-19 하루에 재트리거 대기로만 두 시간 넘게 썼다(#101 한 건이 07:29→09:45 = 2시간 16분).
   숫자는 `gh api repos/Jiwonang/KeepCon/pulls/<N>/reviews`로 재확인할 수 있다.
2. **틀린 주장이 공개된 뒤에 정정된다.** PR #101은 본문·제목·커밋 메시지에 "같은 diff를
   나란히 리뷰했다"고 적은 채 공개됐고, 에이전트가 그 전제를 무너뜨린 것은 그 뒤였다.
   푸시 전에 리뷰했다면 애초에 쓰지 않았을 문장이다.

**커밋 후·푸시 전**인 이유는 따로 있다. 에이전트 정의는 뮤테이션 검증에 "대상이 체크아웃돼
있고 `git status --porcelain`이 비어 있을 것"을 요구한다 — **커밋 전에 돌리면 그 수단이
원리상 죽는다.**

CI를 아직 못 본다는 것이 유일한 손해인데 실질적이지 않다. `tool/verify.sh`가 CI 세 잡과
같은 도구를 돌리고, **규칙 계층 입력**(`firestore.rules`·`tool/verify_firestore_rules.sh`·
`firebase.json`)이 바뀌었으면 규칙 검증까지 자동으로 붙인다.

⚠️ 트리거를 규칙 파일 하나로 좁히지 않은 이유: CI의 `Firestore rules` 잡은 경로 필터가
없어 **모든 PR에서** 돈다. 로컬이 더 좁으면 검증 케이스만 고친 변경이 로컬에서 통과하고
CI에서 처음 빨개진다.

그 자동 판단이 이 스크립트의 존재 이유다. 예전에는 규칙 검증이 "규칙을 바꿨을 때만" 도는
조건부라 매번 사람이 판단했고, PR #104에서 규칙을 세 번 고치는 동안 **세 번 다 건너뛰었다** —
규칙이 자기 픽스처를 깨거나 없는 문서 접근이 403이 되어 정리 경로가 죽는 결함이 매번 다음
리뷰 라운드에 가서야 드러났다. 판단을 사람에게 남겨 두면 그 판단이 실패한다.

## 절차

### 1. CI 확인

```bash
gh pr checks <번호>
```

CI 잡이 하나라도 red면 **여기서 멈춘다.** ⚠️ **`Firestore rules`·`Markdown lint`는 룰셋 필수 체크가 아니라 red여도 머지 버튼이 열려 있다** — 게이트가 막아 주지 않으므로 이 단계에서 사람이 본다(현재 필수 체크는 `Format · Analyze · Test`와 `CodeRabbit` 둘뿐이다: `gh api repos/Jiwonang/KeepCon/rulesets/18610485 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks'`). 원인을 진단해 수정 → 커밋 → 푸시를 전부 green이 될 때까지 반복한다(CLAUDE.md의 수정 루프). `CodeRabbit` 행의 pass는 **무시한다** — 위에 적은 이유로 정보가 없다.

### 2. 기본 리뷰가 돌았는지 확인

**정상 경로에서는 푸시 전에 이미 끝나 있다**(위 절 참조). 이 단계는 그 사실을 확인하는
자리다 — 지적과 반영 내역이 있는지 본다. 남의 PR이거나 다른 경로로 올라와 리뷰가 없으면
**여기서 돌린다**(리뷰 없이 머지되는 경로를 막는 것이 이 스킬의 목적이므로, 늦더라도 돈다).

**리뷰 기록이 이미 있고 그 뒤 푸시한 커밋이 없으면 여기서 다시 돌리지 않는다** — 재리뷰는 head를
움직여 CodeRabbit 라운드를 하나 더 쓴다(이 순서 변경이 없애려던 비용이다). 뒤에 커밋이 있으면
**그 범위만** 다시 본다(5번의 SHA 대조 참조).

**리뷰 기록이 없을 때만** 아래를 실행한다.

> `keepcon-code-reviewer` 에이전트로 변경 diff를 리뷰한다. **작성자가 자기 코드를 리뷰하는 것이 아니라, 맥락을 공유하지 않는 에이전트가 처음부터 읽게 한다** — 잘못 읽어서 생긴 전제가 전달되지 않는 것이 이 층의 존재 이유다.
>
> 프롬프트에는 리뷰 결과·작성 의도를 넣지 않는다. **다만 그것으로 차단되지는 않는다** — PR 번호를 주는 이상 리뷰어는 `gh pr view`로 PR 본문("고민했던 내용" 포함)을 읽는다. 그래서 진짜 방어선은 차단이 아니라 **반증**이다: PR 본문과 주석은 **주장으로만 취급하고 코드·실행으로 다시 확인한다**(에이전트 정의의 "반증 지향" 절). 의도를 정말 차단하려면 PR 번호 대신 `<base>...<head>` 커밋 범위만 넘긴다.
>
> 유효한 지적은 수정 → 커밋 → 푸시하고 1번으로 돌아간다.

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

`RATE_LIMITED`는 시간 창(rolling window) 제한이라 곧 풀린다. 바로 폴백으로 넘어가지 말고 기다렸다 다시 트리거한다. **단, 봇 안내 문구를 그대로 믿지 마라.**

```bash
# 창이 열리는 시각 = 저장소 전체 마지막 성공 리뷰 + 1시간 (+ 여유 2분)
# --limit은 저장소 전체 PR 수 이상으로 — 오래된 PR을 재트리거해도 같은 풀을 쓰므로
# 상한이 낮으면 그 리뷰를 놓쳐 창을 이르게 계산한다. (PR 40개당 약 25초)
#
# 실패를 삼키면 안 된다. 일부 PR 조회만 실패해도 나머지로 "마지막 리뷰"가 계산돼
# 창을 이르게 잡고, 그러면 트리거가 튕겨 슬롯을 버린다. 한 건이라도 실패하면 멈춘다.
# (전체를 서브셸로 감싸 exit이 사용자 셸을 닫지 않게 한다.)
(
  set -o pipefail
  nums=$(gh pr list --state all --limit 200 --json number --jq '.[].number') || { echo "PR 목록 조회 실패 — 트리거하지 마라"; exit 1; }

  tmp=$(mktemp)
  for n in $nums; do
    gh api "repos/Jiwonang/KeepCon/pulls/$n/reviews" --jq '.[] | select(.user.login=="coderabbitai[bot]") | .submitted_at' >> "$tmp" || { echo "PR #$n 조회 실패 — 부분 결과로 계산하면 창을 이르게 잡는다. 트리거하지 마라"; rm -f "$tmp"; exit 1; }
  done
  last=$(sort "$tmp" | tail -1); rm -f "$tmp"

  [ -n "$last" ] || { echo "리뷰 0건 — 원인을 확인하기 전에는 트리거하지 마라"; exit 1; }
  python -c "import sys,datetime as d;t=d.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00'))+d.timedelta(hours=1,minutes=2);print('마지막 리뷰',sys.argv[1],'→ 트리거 가능',t.strftime('%Y-%m-%dT%H:%M:%SZ'))" "$last"
)
```

> ⚠️ **한도는 PR별이 아니라 계정 단위 공유 풀이다.** 이 계정의 실효 한도는 시간당 1건이며(봇이 리뷰 본문에 `Your plan provides up to 1 included review per hour`라고 적는다 — 플랜 상한인 Pro+ 시간당 10건이 아니라 fair-usage로 조여진 값이다), **저장소의 다른 PR이 같은 슬롯을 가져간다.**
>
> ⚠️ `@coderabbitai rate limit`이 알려주는 "N분 뒤"는 **조회 시점 기준의 근사치라 경계에서 진다.** 2026-08-19 실측: 안내받은 29분을 기다려 #101을 트리거했으나 창(07:30:01Z)이 열리기 **16초 전**이라 튕겼다. 실패한 트리거는 창을 앞당겨 주지도 않는다.
>
> ⚠️ **그런데 시간만 변수가 아니다 — 대기열도 변수다.** 같은 실측에서 #102는 창이 열리기 **78초 전**(07:28:43Z)에 트리거했는데 수락돼 07:32:36Z에 리뷰를 받았다. #101이 진 진짜 이유는 경계 오차가 아니라 **1분 2초 먼저 줄을 선 #102**다 — 시간 계산만으로는 못 이긴다. 그래서 아래 "다른 PR을 트리거하지 않는다"가 계산보다 중요하다.
>
> 그래서 **위 명령으로 계산한 시각 + 2분**에 트리거하고, 기다리는 동안 **다른 PR을 트리거하지 않는다**(같은 풀을 다툰다).

### 3b. 리뷰가 지금 head를 봤는지 확인 (필수)

`REVIEWED`는 "언젠가 리뷰됐다"는 뜻일 뿐이다. **CodeRabbit이 리뷰한 커밋과 현재 head를 비교한다:**

```bash
gh api repos/Jiwonang/KeepCon/pulls/<번호>/reviews --jq '[.[] | select(.user.login=="coderabbitai[bot]") | .commit_id] | last // "NO_REVIEW"'
gh pr view <번호> --json headRefOid --jq .headRefOid
```

두 SHA가 같으면 `CURRENT`, 다르면 `STALE`이다. `STALE`이면 **그 뒤 커밋은 리뷰되지 않았다** — `@coderabbitai review`로 재트리거한다. `CURRENT`일 때만 4층(CodeRabbit)이 채워진 것이다.

> ⚠️ **시각(timestamp)으로 비교하지 마라.** 리뷰 게시 시각과 `commits[].committedDate`를 견주는 방식은 틀린다 — `committedDate`는 푸시 시각이 아니라 **작성자 로컬 시계의 커밋 생성 시각**이다. 리뷰를 기다리는 몇 분 사이에 커밋해 두고 리뷰가 올라온 뒤 푸시하면(흔한 작업 흐름) 커밋이 리뷰보다 **이르게** 찍혀 `CURRENT`로 통과한다 — 3b가 막으려던 바로 그것이다. 작성자 시계가 앞서 있으면 반대로 늘 `STALE`이 되어 소음이 된다. SHA 비교는 시계·푸시 지연과 무관하다.
>
> ⚠️ **3단계는 `comments`와 `reviews`를 둘 다 보는데 3b는 `reviews`만 본다.** 리뷰 본문이 SHA 없는 일반 코멘트로만 올라오면 여기서 `NO_REVIEW`가 되어 영원히 `CURRENT`가 될 수 없다. 그때는 **`CURRENT`로 치지 마라** — 재트리거해서 `reviews`에 실리게 하거나, 그래도 안 되면 4번 폴백으로 기록을 남긴다. (2026-08-20 기준 최근 40개 PR에서 리뷰 본문이 일반 코멘트로만 온 사례는 0건이지만, 3단계가 그 가능성을 명시하므로 규칙을 비워 두지 않는다.)
>
> ⚠️ 3단계의 로그인 이름은 `coderabbitai`인데 **여기서는 `coderabbitai[bot]`이다.** REST(`/pulls/N/reviews`)와 GraphQL(`gh pr view`)이 봇 계정을 다르게 표기한다 — 섞어 쓰면 항상 `NO_REVIEW`가 나온다.

이 검사가 없으면 눈으로는 못 잡는다. 도입 시점에 돌려 보니 **PR #93·#95 둘 다 `STALE`이었고, #93은 그 상태로 머지됐다**(#93: 리뷰 커밋 `3568d64f` ≠ head `3ff2eb7d`). "리뷰 본문이 있는지"만 확인하는 규칙으로는 여기까지 못 간다.

### 3c. 리뷰어끼리 어긋나면 — 입력→결과를 댄 쪽이 이긴다

`/code-review`·에이전트·CodeRabbit이 같은 지점에 **다른 심각도나 다른 처방**을 낼 수 있다.
기준은 "나중에 본 쪽"도 "우리 것"도 아니다 — **구체적 입력·상태 → 잘못된 결과를 실제로 댄
쪽**을 따른다. 근거의 종류가 우선순위를 정한다.

1. 실행으로 재현한 것(에뮬레이터 403, 실패하는 테스트, 뮤테이션)
2. 코드·이력을 인용해 경로를 짚은 것
3. 일반론·원칙만 든 것

PR #98이 사례다. 에이전트는 매퍼 순환을 정확히 짚고도 처방을 `🟡 주석 수정`으로 냈고(세션 안의
리뷰라 PR 기록에는 없다),
CodeRabbit은 같은 지점을 `🟠 쓰기 경로에서 거부`로 냈다 — **봇이 맞았다.** 손상 문서가 빈
식별자로 사용 이력에 적재되는 경로를 댈 수 있었기 때문이다.

어느 쪽도 입력→결과를 못 대면 **둘 다 🟡로 내리고** 왜 그렇게 판단했는지 PR에 적는다.

### 4. 폴백 — 기다려도 안 될 때만

`RATE_LIMITED`가 재시도 뒤에도 유지되면 4층(CodeRabbit) 없이 머지할 수 있다. **단, 반드시 기록을 남긴다:**

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

1. CI 세 잡(`Format · Analyze · Test` · `Firestore rules` · `Markdown lint`) green (1번). `gh pr checks`는 **이름 오름차순**이라 `CodeRabbit`이 보통 **첫 행**에 온다 — 위치가 아니라 **이름으로** 골라라(행 수도 불안정하다: `Markdown lint` 도입 전인 PR #93은 3행뿐이다)
2. `keepcon-code-reviewer` 지적을 반영 완료 (2번 — 정상 경로에서는 푸시 전에 끝나 있다) **그리고**
   그 뒤 푸시한 커밋이 없다: PR 본문의 `에이전트 리뷰: <SHA>` == `gh pr view <번호> --json headRefOid --jq .headRefOid`.
   다르면 3b와 같은 이유로 **그 뒤 커밋은 기본 층을 안 거쳤다** — 2번에서 그 범위(`<리뷰한 SHA>...<head>`)만 다시 리뷰한다.
   ⚠️ **이 대조는 기계적 게이트가 아니라 자기 신고다.** PR 본문의 SHA는 작성자가 고칠 수 있고,
   그 SHA에서 에이전트가 실제로 돌았다는 증거는 어디에도 남지 않는다(보호된 상태 체크도 봇 코멘트도
   없다). 두는 이유는 **조작을 막기 위해서가 아니라 빠뜨림을 잡기 위해서**다. 기계화하려면 리뷰
   결과를 PR 코멘트로 남기고 그 코멘트가 인용한 SHA를 대조해야 한다(미도입).
   ⚠️ **CodeRabbit 지적을 고쳐 푸시한 커밋이 정확히 여기 해당한다.** 옛 순서에서는 2번의 "수정 → 푸시 → 1번으로"
   루프가 그것을 다시 태웠는데, 에이전트를 앞으로 옮기면서 그 효과가 사라졌다 — 실제로 #95의 `a1b60a5`,
   #101의 `592d28f`·`d0ec216`이 어느 리뷰어도 안 본 채 머지됐다.
3. 3번이 `REVIEWED` **이고** 3b가 `CURRENT` — 또는 4번의 폴백 기록이 PR에 남아 있음

## 하지 말 것

- `CodeRabbit` 체크가 pass인 것을 근거로 "리뷰 통과"라고 말하지 않는다.
- `Review triggered` 응답만 보고 머지하지 않는다.
- `REVIEWED`만 보고 머지하지 않는다 — **3b가 `CURRENT`인지 확인한다.** 리뷰 뒤 푸시한 커밋은 리뷰되지 않았다.
- `RATE_LIMITED`를 보자마자 폴백으로 가지 않는다 — 재시도가 먼저다.
- 폴백 경로를 기록 없이 지나가지 않는다.
- **스타가 10개 이상이 되면** 자동 리뷰가 복귀한다. 그때 3번의 `NOT_TRIGGERED` 분기는 드물어지지만 할당량 축은 그대로 남으므로 이 스킬은 유효하다.
