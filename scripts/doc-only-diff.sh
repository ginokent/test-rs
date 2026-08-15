#!/usr/bin/env bash
# scripts/doc-only-diff.sh — 2 つの commit の差分が **doc だけ**かを判定する。
#
# `ci-publish-status-dangerously` の fast path のための判定器である。 doc だけの
# 差分なら build / test の入力が base と 1 bit も違わないので、 base (= `origin/main`)
# の検査結果をそのまま継承できる。
#
# ```
# usage: scripts/doc-only-diff.sh [BASE] [HEAD]
#   BASE  既定 origin/main
#   HEAD  既定 HEAD
# ```
#
# exit code:
#   0  doc only        —— 検査を skip してよい
#   1  doc 以外を含む  —— 全検査が要る
#   2  判定不能        —— 引数不正 / ref 解決不可 / git 失敗
#
# **呼び出し側は 0 以外をすべて「全検査」に倒すこと** (2 を 0 と同じに扱うと
# 判定不能が skip になる)。
#
# # 判定の原則 —— fail closed
#
# 判定が緩むと **code の変更が 1 度も検査されないまま merge される**。したがって
# 本 script は allowlist 方式を採る。 **allowlist に載っていない path が 1 つでも
# あれば doc ではない**と判定する (denylist だと新種の path が黙って doc 側に落ちる)。
#
# doc とみなす path (これ以外はすべて非 doc):
#
# - `issues/**`
# - `docs/**`
# - repo 直下の `*.md` (`README.md` / `SPEC.md` / `CLAUDE.md` / `CONTRIBUTING.md` /
#   `init.md` など)。 **直下だけ**である。 `crates/gnrs-num/README.md` や
#   `.github/workflows/README.md` は非 doc として全検査に倒す
#
# `crates/**` / `Cargo.toml` / `Cargo.lock` / `scripts/**` / `mise.toml` /
# `.github/**` / `rust-toolchain.toml` / `deny.toml` / `.claude/**` は非 doc である。
# 列挙ではなく「allowlist の 3 つ以外」として落ちる。
#
# # 前提 (本 script は保証しない)
#
# 1. **BASE (= `origin/main`) が検査済みであること**。 main へ入る commit が必ず
#    `ci-publish-status-dangerously` を経ている運用が前提で、検査を通さず main へ
#    直接 push された commit があるとこの前提は崩れる。
# 2. **md が build / test の入力でないこと**。 `include_str!("../../docs/x.md")` の
#    ような形で md が crate に取り込まれると、 doc の変更が build 入力の変更になる。
#    2026-08-14 時点で `crates/**` に該当は無く、この前提は
#    `scripts/doc-only-diff-test.sh` が毎回 grep して固定している。
#
# # 実装上の落とし穴 (どれも実測で確認した)
#
# - **`--no-renames` は必須**。 rename 検出が効いていると `git diff --name-only` は
#   **移動先の path しか出さない**。 `crates/x/src/lib.rs` -> `docs/moved.md` の改名が
#   `docs/moved.md` 1 行になり、 **code の消滅が doc に見える**。 `--no-renames` を
#   付けると削除 + 追加の 2 行になり、削除側が非 doc として検出される。利用者の
#   `diff.renames = copies` 設定下でも `--no-renames` が優先されることは確認済み。
# - **`-z` は必須**。既定の `core.quotePath` は非 ASCII を `"docs/\346\227\245..."`
#   と quote して出すので、日本語や空白を含む path の parse が壊れる。 `-z` は
#   quote せず NUL 区切りで出す (改行入りの path も安全)。
# - **2-dot (`git diff BASE HEAD`) を使う。 3-dot にしないこと**。 3-dot は
#   merge-base との比較なので、 **main に入った code 修正を欠いた HEAD** を doc-only と
#   判定しうる。 2-dot は 2 つの tree の直接比較なので「HEAD の非 doc tree は
#   `origin/main` の非 doc tree と同一」という、継承の根拠そのものを直接示す。
#   この semantics は `scripts/doc-only-diff-test.sh` の `base-ahead-with-code` が固定する。
# - **submodule / symlink**: `docs` directory 自体が symlink や submodule に置き換わると
#   diff は `docs` (末尾 `/` 無し) を出すので allowlist に当たらず全検査に倒れる。
#   `docs/**` の中の symlink / submodule は doc 扱いになるが、それが build 入力になるには
#   `Cargo.toml` か `crates/**` の変更が要り、どちらも非 doc なのでその変更自体が
#   全検査を通る。
set -euo pipefail

if [[ $# -gt 2 ]]; then
  echo "error: too many arguments (expected at most 2)" >&2
  echo "usage: scripts/doc-only-diff.sh [BASE] [HEAD]" >&2
  exit 2
fi

BASE="${1:-origin/main}"
HEAD_REF="${2:-HEAD}"

for ref in "${BASE}" "${HEAD_REF}"; do
  if ! git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null; then
    echo "error: cannot resolve '${ref}' to a commit" >&2
    echo "hint: fetch the base branch first (e.g. 'git fetch origin main')" >&2
    exit 2
  fi
done

# doc とみなす path かを判定する。
#
# `*/*` の枝が肝である。 `issues/` `docs/` に当たらなかった **階層下の path はすべて**
# ここで非 doc に落ちるので、最後の `*.md` には **repo 直下の file しか来ない**。
# `docsx/y.md` や `issuesx/y.md` のような似た名前の directory も `*/*` で落ちる。
is_doc_path() {
  case "$1" in
  issues/*) return 0 ;;
  docs/*) return 0 ;;
  */*) return 1 ;;
  *.md) return 0 ;;
  *) return 1 ;;
  esac
}

# NUL 区切りの出力は変数に入れられない (command substitution が NUL を落とす) ので
# 一時 file を経由する。 pipe にすると while が subshell に入って集計が失われ、
# git 側の exit code も見えなくなる。
#
# macOS の `mktemp` は template 無しだと TMPDIR を無視するため template を明示する。
DIFF_LIST=$(mktemp "${TMPDIR:-/tmp}/doc-only-diff.XXXXXX")
trap 'rm -f "${DIFF_LIST}"' EXIT

if ! git diff --name-only -z --no-renames "${BASE}" "${HEAD_REF}" >"${DIFF_LIST}"; then
  echo "error: git diff failed for '${BASE}' '${HEAD_REF}'" >&2
  exit 2
fi

doc_count=0
non_doc_count=0

while IFS= read -r -d '' path; do
  if is_doc_path "${path}"; then
    doc_count=$((doc_count + 1))
    echo "doc-only-diff:     doc: ${path}"
  else
    non_doc_count=$((non_doc_count + 1))
    echo "doc-only-diff: NON-doc: ${path}"
  fi
done <"${DIFF_LIST}"

if [[ "${non_doc_count}" -gt 0 ]]; then
  echo "doc-only-diff: ${non_doc_count} non-doc path(s) changed between ${BASE} and ${HEAD_REF}; full checks are required"
  exit 1
fi

# **parse に失敗したときに fail open しないための番人**。出力があるのに 1 件も
# 読めなかった = NUL 区切りとして読めていない、ということなので判定不能に倒す。
#
# `-z` を落とす mutation を実験したところ、 `read -d ''` が NUL を見つけられずに
# 0 件と読み、下の「差分ゼロ」に落ちて **exit 0 (検査 skip) になった**。判定器が
# 壊れる向きとして最悪なのでここで塞ぐ。
if [[ "${doc_count}" -eq 0 && -s "${DIFF_LIST}" ]]; then
  echo "error: could not parse 'git diff --name-only -z' output as NUL-separated paths" >&2
  exit 2
fi

# 差分ゼロは「doc だけ違う」の極限である。 2-dot で空 = 2 つの tree が完全一致 =
# build / test の入力が 1 bit も違わない、なので継承の根拠は最も強い。 doc-only と
# 同じ扱い (exit 0) にするが、 log では区別する。
if [[ "${doc_count}" -eq 0 ]]; then
  echo "doc-only-diff: no differences between ${BASE} and ${HEAD_REF}"
  exit 0
fi

echo "doc-only-diff: all ${doc_count} changed path(s) are docs"
exit 0
