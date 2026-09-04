# DECISIONS.md

Durable design decisions. Append briefly; do not rewrite history.

## 2026-08-29 — Release workflow references are immutable

The existing `v1` tag never moves. A new release tag is created only after its
exact commit SHA passes a caller-repository canary. Callers migrate explicitly
to the new immutable tag.

## 2026-08-29 — Guard, CI and Pages policy are centralized

Application repositories retain thin event and permission callers under
`.github/workflows/**`; security-sensitive implementation lives in reusable
workflows here. Changing a caller remains a human-reviewed `.github/**` change.

## 2026-08-29 — Pages can recover without rebuilding

The ordinary workflow_run path waits up to five minutes for bot auto-merge. A
manual caller can recover by re-authorizing the CI artifact matching current
main. Both paths verify repository state and Git tree identity and never rebuild
application code.

## 2026-09-03 — Both publishers share one authorization gate

itch.io publishing reuses the Pages gate verbatim rather than restating it. A
reusable workflow cannot reference a composite action by a relative path, so the
gate is duplicated as text and `scripts/verify-workflows.rb` fails the build when
the two copies differ. A weaker gate on one publisher would be a security bug,
and duplication without that check is how one would appear.

## 2026-09-03 — The itch.io key reaches exactly one step

`publish-itch.yml` checks out nothing and exposes `butler_api_key` only to the
final push step, after authorization and the freshness check. Callers pass the
secret explicitly; `secrets: inherit` is banned repository-wide and asserted by
the verifier, including in documented caller examples.

## 2026-09-03 — butler is pinned by version, not by checksum

broth.itch.zone serves both the butler archive and any checksum published beside
it, so verifying one against the other proves transfer integrity and nothing
more. The workflow says so in place rather than implying a supply-chain
guarantee it does not have. `butler_version` pins a release when reproducibility
matters.

## 2026-09-04 — Safety valves that cost merges are removed

Two earlier decisions are reversed. Callers now reference `@main`; immutable
release tags and the canary-before-tag step are gone. Merge Guard no longer
refuses `.github/**` changes; every in-repository pull request auto-merges once
CI passes. Both valves were built for a team; this is one person and their
agents, and adding one workflow cost three manual merges. What stays: the fork
refusal, no checkout on write-capable runners, secrets named rather than
inherited, and the two publishers sharing one gate verbatim.
