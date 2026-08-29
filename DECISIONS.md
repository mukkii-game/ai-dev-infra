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
