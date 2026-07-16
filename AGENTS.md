# AGENTS.md

Notes for future coding agents working on ScopedFind.

- ScopedFind is a small native macOS SwiftUI app around `/usr/bin/find` and `/usr/bin/grep`.
- The app has explicit Names and Contents modes. Keep name/folder matching and content matching clearly separated in the UI, README, and tests.
- Fuzzy search is currently dependency-free and still implemented as name matching through `/usr/bin/find`; do not introduce an external `fzf` binary unless there is a deliberate packaging/release decision.
- Content search is dependency-free: ordinary files use `/usr/bin/find ... -exec /usr/bin/grep ... {} +`, text-based PDFs use Apple's PDFKit in-process, and modern Office files use the bounded in-process ZIP/XML reader. Supported Office content formats are `.docx`, `.xlsx`/`.xlsm`, and `.pptx`/`.pptm`; legacy `.doc`, `.xls`, and `.ppt` remain unsupported. Excel searches shared/inline cell text, stored formulas and values, and comments without recalculation or display-format reproduction. PowerPoint searches slides, speaker notes, comments, and comment-author text. Do not introduce ripgrep, ack, OCR engines, Office parsing packages, or another search binary without a deliberate packaging/release decision.
- Case-insensitive search has Swift fallback matching for Unicode/diacritic-insensitive names and supported contents, such as `sevket` matching `şevket`; case-sensitive search should remain literal.
- Regex name matching and modified-time/size filters are dependency-free and applied in process; keep them shell-free and separate from content search regex semantics. Exact modified-date matching means "on this calendar date"; exact size matching means exact bytes after decimal KB/MB/GB unit conversion. Between-date and between-size filters include both boundaries.
- Search events stream from the service. The view model shows the first result immediately, then flushes small timed batches to avoid a SwiftUI refresh for every match in very large searches.
- The educational guide is a core feature and remains prominently discoverable above the results. It is generated from the same `FindSearchExecutionPlan` used by the service. Keep exact commands, launch order, app-side stages, shell-formatting language, tests, and README claims synchronized; never present a hybrid search as one command or imply that ScopedFind launches a shell.
- Search command construction should stay shell-free: use `Process`, fixed `/usr/bin/find` and `/usr/bin/grep` paths, and argument arrays.
- Keep privacy claims honest. If networking, telemetry, logging, persistent background behavior, Full Disk Access, or update mechanisms are added, update `README.md`.
- If user-facing behavior changes, update `README.md`; if the UI changes noticeably, consider updating `docs/screenshot.png`.
- The GitHub release DMG is built from `v*` tags by `.github/workflows/release.yml`.
- Local `swift test` covers the non-UI logic. A full app build needs Xcode, not only Command Line Tools.
- Update this file when project-specific context would make future agent work easier or safer.
