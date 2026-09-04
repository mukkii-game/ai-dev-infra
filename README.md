# ai-dev-infra

AI開発向けの**中央CI基盤**リポジトリです。Claude Code Cloud と OpenAI Codex Cloud の
どちらから開発する場合でも同じ検証が走るように、Webアプリ用の GitHub Actions
ワークフローをここで一元管理します。

各Webアプリのリポジトリは、CIの中身を自前で持たず、ここで定義された
**Reusable Workflow** を呼び出して利用します。

## 提供しているワークフロー

### `.github/workflows/verify-web.yml`

Vite + TypeScript + npm 構成のWebアプリを検証する Reusable Workflow です。
呼び出し元リポジトリに対して、GitHub-hosted の Ubuntu runner 上で次を実行します。

1. 呼び出し元リポジトリを checkout
2. Node.js のセットアップ
3. `package-lock.json` の存在確認（無ければ明確なエラーで失敗。`npm install` にはフォールバックしません）
4. `npm ci`
5. `./node_modules/.bin/tsc --noEmit`
6. `./node_modules/.bin/vitest run`
7. `./node_modules/.bin/vite build`
8. `./node_modules/.bin/playwright install --with-deps chromium`
9. `./node_modules/.bin/playwright test`
10. すべて成功した場合のみ、ビルド成果物を GitHub Actions artifact として保存

`tsc` / `vitest` / `vite` / `playwright` は `npx` で暗黙にダウンロードせず、
`npm ci` 後の `./node_modules/.bin/` にあるローカルCLIを直接実行します。
これらが呼び出し元の依存関係に無い場合は、ネットワークから取得せずCIを失敗させます。

#### inputs

| name | type | required | default | 説明 |
| --- | --- | --- | --- | --- |
| `artifact_path` | string | no | `dist` | artifact として保存するビルド出力ディレクトリ |
| `node_version` | string | no | `lts/*` | `actions/setup-node` に渡す Node.js のバージョン |

#### 呼び出し側の例

Webアプリ側のリポジトリに、次のようなワークフローを置きます。

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  verify:
    uses: mukkii-game/ai-dev-infra/.github/workflows/verify-web.yml@main
    # inputs は任意。省略時は artifact_path: dist / node_version: lts/* が使われます。
    with:
      artifact_path: dist
      node_version: lts/*
```

### `.github/workflows/merge-guard.yml`

このリポジトリ内のブランチからのPRについて、fork でない場合に GitHub native
auto-merge を有効にします。`.github/**` の変更も同じく自動マージされます。
「ワークフロー変更は人間の承認必須」という安全弁は、1人＋AIの運用では守るもの
より手動マージの手間のほうが大きかったため外しました。

呼び出し側は `pull_request_target` を宣言し、次の薄いcallerだけを保持します。

```yaml
name: Merge Guard

on:
  pull_request_target:
    types: [opened, synchronize, reopened, ready_for_review]

permissions:
  contents: write
  pull-requests: write

concurrency:
  group: merge-guard-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  guard:
    uses: mukkii-game/ai-dev-infra/.github/workflows/merge-guard.yml@main
```

reusable化により必須チェックcontextは
`guard / Guard and enable auto-merge` になります。既存リポジトリのrulesetもcaller
移行と同時にこのcontextへ更新します。

### `.github/workflows/deploy-pages.yml`

CIが検証・保存した `web-build` artifactだけをGitHub Pagesへ公開します。再buildは
しません。`workflow_run` のPR CIとmain push CIを扱い、bot merge・現在のmain・
Git tree一致を検証します。

bot merge待ちは最大5分です。時間内にmergeされない場合はwarningを残し、callerの
`workflow_dispatch` から現在のmainに対応するCI artifactを再検証して公開できます。

```yaml
name: Deploy Pages

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
  workflow_dispatch:

permissions:
  contents: read
  actions: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  deploy:
    uses: mukkii-game/ai-dev-infra/.github/workflows/deploy-pages.yml@main
```

### `.github/workflows/publish-itch.yml`

CIが検証・保存した `web-build` artifactだけを、butler で itch.io へ公開します。
`deploy-pages.yml` とまったく同じ認可ゲート（bot merge・現在のmain・Git tree一致）を
通してから公開し、再buildもコードの実行もしません。

Vite の `base` が `./` であれば、Pages に出しているものと**同一のartifact**が
itch.io でもそのまま動きます。itch用の別ビルドは不要です。

APIキーは最後の push ステップにしか渡りません。checkout もしないため、PRのコードが
キーに到達する経路がありません。認可ゲートの本文は `deploy-pages.yml` と
byte単位で一致していることをCIが検査します（片方だけ緩むのを防ぐため）。

#### inputs / secrets

| name | 種別 | required | default | 説明 |
| --- | --- | --- | --- | --- |
| `itch_target` | input | yes | — | 公開先。`user/game` 形式 |
| `itch_channel` | input | no | `html5` | butler のチャンネル名 |
| `butler_version` | input | no | `LATEST` | butler のバージョン。`x.y.z` で固定可 |
| `butler_api_key` | secret | yes | — | itch.io の API キー |

`itch_target` / `itch_channel` / `butler_version` はコマンドラインに渡るため、
許可パターンに一致しない値はゲート通過後でも実行前に失敗させます。

#### 呼び出し側の例

secret はcaller側リポジトリに置きます。このリポジトリはsecretを保持しません。
また、callerは渡すsecretを**明示**します。`secrets: inherit` は使いません。

```yaml
name: Publish to itch.io

on:
  workflow_run:
    workflows: [CI]
    types: [completed]
  workflow_dispatch:

permissions:
  contents: read
  actions: read

concurrency:
  group: itch
  cancel-in-progress: false

jobs:
  publish:
    uses: mukkii-game/ai-dev-infra/.github/workflows/publish-itch.yml@main
    with:
      itch_target: your-itch-user/your-game
    secrets:
      butler_api_key: ${{ secrets.BUTLER_API_KEY }}
```

#### 初回だけ必要な手動作業

1. itch.io でプロジェクトを作成する（butlerは存在しないプロジェクトを作れません）
2. https://itch.io/user/settings/api-keys でAPIキーを発行する
3. caller側リポジトリの Settings → Secrets and variables → Actions に
   `BUTLER_API_KEY` として登録する
4. 初回 push 後、itch.io のプロジェクト編集画面で Kind of project が
   *HTML* になっていること、アップロードが
   *This file will be played in the browser* になっていることを確認する
   （`html` を含むチャンネル名なら通常は自動で設定されます）

## セキュリティ方針

`verify-web.yml` は、信頼できないPRのコードを実行するものとして設計しています。

- permissions は `contents: read` のみ
- secrets を一切参照・使用しません。workflow 内のどのステップも secret を読み取らず、
  環境変数やコマンドライン経由でアプリコードに渡すこともありません
- GitHub への write 権限を持ちません
- verify workflowは `main` へのpush、PRのmerge、デプロイを行いません
- Merge GuardはPRコードをcheckout・実行しません
- Deploy PagesはCI artifactを実行せず、検証後にPagesへ転送します
- Publish to itch.ioも同じ認可ゲートを通し、artifactを実行しません。APIキーは
  ゲート通過後のpushステップ1箇所にしか渡らず、callerは渡すsecretを明示します
- 各callerは必要なpermissionsを明示し、called workflowは権限を昇格できません
- 外部Actionsはすべて完全なcommit SHAに固定します

ネットワーク取得については、`npm ci` による lockfile に固定された依存関係の取得、および
CI環境の構築に必要な Node.js・GitHub Actions・Playwright の Chromium / OS依存関係の取得は
行います。一方で、不足したCLIを `npx` 等で暗黙に追加取得することはしません。

## 参照のしかた

caller は `@main` を参照します。不変タグ（`v1` `v2`）と「固定SHAでcanaryを通してから
タグを切る」手順は廃止しました。ワークフロー1本を足すのに手動マージが3回必要になり、
1人＋AIの運用では安全弁より手間のほうが大きかったためです。

`main` へのpushは即すべてのcallerに効きます。壊れたらこのリポジトリで直して
pushすれば、次のCIから直ります。`v1` `v2` タグは履歴として残しますが更新しません。

このリポジトリはPATやアプリのsecretを保持しません。リポジトリ生成と管理資格情報は
非公開の `mukkii-game/ai-ops` だけが扱います。
