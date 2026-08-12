## リポジトリの位置づけ (最上位)

本リポジトリ **gnrs-test** は Rust 向けテストツール群を収めるワークスペース
である。現在は **PBT**・**fuzzing**・**benchmarking** の 3 カテゴリを提供
する。共有基盤 `gnrs-test-core` の上に PBT 系 (`gnrs-test-pbt` / `gnrs-test-pbt-derive`)
と fuzzing 系 (`gnrs-test-fuzz`) が乗り、さらに `gnrs-test-core` にも依存しない
独立カテゴリとして benchmarking 系 (`gnrs-test-bench`) が並ぶ構成を採る。

- **gnrs-test** = テストツール群の傘 (ワークスペース / リポジトリ)。
- **PBT・fuzzing・benchmarking はそれぞれ別カテゴリ**である。各カテゴリは
  必要な共有基盤だけに依存する。PBT 系と fuzzing 系は `gnrs-test-core` を
  並行利用する兄弟関係にあり (`gnrs-test-fuzz` は `gnrs-test-core` のみに依存し、
  PBT ランナー `gnrs-test-pbt` には依存しない)、benchmarking 系 `gnrs-test-bench`
  は計測に Rng/Arbitrary を必要としないため **`gnrs-test-core` にも依存せず
  std のみで完結する独立カテゴリ**である。いずれも gnrs-test が持つ複数
  カテゴリの一つにすぎない。
- 今後これらとは異質なテストカテゴリ (例: コンパイル時テスト) を加える
  場合は、既存 crate の feature として押し込まず、**新しい兄弟 crate
  として並べて追加する**。テストカテゴリを crate 単位で分離するのが本
  リポジトリの拡張方針である。各カテゴリの crate が依存する共有基盤は
  最小限に留める (不要な共有基盤に依存させない)。

workspace 全体に効く制約 (後述の依存方針 / 安全性方針 / toolchain pin) は、
将来追加される crate にも等しく適用する。

## 大方針 (gnrs-test crate 群)

gnrs-test の各 crate は std とコンパイラ提供の `proc_macro` クレートのみで
動作する、プロパティベーステスト + fuzzing + benchmarking のための
ライブラリ群。本ドキュメントは大方針を記述する。詳細設計はコード内
コメントで管理する。

## 配布方針

- crates.io には **公開しない**。git dependency として参照される運用を前提とする。
- インストールは `git = "..."` 形式の dependency 指定で行う。
- 内部依存も crates.io 公開要件に縛られない。必要であれば依存先が
  git のみで配布されているクレートでも構わない (本クレート自体の
  no-deps 方針は維持)。
- `readme` / `keywords` / `categories` 等、crates.io ページ向けの
  メタデータ整備、および公開順序の運用ドキュメント等は対応しない。

## 依存方針

- 直接依存は **std とコンパイラ組み込みの `proc_macro` クレートのみ**。
- `syn` / `quote` / `proc-macro2` を含む外部 proc-macro 補助クレートも
  使わない (`gnrs-test-pbt-derive` は手書き parser で実装する)。

## 安全性方針

- ワークスペース全体で `unsafe_code = "forbid"` を強制する。
- 組み込み `block_on` executor も `std::pin::pin!` を使い unsafe ゼロで
  実装する。

## Toolchain pin

- `rust-toolchain.toml` で **stable 1.95** に pin する (rustfmt / clippy 同梱)。
- ローカルと CI の fmt / clippy / test / doc ジョブはすべてこの版で動かす。
- **MSRV は 1.82** (`PanicHookInfo` のため)。MSRV ジョブは `rustup default 1.82`
  で 1.82 に切り替え、`cargo test --workspace --all-targets` まで回す (直接依存・
  dev-dep ともにゼロのため build/check ではなく test で実挙動まで検証する、最も
  厳格な MSRV 保証)。

## ワークスペース構成

現在のワークスペースは 5 crate で構成される。新しいテストカテゴリは、この表に
兄弟 crate として追加していく。

### crate 命名とディレクトリ命名の規約

- **crate 名は `gnrs-test-` prefix で統一する** (2026-08-11、`testrs` からの改名時に
  確定)。リポジトリ名 `gnrs-test` と crate 名 prefix を一致させる
- **crate ディレクトリ名は package 名と一致させる** (2026-08-12 確定)。
  `crates/gnrs-test-pbt` の package 名は `gnrs-test-pbt`。ディレクトリ名から
  `Cargo.toml` を開かずに package 名が分かり、`cargo` のエラーメッセージや
  ビルドログに出る package 名とパスが一致する
  - **この規約は 2026-08-12 に方針を反転させたもの**。それ以前は「ディレクトリ階層で
    既に repo が特定されるため prefix を重複させない」(`crates/pbt` = `gnrs-test-pbt`)
    という規約だった。`gnrs-http` の `SPEC.ja.md` にも同じ旧規約が書かれているため、
    他 repo へ展開する際はそちらも書き換える
  - パスに repo 名が 2 回出る (`gnrs-test/crates/gnrs-test-pbt/`) 冗長さは、
    package 名との一致を優先して受け入れる
- Rust 識別子は `gnrs_test_*` (例: `gnrs_test_pbt` / `gnrs_test_core`)
- **adapter crate** (特定ライブラリへの束縛を担う crate) は
  `{リポジトリ名}-{機能名}-{機能を提供するライブラリ名}` とし、最終セグメントは
  **ライブラリ名をそのまま**置いて短縮しない (`gnrs-http` の `SPEC.ja.md:74-107` で
  2026-08-12 確定)。本 repo に adapter crate は現存しないが、将来追加する場合は
  この規約に従う

| クレート            | カテゴリ      | 依存       | 目的                                                            |
|---------------------|--------------|------------|-----------------------------------------------------------------|
| `gnrs-test-core`       | 共有         | std        | `Rng`, `XorShift64`, `Arbitrary` trait, `strategy::*` combinator |
| `gnrs-test-pbt-derive` | PBT          | proc_macro | `#[derive(Arbitrary)]` と `#[pbt]` proc-macro                    |
| `gnrs-test-pbt`        | PBT          | core+derive | テストランナー、assertion マクロ、regression shrinking          |
| `gnrs-test-fuzz`       | fuzzing      | core       | in-process mutation 駆動の fuzzer (`fuzz` + `fuzz_typed`)        |
| `gnrs-test-bench`      | benchmarking | std        | std のみ依存のマイクロベンチハーネス (`bench` + `bench_compare`) |

PBT を使う通常利用では `gnrs-test-pbt` のみで足りる (`gnrs-test-core` と
`gnrs-test-pbt-derive` の内容をすべて再エクスポートしている)。fuzzing 利用では
`gnrs-test-fuzz` を使う。なお `fuzz_typed` に独自型を渡す場合、`#[derive(Arbitrary)]`
の生成コードが PBT facade `gnrs-test-pbt` を参照するため `gnrs-test-pbt` も必要となる。
benchmarking 利用では `gnrs-test-bench` を使う。これは std のみに依存し、他の
gnrs-test crate には依存しない (統計関数の検証のためにのみ `gnrs-test-pbt` を
dev-dependency として用いる)。

## Lint / Doc 方針

- `cargo clippy --workspace --all-targets -- -D warnings` が clean であること。
- `cargo doc --workspace --no-deps` が `RUSTDOCFLAGS=-D warnings` で
  clean であること。
- CI に `doc` ジョブと MSRV (1.82) の `cargo build` ジョブを常設する。
