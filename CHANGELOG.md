# Changelog

All notable changes to LocalStat are recorded here.

## Unreleased

### Added

- Horizontally scrolling source tabs with visible close buttons, unsaved-change
  indicators, and keyboard-accessible controls.
- View menu commands that open the editor and output font settings directly.
- Offline searchable Help with a user guide, language guides, procedure/function
  index, and runnable examples that open as unsaved editor tabs.
- Native Settings with editor themes, separate source/output fonts, viewing
  controls, screen-only table zoom, and configurable editing assistance.
- Toolbar Appearance control with System, Light, and Dark choices that persist
  between launches.
- Code-first IDE layout with saved pane sizes, a collapsible project navigator,
  and a compact results header with an expansion control.
- Formatted Tables tab for PROC PRINT, PROC FREQ, and PROC TABULATE, with grouped
  headings, totals, and BY sections where supported by the runtime.
- Native Print Tables command and formatted table pages in PDF run reports.
- Optional versioned `--tables-json <path>` runtime output for the IDE; the
  existing text listing and text export stay unchanged.

### Fixed

- Default to four spaces for automatic indentation, Tab, and Shift-Tab. Migrate
  saved two-space settings once while preserving later explicit choices and
  existing source text.
- Keep the Settings table-zoom selector accurate after repeated size changes.
- Clear Help's empty-search message when navigation restores the contents list.
- Show the complete input data and program in the reporting guide, and verify
  both article code and Open Example programs in fresh projects.
- Replace em dashes throughout tracked source, diagnostics, fixtures, and
  documentation, with a repository text check to prevent reintroduction.
- Reject malformed table files with overflowing cell spans instead of crashing
  while validating their layout.

## [0.1.0-alpha] - 2026-11-01

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
