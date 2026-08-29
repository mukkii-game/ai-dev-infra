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
    uses: mukkii-game/ai-dev-infra/.github/workflows/verify-web.yml@v1
    # inputs は任意。省略時は artifact_path: dist / node_version: lts/* が使われます。
    with:
      artifact_path: dist
      node_version: lts/*
```

## セキュリティ方針

`verify-web.yml` は、信頼できないPRのコードを実行するものとして設計しています。

- permissions は `contents: read` のみ
- secrets を一切参照・使用しません。workflow 内のどのステップも secret を読み取らず、
  環境変数やコマンドライン経由でアプリコードに渡すこともありません
- GitHub への write 権限を持ちません
- `main` への push、PRのmerge、デプロイは行いません
- checkout したアプリコードを高権限で実行しません

ネットワーク取得については、`npm ci` による lockfile に固定された依存関係の取得、および
CI環境の構築に必要な Node.js・GitHub Actions・Playwright の Chromium / OS依存関係の取得は
行います。一方で、不足したCLIを `npx` 等で暗黙に追加取得することはしません。

## このリポジトリで扱わないもの

auto-merge / デプロイ / `workflow_dispatch` / GitHub Pages / Cloudflare /
bootstrap 処理 / PAT やその他の secret は、現時点では実装しません。
