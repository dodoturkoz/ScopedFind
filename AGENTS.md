# AGENTS.md

Notes for future coding agents working on ScopedFind.

- ScopedFind is a small native macOS SwiftUI app around `/usr/bin/find` and `/usr/bin/grep`.
- The app has explicit Names and Contents modes. Keep name/folder matching and content matching clearly separated in the UI, README, and tests.
- Fuzzy search is currently dependency-free and still implemented as name matching through `/usr/bin/find`; do not introduce an external `fzf` binary unless there is a deliberate packaging/release decision.
- Content search is dependency-free: ordinary files use `/usr/bin/find ... -exec /usr/bin/grep ... {} +`, and text-based PDFs use Apple's PDFKit in-process. Do not introduce ripgrep, ack, OCR engines, or another search binary without a deliberate packaging/release decision.
- Search command construction should stay shell-free: use `Process`, fixed `/usr/bin/find` and `/usr/bin/grep` paths, and argument arrays.
- Keep privacy claims honest. If networking, telemetry, logging, persistent background behavior, Full Disk Access, or update mechanisms are added, update `README.md`.
- If user-facing behavior changes, update `README.md`; if the UI changes noticeably, consider updating `docs/screenshot.png`.
- The GitHub release DMG is built from `v*` tags by `.github/workflows/release.yml`.
- Local `swift test` covers the non-UI logic. A full app build needs Xcode, not only Command Line Tools.
- Update this file when project-specific context would make future agent work easier or safer.
