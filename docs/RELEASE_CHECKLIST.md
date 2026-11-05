# 0.1.3-alpha release checklist

The `v0.1.2-alpha` candidate remained a draft after table and layout feedback.
This checklist tracks the corrected developer preview. Private
vulnerability reporting and required CI branch protection are enabled.
Artwork grant details and a second physical Mac test remain outstanding;
retain these limits in the new release notes.

## Candidate source

- [ ] Working tree is clean and the release commit is reviewed.
- [ ] `VERSION` is `0.1.3-alpha` and `CHANGELOG.md` has no missing alpha notes.
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
- [x] Enable GitHub private vulnerability reporting.
- [x] Branch protection for `main` requires the CI `test` check.
- [ ] Review repository topics, description, license detection, and public issue
  settings.

## Prerelease

- [ ] Push annotated `v0.1.3-alpha` on the reviewed main commit. The tag
  triggers `release-alpha.yml`, which tests and packages the candidate and
  creates a draft prerelease with one ZIP and matching `.sha256` file.
- [ ] Review the verification record included in the draft release body.
- [ ] Download both files, verify the checksum, inspect the extracted app, and
  smoke-test open/edit/save/run/stop on a separate Apple Silicon Mac.
- [ ] Keep the release marked as a prerelease and retain the Developer Preview,
  ad-hoc signing, Gatekeeper, compatibility, and trust-boundary warnings.

## Publication

- [ ] Resolve the pending asset-permission details and second-Mac results.
- [x] Approve repository visibility and final release publication.
- [ ] Enable private vulnerability reporting and apply .github/main-protection.json
  when the repository plan permits it; see PUBLICATION_AUDIT.md.
- [ ] Publish the reviewed draft as a prerelease. Repeat workflow runs must
  preserve existing release assets.

Developer ID signing, hardened runtime, notarization, universal binaries, and a
consumer installer are beta/public-distribution milestones, not claims of this
alpha.
