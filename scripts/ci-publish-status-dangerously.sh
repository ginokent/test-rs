#!/usr/bin/env bash
# scripts/ci-publish-status-dangerously.sh — push 済みの clean HEAD に対し、
# ci 相当の check を実行して結果を **CI と同名の context** で commit status
# として PR HEAD に投影する。
#
# ⚠️ 名前に `-dangerously` を含めているのは、本 task が GitHub Actions の CI
# signal を local が override できる構造であることを CLI レベルで明示する
# 意図 (npm `--force` 系の命名意図と同じ)。利用前に CONTRIBUTING.md の
# 「ci-publish-status-dangerously — コスト削減目的のユーザー責任設計」
# セクションを必ず読むこと。
#
# 設計判断 (詳細は CONTRIBUTING.md 参照):
# - context 名は **CI workflow の check 名と完全同名** で投げる。Branch
#   protection の Required check 設定値を local 1 回で満たせる = CI を発火
#   させずに merge が可能になる。GitHub Actions コスト削減が一義的目的。
# - check-runs API ではなく commit statuses API を使う理由: check-runs は
#   GitHub Apps 認証専用で PAT (`gh auth login` で得るもの) では作成不可。
#   commit statuses は PAT の `repo` scope で書き込み可能で、Branch
#   protection の Required としても check-runs と等価に扱える。詳細は
#   scripts/report-status-local.sh の冒頭コメント参照。
# - ⚠️ 裏返しのリスク: ローカル環境差 (OS / toolchain / cache / 環境変数)
#   で CI が落ちる check が local では緑になりうる。また gh api 直叩きで
#   任意 state を post 可能なので 「PR HEAD に緑」 = 「PR コードが緑」を
#   保証しない。第三者 contributor 環境では `local-ci: *` 等の prefix 戦略
#   への切替を検討すること。
# - 各 task は順次実行 (並列 status 投影で gh api の order 保証が崩れる
#   のを避ける目的)。`mise run ci` 側は並列実行で高速化する。
# - 各 task 単独の失敗で全体を止めず、5 task すべて実行した上で集約 status
#   を最後に決める (= 1 つ落ちた時に他の落ち位置も同時に分かる)。
# # ⚠️ doc-only の fast path —— **検査せずに投影する経路**
#
# `origin/main` との差分が **doc だけ**なら、検査を走らせずに success を投影して終わる。
# doc は build / test の入力ではないので、その差分は **`origin/main` の tree と非 doc 部分が
# 1 bit も違わない**ことを意味し、`origin/main` の検査結果をそのまま継承できる。issue file
# 1 枚の PR に全 test を回すのを避けるのが目的である。
#
# **前提**: main へ入る commit が必ず本 task を経ていること。検査を通さず main へ直接 push
# された commit があると「継承元が緑」という前提が崩れる。本 script はこれを検査しない
# (投影は PR HEAD の sha に載るので、merge commit の sha に事後に問い合わせる手段が無い)。
#
# 判定は `scripts/doc-only-diff.sh` に切り出してある (allowlist 方式 / fail closed)。
# その test (`scripts/doc-only-diff-test.sh`) を **判定より前に**走らせているのは、判定器が
# 壊れて `scripts/**` の変更を doc-only と誤判定した場合、その PR では test が 1 度も走らない
# まま投影されてしまうためである。
set -euo pipefail

# doc-only 判定の base。
#
# **古い `origin/main` で判定すると差分は小さくなる** (`main` に入った code 修正が見えなく
# なる) ので、下で必ず fetch し直す。「古いほど安全側」ではない。
BASE_REF="origin/main"

./scripts/preflight.sh

# gh CLI 存在チェック。
if ! command -v gh >/dev/null 2>&1; then
  cat >&2 <<'EOF'
error: gh CLI is not installed.
       ci-publish-status-dangerously requires `gh` to post commit statuses
       to GitHub.
       Install:        https://cli.github.com/
       Authenticate:   gh auth login
EOF
  exit 1
fi

# push 済み check: HEAD が remote 上に存在するか。
# git branch --remotes --contains <sha> が空でないことで判定する。
HEAD_SHA=$(git rev-parse HEAD)
if [[ -z "$(git branch --remotes --contains "${HEAD_SHA}" 2>/dev/null)" ]]; then
  cat >&2 <<EOF
error: HEAD (${HEAD_SHA}) is not present on any remote.
       Push the branch before running 'mise run ci-publish-status-dangerously'.
       (GitHub commit statuses are attached to commits known to the server;
       unpushed commits will trigger a 404 from the statuses API.)
EOF
  exit 1
fi

# 投影する context と、それを検査する script の対応。`context|script` 区切り。
#
# **doc-only の fast path と通常経路の両方がこれを唯一の出典にする**。context の列挙を
# 2 箇所に分けると、1 つ足したときに fast path 側が投影し忘れて **Required check が永久に
# pending になる** (branch protection は投影されない context を待ち続ける)。
#
# 以下は移設元の `run_and_report` 羅列に付いていたコメントである (呼び出しを loop に
# まとめた際に情報を失わないよう、ここへ移した)。
# context は CI workflow (.github/workflows/ci.yml) の各 job `name:` と完全
# 一致させる。Branch protection の Required check 設定と同期。
# MSRV は CI 専用 job のためここからは除外する (rust-toolchain.toml の pin
# とは別 toolchain が必要で、ローカルで毎回回すコストに見合わないため)。
# ローカル OS を問わず、Branch protection の Required check (Linux) を
# 満たすことを意図して `(ubuntu-latest)` 固定で投影する。macOS / Windows
# 上で実行しても context 名は ubuntu-latest になることに留意。
CHECKS=(
  "cargo fmt --check|./scripts/fmt.sh"
  "cargo clippy -D warnings|./scripts/clippy.sh"
  "cargo doc|./scripts/doc.sh"
  "cargo test (ubuntu-latest)|./scripts/test.sh"
  "cargo deny (license/bans/sources/advisories)|./scripts/deny.sh"
)

# **判定器を信じる前に、判定器の test を回す** (冒頭コメント参照)。cargo も要らず数秒で
# 終わる。落ちたら投影ごと止める。
./scripts/doc-only-diff-test.sh

# 判定の base を取り直す。offline 等で失敗しても投影は止めない。ref がそもそも無ければ
# 判定器が exit 2 を返して全検査に倒れる。
if ! git fetch --quiet origin main; then
  echo "warning: 'git fetch origin main' failed; falling back to the local ${BASE_REF} ref" >&2
fi

# **判定は必ず `if` で受ける**。`set -e` 下で裸に呼ぶと exit 1 (= 全検査が要る) で投影全体が
# 落ちてしまう。0 以外はすべて全検査に倒す。
if ./scripts/doc-only-diff.sh "${BASE_REF}" HEAD; then
  cat <<EOF
==> doc-only fast path: the diff against ${BASE_REF} touches documentation only.
    Build and test inputs are identical to ${BASE_REF}, so its results are inherited.
    NO CHECK WAS EXECUTED for this commit; the statuses below are inherited, not measured.
EOF
  for entry in "${CHECKS[@]}"; do
    ./scripts/report-status-local.sh "${entry%%|*}" success \
      "success (local, doc-only: inherited from ${BASE_REF})"
  done
  exit 0
fi

echo "==> non-doc changes detected; running all checks"

overall_status=0

run_and_report() {
  local context="$1"
  local script_path="$2"
  if "${script_path}"; then
    ./scripts/report-status-local.sh "${context}" success
  else
    overall_status=1
    ./scripts/report-status-local.sh "${context}" failure
  fi
}

# `CHECKS` (上部) を唯一の出典として順次実行する。context をここに再掲しないのは、
# fast path 側と二重管理になって投影漏れ (= Required check の永久 pending) を招くため。
for entry in "${CHECKS[@]}"; do
  run_and_report "${entry%%|*}" "${entry##*|}"
done

if [[ "${overall_status}" -ne 0 ]]; then
  echo "error: one or more checks failed (see commit statuses on the PR HEAD)" >&2
fi

exit "${overall_status}"
