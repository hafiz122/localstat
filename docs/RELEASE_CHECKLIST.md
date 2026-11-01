# 0.1.0-alpha release checklist

## Candidate source

- [ ] Working tree is clean and the release commit is reviewed.
- [ ] `VERSION` is `0.1.0-alpha` and `CHANGELOG.md` has no missing alpha notes.
- [ ] `./scripts/release-alpha.sh` passes on Apple Silicon.
- [ ] The `macos-14` CI job passes from a fresh checkout.
- [ ] The generated ZIP checksum verifies after downloading to another path.
- [ ] In-app Help contains the current compatibility and security warnings.
- [ ] No feature is described as fully SAS-compatible or SAS-verified without
  actual reference output from an installed SAS engine.

## Repository publication

- [x] Owner confirmed permission to retain the Patrick Jane/Simon Baker logo.
- [ ] Record the grant reference, covered uses and attribution before public publication.
- [ ] Confirm the screenshot, examples, and every other bundled asset have
  redistribution rights.
- [ ] Enable GitHub private vulnerability reporting.
- [ ] Add branch protection for `main` and require the CI check.
- [ ] Review repository topics, description, license detection, and public issue
  settings.

## Prerelease

- [ ] Dispatch `release-alpha.yml` on main with the full reviewed commit SHA as
  `candidate_commit`. It tests the candidate and creates a private draft
  prerelease with exactly one ZIP and matching `.sha256` file.
- [ ] Review the verification record included in the draft release body.
- [ ] Download both files, verify the checksum, inspect the extracted app, and
  smoke-test open/edit/save/run/stop on a separate Apple Silicon Mac.
- [ ] Keep the release marked as a prerelease and retain the Developer Preview,
  ad-hoc signing, Gatekeeper, compatibility, and trust-boundary warnings.

## Later publication (not performed during candidate preparation)

- [ ] Resolve the pending asset-permission details and second-Mac results.
- [ ] Approve repository visibility and final release publication.
- [ ] Enable private vulnerability reporting and apply .github/main-protection.json
  when the repository plan permits it; see PUBLICATION_AUDIT.md.
- [ ] Create the final annotated `v0.1.0-alpha` tag on the verified candidate
  commit, then publish the already-reviewed draft as a prerelease. The tag
  workflow will refuse to replace an existing draft/release and its assets.

Developer ID signing, hardened runtime, notarization, universal binaries, and a
consumer installer are beta/public-distribution milestones, not claims of this
alpha.
