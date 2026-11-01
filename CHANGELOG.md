# Changelog

All notable changes to LocalStat are recorded here.

## [0.1.0-alpha] - Unreleased

### Added

- Native AppKit editor with project navigation, tabs, SAS highlighting, line
  numbers, find, undo, diagnostics, output, and whole-program execution.
- SAS-aware auto-indentation, Tab/Shift-Tab line indentation, bracket pairing,
  selection wrapping, closing-bracket skipping, and paired deletion.
- Bundled Apple Silicon OpenSAS runtime pinned to an upstream source revision.
- Fresh local runtime process for each run, cancellation, result export, and
  working-directory support.
- Searchable, paginated PDF run reports containing execution metadata, the
  executed source snapshot, output, and diagnostics.
- Bounded `PROC REG` ordinary-least-squares implementation using pivoted
  Householder QR, with estimates, inference, ANOVA, and model statistics.
- Automated runtime, compatibility, process-integration, and packaging tests.

### Known limitations

- This is an incomplete SAS-language subset, not SAS Institute software.
- The downloadable alpha artifact is ARM64-only, ad-hoc signed, and not
  notarized. Gatekeeper may reject it on another Mac.
- WORK and macro state do not persist between runs.
- Selection execution, dataset browsing, graphics, and non-text ODS output are
  not implemented.
- macOS 14 is the declared deployment target but has not yet been manually
  exercised on a macOS 14 installation.

### Security

- Hardened SAS catalog parsing against forged physical page counts, cyclic or
  repeatedly referenced block chains, disproportionate catalog work, and
  attacker-controlled entry-count allocations.

### Release preparation

- Draft-only prerelease workflow with explicit candidate commit dispatch,
  source commit metadata, extracted-bundle validation, and verification record.
- Installation guide, issue forms, publication audit, and third-party notices.
- Editor assistance avoids changing strings, comments, and DATALINES text;
  Unicode selection and native paste/Undo checks cover both system appearances.
