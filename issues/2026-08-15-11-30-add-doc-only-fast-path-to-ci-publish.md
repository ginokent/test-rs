# ci-publish に doc-only fast path を導入する

- Priority: Medium
- Created: 2026-08-15 11:30 JST
- Model: Opus 5 (1M context)
- Branch: `feature/add-doc-only-fast-path`
- Status: **実装完了・CI 検証中**
- 起票経緯: ユーザー指示。 `gnrs-ml` で先行導入済みの仕組みを `gnrs-*` 系 20 repo へ展開する

## 目的

`origin/main` との差分が **doc だけ**なら、 検査を走らせず success を投影して終わる。
doc は build / test の入力ではないので、 その差分は **HEAD の非 doc tree が `origin/main` の
非 doc tree と 1 bit も違わない**ことを意味し、 検査結果をそのまま継承できる。
issue file 1 枚の PR に全 test を回すのを避けるのが目的。

## 導入したもの

| ファイル | 役割 |
|---|---|
| `scripts/doc-only-diff.sh` | 判定器。 **allowlist / fail closed**。 exit 0=doc only / 1=非 doc あり / 2=判定不能 |
| `scripts/doc-only-diff-test.sh` | 判定器の shell test (42 ケース)。 **判定より前に**実行 |
| `scripts/ci-publish-status-dangerously.sh` | fast path 挿入 + `CHECKS` 配列への統一 |
| `scripts/report-status-local.sh` | 第 3 引数 (description) 対応 |
| `CONTRIBUTING.md` | 動作手順の更新 + `⚠️ doc-only の fast path` 節 |
| `mise.toml` | `doc-only-diff-test` task + description の更新 |

doc とみなすのは **`issues/**` / `docs/**` / repo 直下の `*.md` のみ**。 それ以外
(`crates/**` / `src/**` / `Cargo.toml` / `Cargo.lock` / `scripts/**` / `mise.toml` /
`.github/**` / `deny.toml` / `.claude/**`) はすべて非 doc として全検査に倒れる。

## 安全弁 (4 つ)

1. **判定器の test を判定より前に実行** — 判定器が壊れて `scripts/**` を doc-only と誤判定
   すると、 その PR では test が 1 度も走らないまま投影されてしまう
2. **`git fetch origin main` で base を最新化** — 古い base だと `main` に入った code 修正が
   差分から消え、 判定が緩む方向に倒れる
3. **判定は必ず `if` で受ける** — `set -e` 下で裸に呼ぶと exit 1 (= 全検査が要る) で投影全体が
   落ちる。 **0 以外はすべて全検査に倒す**
4. description に **`success (local, doc-only: inherited from origin/main)`** を載せ、
   実測か継承かを GitHub 上で判別できるようにする (標準出力にも `NO CHECK WAS EXECUTED`)

## 先行 repo で確立した実装 (本 repo はその適用)

`gnrs-collection` (PR #20) と `gnrs-compress` で手順を確立した。 特に:

- **`report-status-local.sh` の第 3 引数対応が必要だった**。 移植元 (`gnrs-ml`) のみ
  `DESCRIPTION_OVERRIDE` を持ち、 他 repo は `$1` / `$2` だけ。 **そのまま渡すと黙って
  無視され、 GitHub 上に「inherited」が出ない** (実測か継承か区別できなくなる)
- **`CHECKS=("context|script")` を唯一の出典にした**。 context の列挙を 2 箇所に分けると、
  1 つ足したときに fast path 側が投影し忘れて **Required check が永久に pending になる**
  (branch protection は投影されない context を待ち続ける)
- **前提検査の fail open を修正した**。 移植元は `crates/` を直に grep していたため、
  `crates/` を持たない構成では grep がディレクトリ不在で失敗し `|| true` に握り潰されて
  「検査していないのに PASS」になる。 `git ls-files` ベースに変えて repo 構成に依存しない
  ようにした (`gnrs-compress` で両構成の動作を実証)

## 検証

- `bash -n` で構文 OK
- **`doc-only-diff-test.sh` 42 ケース PASS** (前提検査 `premise-md-not-a-build-input` 含む)
- `run_and_report` の羅列が **loop に完全置換** (残存 0)、 context 文字列の重複なし、
  loop 後の孤立コメントなし
- 本 repo に md/docs/issues を build 入力にする crate は **0 件**

## 完了条件

- [x] 判定器と test を導入する
- [x] `report-status-local.sh` に第 3 引数を追加する
- [x] `CHECKS` 配列を唯一の出典として fast path と通常経路を回す
- [x] `CONTRIBUTING.md` / `mise.toml` を更新する
- [ ] CI 相当の leg が緑になる
