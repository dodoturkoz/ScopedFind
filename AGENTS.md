# AGENTS.md

Notes for future coding agents working on ScopedFind.

- ScopedFind is a small native macOS SwiftUI app around `/usr/bin/find`.
- The core promise is filename/folder-name search only. Do not accidentally expand behavior into content search without making that a deliberate product change and updating the README/UI.
- Search command construction should stay shell-free: use `Process`, a fixed `/usr/bin/find` executable URL, and argument arrays.
- Keep privacy claims honest. If networking, telemetry, logging, persistent background behavior, Full Disk Access, or update mechanisms are added, update `README.md`.
- If user-facing behavior changes, update `README.md`; if the UI changes noticeably, consider updating `docs/screenshot.png`.
- The GitHub release DMG is built from `v*` tags by `.github/workflows/release.yml`.
- Local `swift test` covers the non-UI logic. A full app build needs Xcode, not only Command Line Tools.
- Update this file when project-specific context would make future agent work easier or safer.
