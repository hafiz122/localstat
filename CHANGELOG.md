# Changelog

All notable changes to LocalStat are recorded here.

## Unreleased

## [0.1.5-alpha] - 2026-11-06

### Fixed

- Keep the editor gutter divider within the source area so it does not cross
  the active program tab or toolbar.

## [0.1.4-alpha] - 2026-11-05

### Changed

- Start a fresh workspace with an empty Project Explorer and an untitled
  program, instead of showing and opening bundled examples by default.
- Keep editable example copies in Application Support and make them available
  through Help or by explicitly opening the Examples folder as a project.
- Remove the extra "LocalStat Studio" bar above the workbench.

### Fixed

- Restore only valid saved project folders and keep failed fallback setup from
  displaying the home directory in the Project Explorer.

## [0.1.3-alpha] - 2026-11-05

### Changed

- Draw a complete border around every formatted table cell on screen, in
  printed pages, and in PDF reports.
- Keep the results controls visible when the Project Explorer divider moves
  or the app window reaches its minimum size.
- Keep the editor toolbar and source area visible when results expand.
- Match the line-number gutter to System and Dark appearances and remove the
  duplicate Results heading outside SAS Native.
- Explain the empty Diagnostics pane before and after a run.

## [0.1.2-alpha] - 2026-11-05

### Changed

- Name and keep SAS Native as the fresh-start workspace and editor default,
  while preserving explicitly saved System, Light, Dark, and editor choices.
- Refine the Project Explorer, program tabs, contextual Run toolbar, editor
  gutter, settings, and lower results pane around a compact workbench layout.
- Increase the default results pane height so formatted tables have more room.
- Present supported PRINT, FREQ, and TABULATE tables with restrained blue
  screen headers and SAS-inspired paper output: centered titles and narrow
  tables, horizontal rules, and right-aligned numeric values.

### Fixed

- Keep character values containing punctuation left-aligned in printed tables.
- Update built-in Help and verification documentation to match the current UI.

## [0.1.1-alpha] - 2026-11-05

### Added

- Horizontally scrolling source tabs with visible close buttons, unsaved-change
  indicators, and keyboard-accessible controls.
- View menu commands that open the editor and output font settings directly.
- Offline searchable Help with a user guide, language guides, procedure/function
  index, and runnable examples that open as unsaved editor tabs.
- Native Settings with editor themes, separate source/output fonts, viewing
  controls, screen-only table zoom, and configurable editing assistance.
- SAS Studio style workspace by default, including the Explorer tree, code and
  results chrome, syntax colors, and a matching Dark appearance.
- Expandable project folders with import and create actions for programs and
  folders, preserving navigation across refreshes.
- Source package for the professor presentation and synthetic demo programs.
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
