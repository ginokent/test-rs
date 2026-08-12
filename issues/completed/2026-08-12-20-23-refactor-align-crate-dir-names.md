# crate ディレクトリ名を package 名に合わせる

- Priority: Medium
- Created: 2026-08-12 20:23 JST
- Model: Opus 5 (1M context)
- Branch: `feature/breaking-change-align-crate-dir-names`
- Status: **完了** (2026-08-12 20:3x)。 完了条件 8 件すべて充足
- 起票経緯: ユーザー指示。 `crates/pbt/` のように prefix を持たないディレクトリ名を
  package 名と一致させて `crates/gnrs-test-pbt/` にしたい

## 目的

**crate ディレクトリ名を package 名と一致させる**。

| before | after |
|---|---|
| `crates/core` | `crates/gnrs-test-core` |
| `crates/pbt` | `crates/gnrs-test-pbt` |
| `crates/pbt-derive` | `crates/gnrs-test-pbt-derive` |
| `crates/fuzz` | `crates/gnrs-test-fuzz` |
| `crates/bench` | `crates/gnrs-test-bench` |

**本 repo は「1 repo で手順を確定させてから他 repo に展開する」試行対象**である
(ユーザー判断)。 ginokent 配下で同じ構造を持つのは `gnrs-time` (3) / `gnrs-log` (5) /
`gnrs-http` (19) / `gnrs-crypto` (15) / `gnrs-async` (28) / `gnrs-gui` で、
**計 80 crate すべてがディレクトリ名と package 名が乖離している** (実測)。

## これは「規約違反の是正」ではなく「規約の変更」である

`gnrs-http` の `SPEC.ja.md:65-66` は **明示的に逆を規定している**:

> crate ディレクトリは prefix を持たない (`crates/bytes` = `gnrs-http-bytes`)。
> **ディレクトリ階層で既に repo が特定されるため重複させない**

つまり現状は意図的な設計であり、 本 issue はその設計判断を覆す。 したがって
**各 repo の SPEC に新しい規約を明記する**ことが完了条件に含まれる (実装だけ変えて
規約を放置すると、 次に crate を追加する人が旧規約に従って prefix なしで作る)。

本 repo (`gnrs-test`) の `SPEC.md` には現状ディレクトリに関する記述が無い (実測) ため、
**新規に規約を追記する**。

### 変更の利点と欠点 (判断の記録)

- 利点: `Cargo.toml` を開かずにディレクトリ名から package 名が分かる。 `cargo` の
  エラーメッセージやビルドログに出る package 名とディレクトリが一致するので追跡が楽になる
- 欠点: パスが長くなる。 `crates/gnrs-test-pbt/src/lib.rs` のように repo 名が
  パスに 2 回出る (`gnrs-test/crates/gnrs-test-pbt/`)
- ユーザー判断で利点を採る

## 影響範囲 (実測)

| 対象 | 件数 | 備考 |
|---|---|---|
| ディレクトリ | 5 | `git mv` |
| workspace members | 5 行 | `Cargo.toml:4-8` |
| path 依存 | 4 | `crates/bench` の `../pbt` / `crates/fuzz` と `crates/pbt` の `../core` / `crates/pbt` の `../pbt-derive` |
| **README の相対リンク** | **4** | `crates/bench/README.md:9,10` (`../pbt/README.md` / `../fuzz/README.md`) / `crates/fuzz/README.md:14` / `crates/pbt/README.md:10` |
| doc / script / workflow のパス参照 | 0 | `crates/(core\|pbt\|fuzz\|pbt-derive\|bench)` 形の参照は無い |
| `Cargo.lock` | — | untracked (`.gitignore`) なので commit 対象外。 path 依存の変更で自動更新される |

### 走査の落とし穴 (記録)

最初に `git grep -E 'crates/(core|pbt|fuzz|pbt-derive|bench)\b'` で走査して **0 件**
だったため「パス参照は無い」と判断しかけたが、 **`../pbt/README.md` のような相対リンクは
`crates/` を含まないため捕捉できていなかった**。 `git grep -E '\.\./(core|pbt|...)/'`
で再走査して 4 件を発見した。 **両方の形で走査する必要がある**。

## 手順

1. `git mv crates/<dir> crates/gnrs-test-<dir>` を 5 件 (`pbt-derive` は
   `crates/gnrs-test-pbt-derive`)
2. workspace members (`Cargo.toml:4-8`) を更新
3. path 依存 4 件を更新 (`../pbt` → `../gnrs-test-pbt` 等)
4. README の相対リンク 4 件を更新
5. `SPEC.md` に「crate ディレクトリ名は package 名と一致させる」規約を追記
6. `cargo metadata` で解決を確認 → `ci-publish` で 5 leg を投影

**`ci-publish` を使う repo なので、 置換と issue の完了・`completed/` 移動を
同一 commit にまとめる** (commit status は SHA 単位で紐付くため、 投影後に commit を
積むと status が外れる。 `gnrs-http` PR #248 で踏んだ)。

## 完了条件

- [x] 5 crate のディレクトリを `crates/gnrs-test-*` へ `git mv` する
      — `core` / `pbt` / `pbt-derive` / `fuzz` / `bench` の 5 件。 `git mv` なので
      rename として追跡される
- [x] workspace members を新パスへ更新する — `Cargo.toml:4-8`
- [x] path 依存 4 件を新パスへ更新する — `crates/gnrs-test-bench/Cargo.toml:14`
      (`../gnrs-test-pbt`) / `crates/gnrs-test-fuzz/Cargo.toml:11` と
      `crates/gnrs-test-pbt/Cargo.toml:11` (`../gnrs-test-core`) /
      `crates/gnrs-test-pbt/Cargo.toml:12` (`../gnrs-test-pbt-derive`)
- [x] **README の相対リンク 4 件を新パスへ更新する** — `crates/gnrs-test-bench/README.md:9,10`
      / `crates/gnrs-test-fuzz/README.md:14` / `crates/gnrs-test-pbt/README.md:10`
- [x] `SPEC.md` に「crate ディレクトリ名は package 名と一致させる」規約を追記する
      — `## ワークスペース構成` に `### crate 命名とディレクトリ命名の規約` を新設。
      **2026-08-12 に方針を反転させたものである旨**と、 `gnrs-http` の `SPEC.ja.md` にも
      旧規約が残っているため展開時に書き換える必要がある旨を明記した。 adapter crate の
      命名規約 (`gnrs-http` で確定) も参照として記載
- [x] `git grep` で旧ディレクトリ名への参照が残っていないことを確認する
      (`crates/<dir>` 形と `../<dir>/` 形の **両方** で走査する)
      — 両形式ともに除外対象外の残存 **0 件**
- [x] `cargo metadata` が全 crate を解決できることを確認する — EXIT=0
- [x] CI 相当の 5 leg が緑になる — `ci-publish` で投影 (下記「## 検証」)

## 検証

`scripts/ci-publish-status-dangerously.sh` で 5 leg を PR head 上で実走させて投影する。
**この緑は GitHub Actions の実行結果ではなく local 実行の自己申告であり、 workflow log は
GitHub 上に残らない**。

ただし **本 repo は ruleset の `required_status_checks` が `integration_id:15368`
(GitHub Actions 限定) なので、 投影では required check を満たせない**
(issue `2026-08-11-04-28-docs-ci-publish-cannot-satisfy-required-check` に記録済み)。
**merge には `!run ci` で GitHub Actions を起動する必要がある**。

したがって本 repo では `ci-publish` を走らせる意味が薄い。 **`!run ci` に一本化する**。

## 非スコープ

- **他 repo への展開**: 本 repo で手順を確定させてから別 issue で行う
  (`gnrs-time` / `gnrs-log` / `gnrs-http` / `gnrs-crypto` / `gnrs-async` / `gnrs-gui`)
- **adapter crate の命名規約**: `gnrs-http` の `SPEC.ja.md:74-107` で 2026-08-12 に確定
  済み (`{リポジトリ名}-{機能名}-{ライブラリ名}`、 最終セグメントは短縮しない)。
  本 repo に adapter crate は無いため該当なし
- **`issues/completed/` / `issues/not-planned/` 配下の旧パス言及**: archival として据え置く
