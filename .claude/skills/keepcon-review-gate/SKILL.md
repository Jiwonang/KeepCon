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
로컬 검증              ← bash tool/verify.sh   (Windows: tool\verify.cmd)
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
# 상한이 낮으면 그 리뷰를 놓쳐 창을 이르게 계산한다.
# PR당 API 왕복 **최소** 2회이고 `--paginate`는 응답 페이지마다 한 번씩 더 부른다 —
# 소요는 PR 수 × 페이지 수에 비례한다. 현 저장소(대부분 1페이지) 실측 20 PR = 25초,
# 40개 약 50초, 106개 2분 남짓. **중간에 끊지 마라** — 2분 타임아웃에 실제로 걸렸고,
# 창이 안 열린 줄 알고 끊으면 처음부터 다시 돈다.
#
# 실패를 삼키면 안 된다. 일부 PR 조회만 실패해도 나머지로 "마지막 리뷰"가 계산돼
# 창을 이르게 잡고, 그러면 트리거가 튕겨 슬롯을 버린다. 한 건이라도 실패하면 멈춘다.
# (전체를 서브셸로 감싸 exit이 사용자 셸을 닫지 않게 한다.)
(
  set -e -o pipefail   # set -e 가 없으면 아래 cut·sort 실패가 조용히 지나가
                       # 일부 PR이 빠진 채 창을 이르게 계산한다.
  nums=$(gh pr list --state all --limit 200 --json number --jq '.[].number') || { echo "PR 목록 조회 실패 — 트리거하지 마라"; exit 1; }

  sub=$(mktemp); cre=$(mktemp); upd=$(mktemp); raw=$(mktemp)
  trap 'rm -f "$sub" "$cre" "$upd" "$raw"' EXIT   # 중간 실패로 빠져나가도 남기지 않는다
  for n in $nums; do
    gh api --paginate "repos/Jiwonang/KeepCon/pulls/$n/reviews" --jq '.[] | select(.user.login=="coderabbitai[bot]") | select(.submitted_at != null) | .submitted_at' >> "$sub" || { echo "PR #$n 조회 실패 — 부분 결과로 계산하면 창을 이르게 잡는다. 트리거하지 마라"; exit 1; }
    # ⚠️ `reviews`만 보면 안 된다 — 3단계가 이미 경고하듯 리뷰 본문은 **일반 코멘트로도** 온다.
    #    2026-08-20 실측: #105의 마지막 리뷰가 comments에 10:06:26Z로 실렸는데 reviews에는
    #    07:41:38Z뿐이라, 이 스캔이 창을 **54분 이르게** 잡았다.
    #
    # ⚠️ 두 값을 `tee >(...)`로 가르지 마라. 프로세스 치환은 파이프라인의 대기·상태 전파
    #    **밖**이라 ①뒤의 `sort`가 기록보다 먼저 돌 수 있고 ②그 안의 실패가 `||`에 안 잡힌다.
    #    파일로 받아 성공을 확인한 뒤 순차로 가른다.
    gh api --paginate "repos/Jiwonang/KeepCon/issues/$n/comments" --jq '.[] | select(.user.login=="coderabbitai[bot]") | select(.body | test("Actionable comments posted|No actionable comments")) | "\(.created_at) \(.updated_at)"' > "$raw" || { echo "PR #$n 코멘트 조회 실패 — 트리거하지 마라"; exit 1; }
    cut -d' ' -f1 < "$raw" >> "$cre"
    cut -d' ' -f2 < "$raw" >> "$upd"
  done
  for f in "$sub" "$cre" "$upd"; do sort -o "$f" "$f"; done

  [ -s "$sub" ] || [ -s "$upd" ] || { echo "리뷰 0건 — 원인을 확인하기 전에는 트리거하지 마라"; exit 1; }
  printf 'reviews.submitted_at  최댓값: %s
' "$(tail -1 "$sub")"
  printf 'comments.created_at   최댓값: %s
' "$(tail -1 "$cre")"
  printf 'comments.updated_at   최댓값: %s  <- 창 계산에 쓰는 값
' "$(tail -1 "$upd")"
  last=$(printf '%s
%s
' "$(tail -1 "$sub")" "$(tail -1 "$upd")" | sort | tail -1)
  python -c "import sys,datetime as d;t=d.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00'))+d.timedelta(hours=1,minutes=2);print('마지막 리뷰',sys.argv[1],'→ 트리거 가능',t.strftime('%Y-%m-%dT%H:%M:%SZ'))" "$last"
)
```

> ⚠️ **`updated_at`이 항상 리뷰 시각인 것은 아니다 — 세 값이 벌어지면 사람이 판단하라.**
> CodeRabbit은 **머지 직전에 요약 코멘트를 편집**한다. #84 실측: 마지막 커밋이
> `2026-08-10T03:01:50Z`, 코멘트가 담은 리뷰 범위도 그 커밋 하나뿐인데 `updated_at`은
> `2026-08-11T05:51:55Z`(머지 21분 전)다 — 그 사이 커밋이 없으니 리뷰였을 수 없다.
> 스캔이 저장소 전체 최댓값을 쓰므로 **옛 PR 하나를 머지하는 것만으로** 창이 최대 27시간
> 밀려, 슬롯이 비어 있는데 트리거를 거부한다.
>
> 그렇다고 `created_at`으로 바꾸면 **역행한다** — 제자리 재리뷰(#105 +11분, #92 +26분)를
> 놓쳐 창을 이르게 잡는다. 그래서 위 스크립트는 세 후보를 **모두 찍는다.**
> `updated_at`이 나머지 둘보다 **한 시간 이상** 앞서 있으면 리뷰가 아니라 머지 편집일
> 공산이 크니, 그 값 대신 나머지 둘의 최댓값으로 계산하라. 관측된 실제 재리뷰는 전부
> 54초~26분 안에 들어온다. (자동 판별은 별도 PR — 후보의 head SHA로 커밋 시각을 조회해
> 하한을 잡는 3단계 해법이 있다.)
>
> ⚠️ **한도는 PR별이 아니라 계정 단위 공유 풀이다.** 이 계정의 실효 한도는 시간당 1건이며(봇이 리뷰 본문에 `Your plan provides up to 1 included review per hour`라고 적는다 — 플랜 상한인 Pro+ 시간당 10건이 아니라 fair-usage로 조여진 값이다), **저장소의 다른 PR이 같은 슬롯을 가져간다.**
>
> ⚠️ `@coderabbitai rate limit`이 알려주는 "N분 뒤"는 **조회 시점 기준의 근사치라 경계에서 진다.** 2026-08-19 실측: 안내받은 29분을 기다려 #101을 트리거했으나 창(07:30:01Z)이 열리기 **16초 전**이라 튕겼다. 실패한 트리거는 창을 앞당겨 주지도 않는다.
>
> ⚠️ **그런데 시간만 변수가 아니다 — 대기열도 변수다.** 같은 실측에서 #102는 창이 열리기 **78초 전**(07:28:43Z)에 트리거했는데 수락돼 07:32:36Z에 리뷰를 받았다. #101이 진 진짜 이유는 경계 오차가 아니라 **1분 2초 먼저 줄을 선 #102**다 — 시간 계산만으로는 못 이긴다. 그래서 아래 "다른 PR을 트리거하지 않는다"가 계산보다 중요하다.
>
> 그래서 **위 명령으로 계산한 시각 + 2분**에 트리거하고, 기다리는 동안 **다른 PR을 트리거하지 않는다**(같은 풀을 다툰다).

### 3b. 리뷰가 지금 head를 봤는지 확인 (필수)

`REVIEWED`는 "언젠가 리뷰됐다"는 뜻일 뿐이다. **CodeRabbit이 리뷰한 커밋과 현재 head를 비교한다.**

⚠️ **한쪽 API만 조회하고 끝내지 마라 — 판정이 실리는 자리가 갈린다.** 2026-08-24
실측(14건):

- `reviews`가 **0건**인 것은 #112·#113·#114·#115 넷. 이 중 #112·#114·#115는 지적이
  없어 **요약 코멘트를 계속 수정(edit)**해 마커 블록에 `No actionable comments were
  generated`를 채웠다. **#113은 다르다** — 마커는 있지만 판정 문구가 본문 어디에도
  없고(전수 검색 0건) `reviews`도 0건이다. §3 판정도 `RATE_LIMITED`다 — **이 PR은
  리뷰가 한 번도 안 됐다.** 그런데도 마커 블록의 `between <base> and <head>` 범위는
  head와 정확히 일치한다(`77ac5668`) — **sha 일치가 리뷰 완료를 증명하지 않는다는
  살아 있는 증거**다. 이 사실은 아래 판정 규칙에서 다시 쓴다.
- 마커 코멘트가 **아예 없고** `reviews`에만 결과가 있는 것은 #93·#95·#98·#101·#104·
  #110·#111 일곱 건 — 전부 지적을 낸 리뷰였다.
- **양쪽에 다 있는 것**도 있다: #92·#105는 마커에 `No actionable comments were
  generated`가, `reviews`에는 더 **이른** 지적 리뷰가 실렸다(#105는 이전에 "0건"으로
  잘못 기록됐다 — 실제로는 1건). #106도 마커가 있다.

⚠️ **"지적이 있으면 마커를 안 만든다"로 읽지 마라 — 갈리는 것은 sha가 아니라 판정 문구뿐이다.**
마커 블록의 커밋 범위는 지적 유무와 무관하게 **모든 리뷰 패스마다 갱신된다**(#106의 마커 sha가
그 시점 `reviews` 최신값보다 더 나중 커밋인 것으로 확인). 지적이 있으면 판정 문구가 `reviews`
쪽에 실리고 마커에는 범위만 남을 뿐이다. 그래서 **마커의 sha 단독은 증거가 아니다.**

**어느 한쪽만 보면 반드시 반대쪽 절반에서 진다.** 그러니 **둘 다 조회하고 어느 하나라도
head를 가리키면 `CURRENT`로 판정한다:**

```bash
# --- 1) comments의 요약 코멘트(recent_review 마커) ---
# ⚠️ `--paginate` 없으면 첫 30건만 본다 — 코멘트가 쌓인 PR에서 **최신 리뷰를 놓친다.**
# ⚠️ `recent_review_start`~`recent_review_end` 마커로 좁혀서 판정 문구·SHA를 뽑는다.
#    이 코멘트는 walkthrough(변경 요약)까지 한 몸에 담고 있고, walkthrough는 리뷰
#    트리거와 무관하게 항상 채워진다 — 마커 밖 텍스트로 판정하면 "리뷰 안 했는데도
#    코멘트가 있다"를 리뷰로 오판할 여지가 남는다. `between …` 커밋 범위도 리뷰가
#    끝나기 전 `Currently processing new changes in this PR` 안내에 실릴 수 있으니
#    범위만 보고 판정하지 않는다(2026-08-20 #106에서 그렇게 오판했다).
# ⚠️ 마커 코멘트가 없거나 판정 문구가 NONE인 것은 실패가 아니다 — 지적을 낸 리뷰는
#    이 코멘트를 아예 안 만들 수도 있고(위 실측 참조), 만들어도 판정 문구 없이 범위만
#    담을 수 있다(#113 — 리뷰가 안 됐는데도 sha는 head와 같다). verdict가 NONE이면
#    sha가 뭐든 증거로 세지 않는다. 여기서 NONE이 나와도 계속 진행해 2)를 반드시 확인한다.
# ⚠️ 시간으로 필터링하지 마라 — `created_at`도 `updated_at`도 아니고 **현재 본문**을
#    읽는다. CodeRabbit은 이 코멘트를 새로 달지 않고 계속 고쳐 쓴다: #114(코멘트 id
#    5389573222)는 01:07:58 생성 → 02:17:10 수정, #115(id 5390718611)는 04:25:58
#    생성 → 04:30:12 수정이었다. **트리거 이후 새로 생긴 코멘트만 찾는 즉흥 폴링**
#    (`select(.created_at > 트리거시각)`)은 이 편집을 영원히 못 본다 — 2026-08-24에
#    정확히 이 방식으로 정상 완료된 리뷰를 "빈 응답"으로 오판했다. 이 스킬 밖에서
#    직접 짠 감시 스크립트로 대신 판정하지 말고, 아래 명령을 그대로 실행해 현재
#    상태를 읽어라.
# ⚠️ `set -o pipefail` 없이 `if line=$(cmd | tail -1); then`을 쓰지 마라. 파이프라인
#    종료 코드는 마지막 명령(`tail`)의 것이라, `gh api`가 404·인증 만료·rate limit으로
#    실패해도 `tail -1`은 오류 JSON을 그대로 통과시켜 종료 코드 0을 낸다 — `then`
#    분기가 실행되고 아래 python이 `json.loads(...)['body']`에서 **`KeyError`로
#    죽는다**(직접 재현해 확인). `[ -z "$line" ]` 가드도 함께 둔다 — 매칭 코멘트가
#    아예 없을 때 `line`이 빈 문자열이라 `json.loads("")`가 **`JSONDecodeError`로
#    죽는다**(이것도 재현 확인).
if line=$(set -o pipefail
          gh api --paginate repos/Jiwonang/KeepCon/issues/<번호>/comments \
             --jq '.[] | select(.user.login=="coderabbitai[bot]")
                   | select(.body | test("recent_review_start"))
                   | {body}' \
           | tail -1)
then
  if [ -z "$line" ]; then
    echo "comments-marker verdict: NONE"
    echo "comments-marker sha:     NONE"
  else
    printf '%s' "$line" | python -c "
import sys, json, re
body = json.loads(sys.stdin.read())['body']
m = re.search(r'<!-- recent_review_start -->(.*?)<!-- recent_review_end -->', body, re.S)
block = m.group(1) if m else ''
verdict = re.search(r'Actionable comments posted: \d+|No actionable comments were generated', block)
sha = re.findall(r'between [0-9a-f]{40} and ([0-9a-f]{40})', block)
print('comments-marker verdict:', verdict.group(0) if verdict else 'NONE')
print('comments-marker sha:    ', sha[-1] if sha else 'NONE')
"
  fi
else
  echo "comments 조회 실패 — 판정 불가(빈 결과와 구분하라). NO_REVIEW로 읽지 마라(재트리거는 슬롯을 버린다)"
fi

# --- 2) reviews 객체 (comments가 NONE이어도 반드시 실행한다) ---
# PENDING 리뷰는 submitted_at이 없지만 commit_id는 있다 — 거르지 않으면 아직 제출되지
# 않은 리뷰의 커밋을 CURRENT 근거로 쓴다. 로그인 이름은 3단계(`coderabbitai`)와 달리
# 여기서는 `coderabbitai[bot]`이다 — REST와 GraphQL이 봇 계정을 다르게 표기한다.
# ⚠️ 본문이 **빈** 리뷰 객체도 제출된다 — 인라인 지적만 담고 요약은 아직 안 온 상태다
#    (#86: 04:26:51Z bodylen=0 → 04:28:03Z bodylen=3738, 같은 커밋. #111도 동형).
#    거르지 않으면 그 몇십 초 동안 "진행 중"이 CURRENT가 된다 — 아래 판정 규칙이
#    comments 경로에 대해 이미 금지한 바로 그것이다. **판정 문구로 거르지 마라** —
#    #104의 최종 요약은 `> [!CAUTION] Some comments are outside the diff`로 시작해
#    문구가 없고, 문구로 거르면 #104가 false STALE이 된다. **본문 길이로만 거른다.**
if rsha=$(set -o pipefail
          gh api --paginate repos/Jiwonang/KeepCon/pulls/<번호>/reviews \
            --jq '.[] | select(.user.login=="coderabbitai[bot]") | select(.submitted_at != null) | select((.body|length) > 0) | .commit_id' \
          | tail -1)
then echo "reviews commit_id:     ${rsha:-NONE}"
else echo "reviews 조회 실패 — 판정 불가(빈 결과와 구분하라)"
fi

echo "headRefOid:            $(gh pr view <번호> --json headRefOid --jq .headRefOid)"
```

> ⚠️ **본문을 `tail -1`로 그대로 자르지 마라 — 코멘트가 아니라 그 안의 마지막 줄만 남는다.**
> `.body`를 여러 줄 텍스트로 뽑아 `tail -1`을 걸면 (코멘트가 하나뿐이어도) 그 본문의
> 최종 줄(`<!-- tips_end -->` 등)만 남는다. 그래서 `{body}`로 감싸 **코멘트당 한 줄의
> JSON**으로 받고(`gh api --jq`는 결과를 한 줄씩 찍는다), `tail -1`은 그 줄 단위에서만
> "마지막 코멘트"를 고른 뒤 python의 `json.loads`로 통째로 복원한다.
>
> ⚠️ 이 python 블록의 출력 라벨은 영문으로 뒀다 — 이 저장소의 Windows Git Bash 환경에서
> 한글 `print()`가 콘솔 인코딩과 어긋나 깨진다(위 날짜 계산 스크립트도 같은 결함이 있다 —
> 값 자체는 맞지만 라벨이 깨진다. 별도 정리 대상).

**`CURRENT`는 두 소스 중 어느 한쪽이라도 head를 가리킬 때다 — ①`comments-marker verdict`가
`NONE`이 아니고 그 `sha`가 `headRefOid`와 같거나, ②본문이 빈 것을 거른 `reviews commit_id`가
`headRefOid`와 같을 때.** **판정 문구 없이 SHA만 같은 것은 증거가 아니다** — 리뷰가 아직
진행 중일 때도 `between <base> and <head>` 범위가 먼저 채워지고 판정 문구는 나중에 채워진다
(2026-08-20 #106에서 이 순서 때문에 "진행 중"을 "완료"로 오판했다). **#113이 이 규칙의
실증이다** — 마커 sha가 head(`77ac5668`)와 정확히 같은데 판정 문구는 본문 어디에도 없고
(전수 검색 0건), `reviews`는 0건이며, §3 판정은 `RATE_LIMITED`다. **리뷰가 한 번도 안 된
PR도 마커 sha는 head를 가리킬 수 있다** — sha 일치만으로 판정하면 미리뷰 PR이 그대로
통과한다.

`CURRENT`가 아닌 나머지는 **판정 문구를 동반한 증거가 하나라도 있었는가**로 가른다 —
`comments-marker verdict`가 `NONE`이 아니거나 본문 있는 `reviews`가 하나라도 있으면
`STALE`(리뷰는 됐고 head가 아닐 뿐), **둘 다 verdict가 없으면**(마커 sha만 있어도, #113처럼)
`NO_REVIEW`다. 마커 sha가 있다는 것 자체는 증거로 세지 않는다. `STALE`이면 **그 뒤 커밋은
리뷰되지 않았다** — `@coderabbitai review`로 재트리거한다. `CURRENT`일 때만 4층(CodeRabbit)이
채워진 것이다.

> ⚠️ **시각(timestamp)으로 비교하지 마라.** 리뷰 게시 시각과 `commits[].committedDate`를 견주는 방식은 틀린다 — `committedDate`는 푸시 시각이 아니라 **작성자 로컬 시계의 커밋 생성 시각**이다. 리뷰를 기다리는 몇 분 사이에 커밋해 두고 리뷰가 올라온 뒤 푸시하면(흔한 작업 흐름) 커밋이 리뷰보다 **이르게** 찍혀 `CURRENT`로 통과한다 — 3b가 막으려던 바로 그것이다. 작성자 시계가 앞서 있으면 반대로 늘 `STALE`이 되어 소음이 된다. SHA 비교는 시계·푸시 지연과 무관하다.

이 검사가 없으면 눈으로는 못 잡는다. 도입 시점에 돌려 보니 **PR #93·#95 둘 다 `STALE`이었고, #93은 그 상태로 머지됐다**(#93: 리뷰 커밋 `3568d64f` ≠ head `3ff2eb7d`). "리뷰 본문이 있는지"만 확인하는 규칙으로는 여기까지 못 간다.

**2026-08-24 #114·#115에서는 반대 방향의 실패가 났다.** `reviews`만 조회해 `NO_REVIEW`로
결론짓고 `comments`를 확인하지 않아, **정상 완료돼 지적 사항이 없던 리뷰를 "리뷰 안 됨"으로
오판했다**(머지 자체는 결과적으로 문제없었으나 기록이 틀렸고, PR에 정정 코멘트를 남겼다).
**여기서 처음에 "그러니 comments를 1차로 쓴다"로 순서만 뒤집었다가, `keepcon-code-reviewer`
에이전트가 `#93·#95·#98·#101·#104·#110·#111` 일곱 건(마커 코멘트가 없고 `reviews`에만
결과가 있는 PR)이 그 뒤집힌 순서에서 전부 `STALE`로 오판된다는 것을 실행 재현으로 잡아냈다**
— 처방이 실패의 방향만 바꾼 것이었다. 위 union(둘 다 조회하고 어느 하나라도 일치하면
`CURRENT`)이 그 반례들과 #114·#115를 모두 잡는다 — 반례 일곱 건(#98·#104·#111 →
`CURRENT`, #93·#95·#101·#110 → `STALE`)과 #114·#115를 합친 **아홉 건**을 재현했고,
#92·#105·#106·#112·#113까지 더한 **14건 전수**로도 판정이 일치한다.

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
- 대체 리뷰: `keepcon-code-reviewer` — 지적 N건 (🔴 a / 🟠 b / 🟡 c, + 🔵 d) · 형제 미고침 k건 / 미확인 m건
  (요약 줄은 **에이전트가 낸 그대로** 옮긴다 — 필드를 줄이면 남은 미고침·미확인이 기록에서 사라진다)
- 반영: `k=0 && m=0`일 때만 `전부 반영`이라고 적는다. 하나라도 남았으면 **무엇이 왜 남았는지**
  적는다 — 미고침·미확인을 세어 놓고 `전부 반영`으로 마무리하면 그 숫자가 장식이 된다
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
- **3b에서 `comments`·`reviews` 어느 한쪽만 보고 결론짓지 않는다** — 형식이 둘로 갈린다. `reviews`는 0건인데 `comments` 마커는 있는 PR(#114·#115)도, 마커는 없는데 `reviews`는 있는 PR(#93·#95·#98·#101·#104·#110·#111)도 실측으로 확인됐다. 둘 다 조회해서 어느 하나라도 head를 가리키면 `CURRENT`다.
- **`created_at` 기준으로 "새 코멘트가 있는가"를 즉흥으로 확인하지 않는다** — CodeRabbit은 요약 코멘트를 계속 수정한다. 현재 본문을 읽어라(위 3b 명령을 그대로 실행).
- `RATE_LIMITED`를 보자마자 폴백으로 가지 않는다 — 재시도가 먼저다.
- 폴백 경로를 기록 없이 지나가지 않는다.
- **스타가 10개 이상이 되면** 자동 리뷰가 복귀한다. 그때 3번의 `NOT_TRIGGERED` 분기는 드물어지지만 할당량 축은 그대로 남으므로 이 스킬은 유효하다.
