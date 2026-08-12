# ディレクトリ改名で取りこぼした doc のリンク切れを修正する

- Priority: Medium (doc のリンク切れのみ。 コード・スクリプトへの実害なし)
- Created: 2026-08-13 06:05 JST
- Model: Opus 5 (1M context)
- Branch: `feature/fix-stale-crate-dir-paths`
- Status: **完了** (2026-08-13 06:0x)。 完了条件 3 件すべて充足
- 起票経緯: `2026-08-12-20-23-refactor-align-crate-dir-names` (PR #41 / merge `46b5d23`)
  の残存確認が誤っており、 旧パス参照 15 件を取りこぼしていた。 `gnrs-crypto` で同種の
  取りこぼしが CI leg failure として顕在化したため、 先行 repo を再走査して発見した

## 何が起きたか

ディレクトリ改名 PR #41 の残存確認で
`git grep -E 'crates/(core|pbt|fuzz|pbt-derive|bench)\b'` を使い **0 件**と判定したが、
**`git grep` のデフォルト正規表現エンジンでは `\b` (単語境界) が期待どおり動かない**。

実測 (`gnrs-crypto` で確認): `git grep -c -E 'crates/(crypto)\b'` は 0 件、
`git grep -c -E 'crates/(crypto)/'` は 1 件を返す。

固定文字列 (`git grep -F 'crates/pbt/'`) で再走査すると **15 件**が残っていた。

## 影響 (本 repo は doc のみ)

`README.md` (9 件) と `CONTRIBUTING.md` (6 件) が各 crate の README を
`crates/pbt/README.md` 等の旧パスで参照しており、 **GitHub 上でリンク切れ (404)** に
なっていた。

**コード・スクリプトへの実害はない**。 他 repo では実害が出ている:

| repo | 残存 | 実害 |
|---|---|---|
| **本 repo** | **15 件** | doc のリンク切れのみ |
| `gnrs-time` | 7 件 | **`scripts/gen-tzdb-bundle.sh` の出力先パス** |
| `gnrs-log` | 9 件 | doc のリンク切れのみ |
| `gnrs-crypto` | 119 件 | **`scripts/ct_codegen.sh` の `find` 対象**。 CI leg failure として顕在化 |

## 対策 (今後の展開先に適用する)

**旧ディレクトリ名の走査は `\b` を使わない**。 固定文字列 (`-F`) か末尾スラッシュ
(`crates/<dir>/`) を使い、 加えて `../<dir>/` 形 (相対リンク・`#[path]`) も別途走査する。

## 完了条件

- [x] `README.md` (9 件) と `CONTRIBUTING.md` (6 件) の旧パスを `crates/gnrs-test-*/` へ修正する
- [x] 固定文字列で残存 0 件を確認する (`issues/` 配下の archival は除外)
- [x] リンク先ファイルが実在することを確認する
      — `crates/gnrs-test-{pbt,fuzz,bench}/README.md` の 3 件すべて実在

## 非スコープ

- **`issues/completed/` 配下の旧パス言及**: archival として据え置く (改名当時の記録)
- **他 repo の取りこぼし修正**: 各 repo で別 issue / PR として対応する
