# Public-alpha preparation audit

Audit date: 1 November 2026. Baseline commit:
`95236ce01e270bb118ac61e931c11a5daf7dedb3`.

## Source and history

Gitleaks 8.30.1 scanned all reachable Git history with full redaction and found
no credential matches. The inventory contained 12 commits and 3,940 unique
blobs; the largest was 1,510,390 bytes. No generated build directories or
credential-key filenames were found in reachable paths. Ignored build outputs
remain outside the repository. Scan output is kept locally under dist/audit.

This is a credential and publication-material audit, not a new exhaustive
runtime vulnerability certification. Git author identities and historic
commit metadata will be public with the repository. No history rewrite was
performed. Documentation and visible screenshot content were reviewed; the
screenshot contains synthetic regression results and no personal paths.

## Redistribution

The owner confirmed permission for the photographic logo and derived icon.
The grant reference, scope, and attribution are still pending in
ASSET_LICENSES.md. Publication remains a review gate.

All four externally sourced test binaries matched upstream Git blob hashes;
THIRD_PARTY_NOTICES.md records their locations. ReadStat, haven, and pandas
notices have been added. OpenSAS's synthetic TE fixture documents its generation
in its NOTES. Other corpus fixtures are inherited from the pinned Apache-2.0
snapshot; no independent claim of third-party authorship clearance is made.

## GitHub settings

Repository remains private. Branch-protection inspection returned HTTP 403
because this account/repository requires a plan upgrade or public visibility.
Private-vulnerability-reporting inspection returned HTTP 404. These settings
must be checked and enabled after publication becomes available; they are not
claimed as enabled.

The prepared protection payload is .github/main-protection.json. At the later
publication step, apply it with:

```sh
gh api --method PUT repos/hafiz122/localstat/branches/main/protection --input .github/main-protection.json
gh api --method PUT repos/hafiz122/localstat/private-vulnerability-reporting
```

It requires the `test` CI check and an up-to-date branch, applies to admins, and
prevents force pushes and deletion. Issue forms are included in this candidate.
No visibility change, final tag, or published release was part of preparation.

## Publication addendum: 1 November 2026

The owner subsequently authorized public visibility and publication of
v0.1.0-alpha. The repository is public, and the existing verified assets were
published as a prerelease at https://github.com/hafiz122/localstat/releases/tag/v0.1.0-alpha.
The annotated tag resolves to 107d2bf2880e4987935a518d4d0b84b2deb9bc98.
Private vulnerability reporting has been enabled. The prepared branch-protection
configuration is applied during publication, with its result verified through GitHub.

The release workflow was temporarily disabled while pushing the already-tested
tag to avoid a duplicate draft build, then re-enabled. No assets were replaced.
Artwork grant details and the second physical Mac smoke test remain outstanding;
publication authorization does not assert those checks were completed.
