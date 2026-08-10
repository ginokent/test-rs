# リポジトリと crate 群を testrs から gnrs-test へ改名する

- Priority: High
- Created: 2026-08-11 04:02 JST
- Model: Opus 5 (1M context)
- Branch: `feature/breaking-change-rename-to-gnrs-test`
- Status: **起票**。 未着手
- 起票経緯: ユーザー指示。 ginokent の自作 crate 群が `gnrs-*` prefix へ順次改名
  されており (`logrs` → `gnrs-log` / `httprs` → `gnrs-http` / `cryptors` →
  `gnrs-crypto` / `audiors` → `gnrs-audio` / `asyncrs` → `gnrs-async` /
  `examplers` → `gnrs-example` / `timers` → `gnrs-time`)、 本 repo も同じ命名体系へ
  揃える

## 要約

リポジトリ名 `testrs` を `gnrs-test` へ、 workspace の 5 crate の package 名を
`gnrs-test-*` へ改名する。

**facade crate は元から存在しない** (全 crate が `testrs-*` prefix) ため、
`gnrs-log` / `gnrs-time` で必要だった facade ディレクトリの `git mv` は不要
(ユーザー判断で facade の新設もしない)。 `crates/{core,pbt,fuzz,pbt-derive,bench}` は
いずれもディレクトリ名に旧名 prefix を含まないので移動しない (`crates/testrs` は
実測 **0 件**)。

## 命名の対応

| 対象 | before | after |
|---|---|---|
| GitHub repo | `ginokent/testrs` | `ginokent/gnrs-test` |
| package | `testrs-core` | `gnrs-test-core` |
| package | `testrs-pbt` | `gnrs-test-pbt` |
| package | `testrs-pbt-derive` | `gnrs-test-pbt-derive` |
| package | `testrs-fuzz` | `gnrs-test-fuzz` |
| package | `testrs-bench` | `gnrs-test-bench` |
| Rust ident | `testrs_pbt` 等 | `gnrs_test_pbt` 等 |
| **環境変数** | `TESTRS_PBT_SEED` | `GNRS_TEST_PBT_SEED` |
| **環境変数** | `TESTRS_FUZZ_SEED` | `GNRS_TEST_FUZZ_SEED` |
| repository URL | `https://github.com/ginokent/testrs` | `https://github.com/ginokent/gnrs-test` |

## 環境変数名も改名する判断とその根拠

`TESTRS_PBT_SEED` / `TESTRS_FUZZ_SEED` は **公開 API としてのインターフェース** である
(`crates/pbt/src/lib.rs:206` と `crates/fuzz/src/lib.rs:105` が `env::var` で読み、
失敗時のエラーメッセージ `[testrs-pbt] {name} FAILED at case #{attempt}
(TESTRS_PBT_SEED={seed}, ...)` にも出力され、 README にも再現手順として記載がある)。

**下流での使用状況を実測した結果、実行時に壊れるものは無い**:

- ginokent 配下 15 repo を `git grep -F 'TESTRS_'` で走査したところ、 ヒットは
  **すべてコメント / doc comment / issue の記述** だった
- **workflow の `env:` で設定している箇所は 0 件**、 コードで `env::var` を読む箇所も
  testrs 自身以外に **0 件**
- つまり改名しても下流の CI / test は壊れない。 影響は「下流 10 箇所以上のコメントが
  古くなる」ことだけ

以上を踏まえ、 global `~/.claude/CLAUDE.md` の設計方針「**後方互換性・fallback は
考慮不要。 セマンティクスのクリーンさを優先**」に従って **改名する** とユーザーが
判断した。 crate 名の prefix と環境変数の prefix が食い違う状態を残さない。

## 本 repo 固有の危険箇所 (先行事例の教訓の該当状況)

| 教訓 (出典) | 本 repo での実測 |
|---|---|
| **大文字始まり識別子の取りこぼし** (`gnrs-crypto` で `CryptorsTicketer` 28 箇所) | **該当あり**。 `TESTRS` **17 件** (環境変数名)、 `Testrs` **1 件** (`crates/pbt-derive/src/lib.rs:623` の `__TestrsPbtT`)。 いずれも小文字の `testrs` 置換では **変わらない** ため独立した段が必要 |
| 単独識別子 (`let testrs =`) | bare `testrs` は散文・URL・`repository` フィールドのみ。 変数バインディングとしての単独識別子は 0 件 |
| ファイル名 / ディレクトリ名 | `crates/testrs` **0 件**。 facade が無いためディレクトリ移動不要 |
| doc が参照する **ファイル名** | README 群の相互リンクは `[`testrs-pbt`](../pbt/README.md)` の形で、 **リンク先パスに旧名を含まない** ため改名の影響を受けない。 表示テキストのみ置換対象 |
| 旧名の**文字列長**のハードコード | 後述の段 3 で扱う `__TestrsPbtT` は **proc-macro が生成するコード片の文字列リテラル内** にあり、 長さ依存は無い。 固定長バッファとの比較も 0 件 |
| `Cargo.lock` の扱い | untracked (実測: `git ls-files -- Cargo.lock` の出力が空)。 commit 対象外 |

### 特に注意する 2 点

1. **`__TestrsPbtT` は proc-macro が生成するコードの内部型パラメータ名**
   (`crates/pbt-derive/src/lib.rs:623`:
   `"fn __testrs_pbt_assert_arbitrary<__TestrsPbtT: ::testrs_pbt::Arbitrary + ?Sized>() {}"`)。
   同じ文字列リテラル内の `__testrs_pbt_assert_arbitrary` と `::testrs_pbt::` は
   小文字なので段 5 で処理されるが、 **`__TestrsPbtT` だけは大文字始まりのため
   取りこぼす**。 段 3 を独立して置く
2. **`testrs_pbt_derive` / `testrs-pbt-derive` は `testrs_pbt` / `testrs-pbt` を
   部分文字列として含む**。 `-derive` 側を **先に** 置換しないと
   `gnrs_test_pbt_derive` ではなく `gnrs_test_pbt-derive` 相当の壊れた名前になる

## 置換手順 (段階順。 部分文字列を含む段を先に置く)

1. `TESTRS_PBT_SEED` → `GNRS_TEST_PBT_SEED` (環境変数)
2. `TESTRS_FUZZ_SEED` → `GNRS_TEST_FUZZ_SEED` (環境変数)
3. `__TestrsPbtT` → `__GnrsTestPbtT` (**大文字始まり**。 段 5 では変わらない)
4. `testrs_pbt_derive` → `gnrs_test_pbt_derive` (**段 5 より先**)
5. `testrs_pbt` → `gnrs_test_pbt` (Rust ident、 160 件で最多)
6. `testrs_core` → `gnrs_test_core`
7. `testrs_fuzz` → `gnrs_test_fuzz`
8. `testrs_bench` → `gnrs_test_bench`
9. `testrs-pbt-derive` → `gnrs-test-pbt-derive` (**段 10 より先**)
10. `testrs-pbt` → `gnrs-test-pbt` (package 名 / 散文 / エラーメッセージ prefix)
11. `testrs-core` → `gnrs-test-core`
12. `testrs-fuzz` → `gnrs-test-fuzz`
13. `testrs-bench` → `gnrs-test-bench`
14. `ginokent/testrs` → `ginokent/gnrs-test` (URL)
15. 残る bare `testrs` → `gnrs-test` (`repository` フィールド / 散文)

各段の実行後に残存件数を確認し、 段 15 の直前に bare の全件を目視する
(`gnrs-time` の改名で `path = "../timers"` を段から取りこぼしかけた教訓)。

**走査には `git grep` を使う**。 `rg -l --hidden` は `target/` 配下の探索が重く、
`gnrs-log` では 2 分でも終わらず timeout した実績がある。

## 除外対象

- `issues/completed/` と `issues/not-planned/` 配下 — 完了時点の事実を記録した archival
- 本 issue file — before / after 表と置換手順が旧名を必要とする

## 下流への波及 (極めて広範)

`testrs-pbt` はテスト基盤として広く使われており、 **ginokent 配下 15 repo・
計 75 個の `Cargo.toml`** が `testrs` を引いている (実測)。

| repo | `Cargo.toml` 数 |
|---|---|
| `quicrs` | 12 |
| `httprs` (現 `gnrs-http`) | 10 |
| `gnrs-gui` / `imagers` | 各 8 |
| `asyncrs` (現 `gnrs-async`) | 7 |
| `cryptors` (現 `gnrs-crypto`) / `gnrs-log` / `josers` / `oauthrs` | 各 5 |
| `cachers` / `timers` (現 `gnrs-time`) | 各 3 |
| `audiors` (現 `gnrs-audio`) | 2 |
| `examplers` (現 `gnrs-example`) / `nativers` | 各 1 |

**`Cargo.lock` が untracked な repo は CI がクリーンな状態から `branch` 指定の最新を
引くため、 本 repo の main merge と同時に即座に壊れる** (`gnrs-time` 改名時に
`gnrs-log` で実証済み: 旧 URL リダイレクトは効くが package 名が解決できず
`no matching package named` で失敗する)。

ユーザー判断で **主要 repo のみ本セッションで追従し、 残りは各 repo のエージェント
向け指示文を用意する** 方針とした。 対象 repo の選定は本改名の完了後に別途相談する。

## 完了条件

- [ ] 5 crate の package 名を `gnrs-test-*` へ変更する
- [ ] Rust 識別子 (`testrs_core` / `testrs_pbt` / `testrs_pbt_derive` / `testrs_fuzz` /
      `testrs_bench`) を `gnrs_test_*` へ更新する
- [ ] **環境変数名 `TESTRS_PBT_SEED` / `TESTRS_FUZZ_SEED` を `GNRS_TEST_*` へ更新する**
      (`env::var` の呼び出し / エラーメッセージ / README の再現手順すべて)
- [ ] **`__TestrsPbtT` を `__GnrsTestPbtT` へ更新する** (大文字始まりの取りこぼし対策)
- [ ] `repository` URL (`Cargo.toml:15`) と README 群の git 依存例を新 URL へ更新する
- [ ] 散文 (`CLAUDE.md` / `SPEC.md` / `README.md` / `CONTRIBUTING.md` / `deny.toml` /
      `.github/` / 各 crate の `README.md` と `description`) を `gnrs-test` 系へ更新する
- [ ] `git grep` で `testrs` の残存が除外対象のみであることを確認する
- [ ] CI 相当の 5 leg (fmt / clippy / doc / test / deny) が緑になる。 **`test` leg で
      proc-macro (`gnrs-test-pbt-derive`) が生成するコードがコンパイルできること**を
      段 3 / 段 4 の検証手段として明示的に確認する
- [ ] GitHub リポジトリ名を `gnrs-test` へ変更する (**ユーザーが GitHub UI で実施**)
- [ ] `git remote set-url` を新 URL へ更新し `git ls-remote` で疎通確認する
- [ ] 主要下流 repo の選定をユーザーと相談し、 対象 repo に追従 issue を起票する

## 非スコープ

- **facade crate `gnrs-test` の新設**: ユーザー判断。 元から facade が無く、 新設は
  改名とは別の設計変更になるため行わない
- **下流 15 repo すべての追従実装**: ユーザー判断で主要 repo のみ。 残りは指示文
- **ローカル作業ディレクトリ `~/go/src/github.com/ginokent/testrs` の改名**:
  リポジトリの成果物ではなく各開発環境の都合なので完了条件外
