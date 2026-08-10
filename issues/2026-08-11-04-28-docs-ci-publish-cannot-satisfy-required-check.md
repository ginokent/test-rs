# ci-publish-status-dangerously が required check を満たせない実態と設計の食い違いを解消する

- Priority: Medium
- Created: 2026-08-11 04:28 JST
- Model: Opus 5 (1M context)
- Branch: (TBD)
- Status: **起票**。 未着手
- 起票経緯: 改名 issue `2026-08-11-04-02-refactor-rename-to-gnrs-test` の PR #39 で
  `mise run ci-publish-status-dangerously` 相当を実行して 5 context を success として
  投影したにもかかわらず、 PR が `mergeStateStatus: BLOCKED` のまま merge できなかった

## 実態 (実測)

`gh ruleset check main` の実出力:

```
- required_status_checks: [do_not_enforce_on_create: false]
  [required_status_checks: [map[context:cargo fmt --check integration_id:15368]]]
  [strict_required_status_checks_policy: true]
  (configured in ruleset 16788468 from repository ginokent/testrs)
```

**`integration_id:15368` が指定されている**。 これは「`cargo fmt --check` という
context を **integration_id 15368 (GitHub Actions) が報告したもの**」だけを required と
して扱う設定である。

一方 `scripts/report-status-local.sh` は **PAT 経由の `gh api .../statuses/{sha}`** で
status を POST するため integration_id が一致せず、 **投影した status は required check
として認識されない**。

実測 (PR #39、 head `fbe5142`):

- `scripts/ci-publish-status-dangerously.sh` は exit 0 で完走し、 5 context すべてを
  success として投影した (`gh api .../commits/fbe5142/status` の `state` も `success`)
- それでも `gh pr view 39 --json mergeStateStatus` は **`BLOCKED`**
- `--admin` は `rule-git` の Constraints と deny hook により使用禁止

## 設計との食い違い

`CONTRIBUTING.md:75-153` は `ci-publish-status-dangerously` を「**Branch protection の
Required status checks を local 1 回で満たせる**」構成として説明しており、
投影する context 名を「CI workflow の各 job `name:` と完全一致」させる設計を記述して
いる。 しかし **ruleset 側は既に `integration_id` で GitHub Actions 限定になっている**
ため、 この前提が成立していない。

さらに `CONTRIBUTING.md:154` 以降の「第三者 contributor 環境での切替案」は、
**まさにこの状態 (Required check は CI 経路でしか満たせない構成) を推奨手順として
記述している**。 つまり ruleset は切替案を適用済みだが、 **script と CONTRIBUTING.md
本体は切替前の設計のまま残っている**。

この不整合の実害:

- `mise run ci-publish-status-dangerously` は **成功するのに merge できない**。 実行者は
  「投影したのに BLOCKED」で原因が分からず止まる (本 session で実際に踏んだ)
- `CONTRIBUTING.md:141` の risk table は「typo / 未投影で偽陽性」を挙げているが、
  **integration_id の不一致という失敗モードは記載がない**

## 対処の候補 (どれを採るかは実装時に判断)

1. **script の context 名に prefix を付ける** — `CONTRIBUTING.md:154-` の切替案どおり
   `local-ci: cargo fmt --check` のような名前にし、 「CI と同名で required を満たす」
   意図を放棄する。 投影は「ローカル検証の記録」として残す
2. **script を撤去する** — `mise.toml` の task と `scripts/ci-publish-status-dangerously.sh`
   / `scripts/report-status-local.sh` を削除し、 CONTRIBUTING.md の該当節も削る
3. **CONTRIBUTING.md に実態を明記する** — script は残すが「**本 repo の ruleset は
   `integration_id` で GitHub Actions 限定なので、 投影では merge できない。 merge には
   `!run ci` が必要**」と明記し、 risk table に integration_id の失敗モードを追加する

いずれの場合も **他 repo との差異** を書き残す価値がある。 実測した限り
`gnrs-example` (ruleset 17727674) と `gnrs-time` (17644199) は
`integration_id:<nil>` (App を問わない) で、 投影で required を満たせる。 **本 repo だけ
挙動が違う**。

## 完了条件

- [ ] 上記 3 候補のいずれかを選び、 実装する
- [ ] `CONTRIBUTING.md` の記述を実態に合わせる (どの候補を採っても記述の修正は必要)
- [ ] `integration_id` の不一致という失敗モードを risk table か該当節に追記する
- [ ] 他 repo (`gnrs-example` / `gnrs-time` / `gnrs-log`) との ruleset 設定の差異を
      記録する (本 repo だけ CI 経路限定である旨)
- [ ] 変更後、 実際に PR を 1 本通して意図どおりに動くことを確認する

## 非スコープ

- **ruleset の設定変更**: `integration_id` 制約を外すかどうかはユーザーの判断であり、
  hook も ruleset 系 `gh api` を閲覧含め deny している。 本 issue は「現状の ruleset を
  前提に script とドキュメントを整合させる」方向で扱う
- **改名 PR #39 の merge 手段**: ユーザー判断で `!run ci` により GitHub Actions を
  起動して通す (本 issue の対処を待たない)
