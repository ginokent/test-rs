# CI の msrv job が rust-toolchain.toml に上書きされ MSRV を検証していないのを直す

- Priority: High
- Created: 2026-08-11 04:32 JST
- Model: Opus 5 (1M context)
- Branch: (TBD)
- Status: **起票**。 未着手
- 起票経緯: 改名 issue `2026-08-11-04-02-refactor-rename-to-gnrs-test` の PR #39 で
  `!run ci` により GitHub Actions を起動した際、 MSRV job の `Show versions` 出力から
  **1.82 ではなく 1.95 で test していること** が判明した

## 実測で確定した事実 (疑いではない)

run `31424353946` の MSRV job (id `93572445279`) のログ:

```
MSRV (1.82) cargo test | Install Rust 1.82 | info: syncing channel updates for 1.82-x86_64-unknown-linux-gnu
MSRV (1.82) cargo test | Install Rust 1.82 | 1.82-x86_64-unknown-linux-gnu installed - rustc 1.82.0 (f6e511eec 2024-10-15)
MSRV (1.82) cargo test | Show versions     | ##[group]Run rustup show active-toolchain
MSRV (1.82) cargo test | Show versions     | info: syncing channel updates for 1.95-x86_64-unknown-linux-gnu
MSRV (1.82) cargo test | Show versions     | cargo 1.95.0 (f2d3ce0bd 2026-03-21)
MSRV (1.82) cargo test | Show versions     | rustc 1.95.0 (59807616e 2026-04-14)
```

- `rustup toolchain install 1.82` は成功している (`rustc 1.82.0` を install)
- `rustup default 1.82` も実行されている
- **しかし `rustup show active-toolchain` は 1.95 を同期し、 `cargo --version` /
  `rustc --version` はいずれも 1.95.0 を報告している**
- 続く `cargo test --workspace --all-targets` も同じ shell で走るため **1.95 で
  test している**

## 原因

rustup は **`rust-toolchain.toml` (directory override) を `rustup default` より優先する**。
`rust-toolchain.toml` が `channel = "1.95"` を宣言しているため、 リポジトリ内で
`cargo` / `rustc` を起動すると常に 1.95 が選ばれる。

`rustup default` は「override が無いときの既定値」を変えるだけなので、 directory
override がある状況では効果を持たない。

## 影響

**MSRV 1.82 の宣言が CI で一切検証されていない。** 1.82 で壊れるコード (1.83+ で
安定化した API の使用など) が入っても CI は緑になる。 MSRV job が存在することで
「検証されている」と誤認させる点が特に危険。

本 repo は **ginokent 配下の多数の repo から dev-dependency として引かれている**
(`gnrs-test-pbt` はテスト基盤として 15 repo が参照)。 下流の MSRV 宣言は本 repo の
MSRV を下限として決まっているため、 **本 repo の MSRV が実は壊れていた場合、 下流の
MSRV job も連鎖して意味を失う**。

## 同じ問題が他 repo にもある

`gnrs-time` (旧 timers) の `.github/workflows/ci.yml:256-259` も同一のパターン
(`rustup toolchain install 1.82` + `rustup default 1.82`) を使っている。 同 repo には
**疑い** の段階で issue `2026-08-11-03-48-ci-msrv-job-may-not-verify-msrv` を起票済みで、
**本 repo の CI ログがその疑いを確定させる根拠になる**。 是正時に相互参照すること。

他にも `msrv` job を持つ repo があれば同じ検査が必要 (本 issue の完了条件に含める)。

## 対処の候補

1. **`RUSTUP_TOOLCHAIN` 環境変数を使う** — job / step の `env` に
   `RUSTUP_TOOLCHAIN: "1.82"` を置く。 rustup は `RUSTUP_TOOLCHAIN` を
   `rust-toolchain.toml` より優先するため確実に 1.82 になる。 **ただし本 repo の
   `scripts/{fmt,clippy,doc,test,deny}.sh` は冒頭で `unset RUSTUP_TOOLCHAIN` している**
   ので、 script 経由で呼ぶ場合は無効化される点に注意 (msrv job は script を経由せず
   `cargo test` を直接叩いているので問題ない)
2. **`cargo +1.82 test ...` と明示する** — toolchain 指定は `rust-toolchain.toml` より
   強い。 変更が 1 行で済む
3. **`rust-toolchain.toml` を一時退避する** — job 内で `mv rust-toolchain.toml{,.bak}`
   する。 副作用が大きく非推奨

候補 1 か 2 を推奨する。 **`gnrs-example` の
`issues/completed/2026-08-06-22-28-fix-respect-rust-toolchain-pin.md` は逆方向の問題
(mise が `RUSTUP_TOOLCHAIN` を export して pin を意図せず上書きする) を扱っており、
「`RUSTUP_TOOLCHAIN` が `rust-toolchain.toml` より強い」ことは既に実証済み**。

## 完了条件

- [ ] msrv job の toolchain 選択を `rust-toolchain.toml` より強い手段へ変更する
      (`RUSTUP_TOOLCHAIN` env または `cargo +1.82`)
- [ ] 変更後の CI ログで `rustup show active-toolchain` / `cargo --version` が
      **1.82 を報告すること** を確認する (`Show versions` step が既にあるので追加の
      instrumentation は不要)
- [ ] **1.82 で `cargo test --workspace --all-targets` が実際に通ることを確認する**。
      通らない場合は「MSRV 宣言が既に壊れていた」ことになるので、 その事実を記録して
      `rust-version` の見直しか code の修正を別途判断する
- [ ] `gnrs-time` の issue `2026-08-11-03-48-ci-msrv-job-may-not-verify-msrv` に本 repo の
      実測結果を根拠として追記し、 同 repo の是正へ引き継ぐ
- [ ] ginokent 配下で `msrv` job を持つ他 repo を洗い出し、 同じパターンがあれば
      各 repo に issue を起票する

## 非スコープ

- **MSRV 値 (1.82) 自体の見直し**: まず「宣言どおり 1.82 で通るか」を確認するのが先。
  通らない場合の対応は本 issue の完了条件で判断のみ行い、 実装は別 issue に切り出す
- **`rust-toolchain.toml` の channel (1.95) の変更**: 通常ビルドの pin は維持する
