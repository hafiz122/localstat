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

- [ ] Remove the Patrick Jane image from all Git history before changing the
  repository to public. Verify with a fresh clone and an object/history scan.
- [ ] Confirm the current logo, screenshot, examples, and every bundled asset
  have redistribution rights.
- [ ] Enable GitHub private vulnerability reporting.
- [ ] Add branch protection for `main` and require the CI check.
- [ ] Review repository topics, description, license detection, and public issue
  settings.

## Prerelease

- [ ] Create an annotated `v0.1.0-alpha` tag on the reviewed commit.
- [ ] Push the tag and confirm the prerelease workflow uploads exactly one ARM64
  ZIP and its matching `.sha256` file.
- [ ] Download both files, verify the checksum, inspect the extracted app, and
  smoke-test open/edit/save/run/stop on a separate Apple Silicon Mac.
- [ ] Keep the release marked as a prerelease and retain the Developer Preview,
  ad-hoc signing, Gatekeeper, compatibility, and trust-boundary warnings.

Developer ID signing, hardened runtime, notarization, universal binaries, and a
consumer installer are beta/public-distribution milestones, not claims of this
alpha.
