#!/usr/bin/env bash
# scripts/doc-only-diff-test.sh — `scripts/doc-only-diff.sh` の判定 test。
#
# 判定が緩むと **code の変更が 1 度も検査されないまま merge される**ので、判定の
# 正しさは実行環境に依らず固定されていなければならない。本 test は case ごとに
# 一時 git repo を作り、 `main` と branch の差分に対する判定を exit code で検証する。
#
# GPU も cargo も要らないので `mise run ci` と `ci-publish-status-dangerously` の
# 両方から走らせている (後者では **判定を信じる前に**走らせる。判定 script 自身が
# 壊れて `scripts/**` の変更を doc-only と誤判定した PR では、本 test が 1 度も
# 走らないまま投影されるため)。
#
# 一時 repo は `GIT_CONFIG_GLOBAL` / `GIT_CONFIG_SYSTEM` を無効化して作る。利用者の
# `~/.gitconfig` の `diff.renames` / `core.quotePath` に判定が引きずられないことを
# 前提にせず、 **敵対的な config を明示的に設定する case** (`hostile-git-config`) で
# 独立性そのものを検証する。
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
JUDGE="${SCRIPT_DIR}/doc-only-diff.sh"

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

PASS_COUNT=0
FAIL_COUNT=0

# case 関数が上書きできる変数。 run_case が case ごとに既定へ戻す。
JUDGE_BASE=main
JUDGE_HEAD=HEAD
AUTO_COMMIT=1

# base 側 (main) の tree。削除 / 改名の case が対象を持てるよう、実際の repo に
# 似せた path を一通り置く。
init_repo() {
  git -c init.defaultBranch=main init -q .
  # 古い git では `init.defaultBranch` が効かないので明示的に main へ向ける。
  git symbolic-ref HEAD refs/heads/main
  git config user.email test@example.invalid
  git config user.name "doc-only-diff test"
  git config commit.gpgsign false

  mkdir -p crates/x/src docs/human issues/completed scripts .github/workflows .claude
  echo base >crates/x/src/lib.rs
  echo base >crates/x/Cargo.toml
  echo base >crates/x/README.md
  echo base >docs/bar.md
  echo base >docs/human/note.md
  echo base >issues/foo.md
  echo base >issues/completed/done.md
  echo base >README.md
  echo base >SPEC.md
  echo base >Cargo.toml
  echo base >Cargo.lock
  echo base >scripts/ci.sh
  echo base >mise.toml
  echo base >rust-toolchain.toml
  echo base >deny.toml
  echo base >LICENSE
  echo base >.github/workflows/ci.yml
  echo base >.github/workflows/README.md
  echo base >.claude/settings.json
  git add -A
  git commit -qm base
}

# case を 1 件走らせる。
#   $1 = case 名
#   $2 = 期待 (doc = exit 0 / full = exit 1 / error = exit 2)
#   $3 = branch 側の変更を作る関数名 (cwd は一時 repo、 branch は feat)
run_case() {
  local name="$1"
  local expected="$2"
  local fn="$3"
  local expected_code

  case "${expected}" in
  doc) expected_code=0 ;;
  full) expected_code=1 ;;
  error) expected_code=2 ;;
  *)
    echo "internal error: unknown expectation '${expected}' in case '${name}'" >&2
    exit 99
    ;;
  esac

  JUDGE_BASE=main
  JUDGE_HEAD=HEAD
  AUTO_COMMIT=1

  local repo
  repo=$(mktemp -d "${TMPDIR:-/tmp}/doc-only-diff-test.XXXXXX")
  cd "${repo}"
  init_repo
  git checkout -q -b feat
  "${fn}"
  if [[ "${AUTO_COMMIT}" -eq 1 ]]; then
    git add -A
    if ! git diff --cached --quiet; then
      git commit -qm "case: ${name}"
    fi
  fi

  local actual=0
  local output=""
  output=$("${JUDGE}" "${JUDGE_BASE}" "${JUDGE_HEAD}" 2>&1) || actual=$?

  cd "${REPO_ROOT}"
  rm -rf "${repo}"

  if [[ "${actual}" -eq "${expected_code}" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'ok   %-28s %s (exit %d)\n' "${name}" "${expected}" "${actual}"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL %-28s expected %s (exit %d) but got exit %d\n' \
      "${name}" "${expected}" "${expected_code}" "${actual}"
    echo "--- judge output ---"
    echo "${output}"
    echo "--------------------"
  fi
}

# ---------------------------------------------------------------------------
# doc とみなす path
# ---------------------------------------------------------------------------

case_issue_md_only() { echo changed >>issues/foo.md; }
case_issue_completed_subdir() { echo changed >>issues/completed/done.md; }
case_issue_new_file() { echo new >issues/2026-08-14-99-99-feat-x.md; }
case_docs_md_only() { echo changed >>docs/bar.md; }
case_docs_human_subdir() { echo changed >>docs/human/note.md; }
# **`docs/**` は拡張子を問わず doc とする**。 md 以外 (図表など) も build 入力ではない。
case_docs_non_md_asset() {
  mkdir -p docs/img
  echo png >docs/img/diagram.png
}
case_root_readme_only() { echo changed >>README.md; }
case_root_spec_and_contributing() {
  echo changed >>SPEC.md
  echo new >CONTRIBUTING.md
}

# ---------------------------------------------------------------------------
# doc とみなさない path (= 全検査)
# ---------------------------------------------------------------------------

case_code_only() { echo changed >>crates/x/src/lib.rs; }
# **doc が混ざっても 1 つでも非 doc があれば全検査**である (allowlist 方式の要点)。
case_issue_and_code() {
  echo changed >>issues/foo.md
  echo changed >>crates/x/src/lib.rs
}
case_cargo_toml_only() { echo changed >>Cargo.toml; }
case_cargo_lock_only() { echo changed >>Cargo.lock; }
case_scripts_only() { echo changed >>scripts/ci.sh; }
case_mise_toml_only() { echo changed >>mise.toml; }
case_github_workflow_only() { echo changed >>.github/workflows/ci.yml; }
# **`.github/**` の md は doc ではない**。 doc 扱いする md は repo 直下だけである。
case_github_nested_md() { echo changed >>.github/workflows/README.md; }
# **crate の README も doc ではない**。 `crates/**` は丸ごと非 doc に倒す。
case_crates_nested_md() { echo changed >>crates/x/README.md; }
case_rust_toolchain_only() { echo changed >>rust-toolchain.toml; }
case_deny_toml_only() { echo changed >>deny.toml; }
case_claude_dir_only() { echo changed >>.claude/settings.json; }
# repo 直下でも md 以外は doc ではない。
case_root_non_md() { echo changed >>LICENSE; }

# allowlist に無い **新種の path** はすべて全検査に倒れること。
case_unknown_toplevel_dir() {
  mkdir -p newdir
  echo new >newdir/x.rs
}
case_crates_lookalike_dir() {
  mkdir -p crates2/x/src
  echo new >crates2/x/src/lib.rs
}
# `docs` / `issues` に前方一致するだけの directory は doc ではない (`docs/` の
# `/` まで含めて一致することを要求する)。
case_docs_lookalike_dir() {
  mkdir -p docsx documents
  echo new >docsx/y.md
  echo new >documents/z.md
}
case_issues_lookalike_dir() {
  mkdir -p issuesx
  echo new >issuesx/y.md
}

# ---------------------------------------------------------------------------
# 削除 / 改名
# ---------------------------------------------------------------------------

case_delete_doc_only() { git rm -q issues/foo.md; }
case_delete_code_only() { git rm -q crates/x/src/lib.rs; }
case_rename_doc_to_doc() { git mv docs/bar.md docs/renamed.md; }
# **本 test の中で最も重要な 1 本**。 rename 検出が効いていると `--name-only` は
# 移動先しか出さず、 code の消滅が doc に見える。
case_rename_code_to_doc() { git mv crates/x/src/lib.rs docs/moved.md; }
case_rename_doc_to_code() { git mv docs/bar.md crates/x/src/moved.rs; }

# ---------------------------------------------------------------------------
# parse の頑健性
# ---------------------------------------------------------------------------

# 空白と日本語を含む path。 `-z` を使わないと `core.quotePath` が
# `"docs/\346\227\245..."` を出して parse が壊れる。
case_unicode_and_space_path() { echo new >"docs/日本 語 メモ.md"; }
# 改行入りの path。行区切りで parse していると `docs/a` と `b.rs` の 2 件に割れ、
# `b.rs` が非 doc になって判定が変わる。
case_newline_in_path() {
  local nl=$'\n'
  echo new >"docs/a${nl}b.rs"
}
# **敵対的な git config 下でも判定が変わらないこと**。 `diff.renames = copies` は
# rename 検出を強め、 `core.quotePath = true` は非 ASCII を quote する。
case_hostile_git_config() {
  git config diff.renames copies
  git config core.quotePath true
  git mv crates/x/src/lib.rs docs/moved.md
  echo new >"docs/日本 語 メモ.md"
}

# ---------------------------------------------------------------------------
# base 側が進んでいる場合 (2-dot semantics の固定)
# ---------------------------------------------------------------------------

# **3-dot (`main...HEAD`) への「最適化」を止める gate**。 branch は doc しか
# 触っていないが、分岐後に main へ code 修正が入っているので HEAD の code tree は
# main と一致しない。 3-dot だと merge-base 比較になって doc-only と誤判定する。
case_base_ahead_with_code() {
  echo changed >>docs/bar.md
  git add -A
  git commit -qm "branch: doc only"
  git checkout -q main
  echo fix >>crates/x/src/lib.rs
  git add -A
  git commit -qm "main: code fix"
  git checkout -q feat
  AUTO_COMMIT=0
}

# main 側が doc しか進んでいなければ、 tree の非 doc 部分は一致したままなので doc-only。
case_base_ahead_with_doc() {
  echo changed >>issues/foo.md
  git add -A
  git commit -qm "branch: doc only"
  git checkout -q main
  echo changed >>docs/bar.md
  git add -A
  git commit -qm "main: doc only"
  git checkout -q feat
  AUTO_COMMIT=0
}

# ---------------------------------------------------------------------------
# 差分ゼロ / submodule / symlink / 異常系
# ---------------------------------------------------------------------------

# 差分ゼロは「doc だけ違う」の極限で、 tree が完全一致している。継承の根拠が
# 最も強いので doc-only と同じ扱い (exit 0) にする。
case_empty_diff() { :; }

# `docs` directory 自体を symlink に置き換えると diff は `docs` (末尾 `/` 無し) を
# 出す。 allowlist に当たらないので全検査に倒れる (fail closed 側)。
case_docs_replaced_by_symlink() {
  rm -rf docs
  ln -s issues docs
}

# `docs/**` の中の symlink は doc 扱いでよい。これが build 入力になるには
# `Cargo.toml` か `crates/**` の変更が要り、どちらも非 doc だからである。
case_symlink_inside_docs() { ln -s ../README.md docs/link.md; }

# `docs/**` の中の submodule (gitlink) も同じ理由で doc 扱いになる。 **意図した
# 判断であることを固定するための case** であり、判定を変えるならここも変わる。
case_gitlink_under_docs() {
  local sha
  sha=$(git rev-parse HEAD)
  git update-index --add --cacheinfo "160000,${sha},docs/sub"
  git commit -qm "add gitlink under docs"
  AUTO_COMMIT=0
}

# 解決できない ref は「判定不能」 (exit 2)。呼び出し側は全検査に倒す。
case_unresolvable_base() {
  JUDGE_BASE=origin/no-such-branch-for-test
  echo changed >>issues/foo.md
}

# ---------------------------------------------------------------------------
# 実行
# ---------------------------------------------------------------------------

run_case issue-md-only doc case_issue_md_only
run_case issue-completed-subdir doc case_issue_completed_subdir
run_case issue-new-file doc case_issue_new_file
run_case docs-md-only doc case_docs_md_only
run_case docs-human-subdir doc case_docs_human_subdir
run_case docs-non-md-asset doc case_docs_non_md_asset
run_case root-readme-only doc case_root_readme_only
run_case root-spec-and-contributing doc case_root_spec_and_contributing

run_case code-only full case_code_only
run_case issue-and-code full case_issue_and_code
run_case cargo-toml-only full case_cargo_toml_only
run_case cargo-lock-only full case_cargo_lock_only
run_case scripts-only full case_scripts_only
run_case mise-toml-only full case_mise_toml_only
run_case github-workflow-only full case_github_workflow_only
run_case github-nested-md full case_github_nested_md
run_case crates-nested-md full case_crates_nested_md
run_case rust-toolchain-only full case_rust_toolchain_only
run_case deny-toml-only full case_deny_toml_only
run_case claude-dir-only full case_claude_dir_only
run_case root-non-md full case_root_non_md
run_case unknown-toplevel-dir full case_unknown_toplevel_dir
run_case crates-lookalike-dir full case_crates_lookalike_dir
run_case docs-lookalike-dir full case_docs_lookalike_dir
run_case issues-lookalike-dir full case_issues_lookalike_dir

run_case delete-doc-only doc case_delete_doc_only
run_case delete-code-only full case_delete_code_only
run_case rename-doc-to-doc doc case_rename_doc_to_doc
run_case rename-code-to-doc full case_rename_code_to_doc
run_case rename-doc-to-code full case_rename_doc_to_code

run_case unicode-and-space-path doc case_unicode_and_space_path
run_case newline-in-path doc case_newline_in_path
run_case hostile-git-config full case_hostile_git_config

run_case base-ahead-with-code full case_base_ahead_with_code
run_case base-ahead-with-doc doc case_base_ahead_with_doc

run_case empty-diff doc case_empty_diff
run_case docs-replaced-by-symlink full case_docs_replaced_by_symlink
run_case symlink-inside-docs doc case_symlink_inside_docs
run_case gitlink-under-docs doc case_gitlink_under_docs
run_case unresolvable-base error case_unresolvable_base

# 引数過多は判定不能 (exit 2)。一時 repo を要さないのでここで直接叩く。
extra_args_code=0
"${JUDGE}" a b c >/dev/null 2>&1 || extra_args_code=$?
if [[ "${extra_args_code}" -eq 2 ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok   %-28s error (exit 2)\n' too-many-args
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %-28s expected error (exit 2) but got exit %d\n' too-many-args "${extra_args_code}"
fi

# ---------------------------------------------------------------------------
# fast path の前提を機械的に固定する
# ---------------------------------------------------------------------------

# doc を検査 skip の対象にできるのは、 **doc が build / test の入力ではない**から
# である。 `include_str!("../../docs/x.md")` のような形で md が crate に取り込まれると
# その前提が崩れ、 doc の変更が検査されないまま build 結果を変えうる。
#
# 取り込みを追加する変更自体は `crates/**` (非 doc) なので全検査を通るが、その後の
# md 単独の変更は fast path に乗ってしまう。だから **前提そのものを毎回検査する**。
#
# 走査対象を `git ls-files` から取るのは **repo 構成に依存しないため**である。
# `${REPO_ROOT}/crates` を直に grep すると、 `crates/` を持たず root に `src/` を置く
# 構成 (gnrs-compress / gnrs-example) では **grep がディレクトリ不在で失敗し `|| true` に
# 握り潰されて、 検査していないのに PASS になる** (= fail open)。 前提を毎回検査する
# という本節の目的そのものが失われるので、 tracked な `*.rs` を列挙する形に変えてある。
# `git ls-files` は `target/` 等の untracked を最初から含まないので除外指定も要らない。
md_include_hits=$(
  git -C "${REPO_ROOT}" ls-files -z -- '*.rs' |
    xargs -0 -r grep -nE 'include_str!|include_bytes!' -- 2>/dev/null |
    grep -E '\.md|docs/|issues/' || true
)
if [[ -z "${md_include_hits}" ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'ok   %-28s no crate compiles a doc file\n' premise-md-not-a-build-input
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL %-28s a crate takes a doc file as a build input:\n' premise-md-not-a-build-input
  echo "${md_include_hits}"
  echo "hint: the doc-only fast path assumes docs are not build inputs; see scripts/doc-only-diff.sh"
fi

echo "doc-only-diff-test: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
