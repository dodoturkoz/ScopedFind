# ScopedFind

ScopedFind is a dependency-free native macOS app for searching inside one folder at a time. It has explicit Names and Contents modes, so filename matches do not get mixed with file-content matches.

It uses macOS's built-in `/usr/bin/find` and `/usr/bin/grep`, Apple's PDFKit, and in-process ZIP/XML readers for modern Word, Excel, and PowerPoint files. It does not bundle search binaries, package-manager dependencies, telemetry, an updater, or a cloud service.

![ScopedFind screenshot](docs/screenshot.png)

## Download

Download the latest DMG from the [Releases](https://github.com/dodoturkoz/ScopedFind/releases) page.

Or install with Homebrew from the ScopedFind tap:

```bash
brew install --cask dodoturkoz/tap/scopedfind
```

The release DMG is currently unsigned and not notarized. That means macOS cannot verify the developer identity or check an Apple notarization ticket before first launch. Depending on your macOS version and security settings, it may say the app cannot be verified or is damaged.

After installing the app, try Apple's normal override flow first:

1. Open the DMG.
2. Drag `ScopedFind.app` onto the `Applications` shortcut in the DMG window.
3. Open `ScopedFind.app` from Applications.
4. If macOS blocks it, open System Settings, go to Privacy & Security, and use Open Anyway if it is offered.

If macOS still reports that the app is damaged or cannot be verified, you can remove the download quarantine flag from the installed copy:

```bash
xattr -dr com.apple.quarantine /Applications/ScopedFind.app
```

Then open `ScopedFind.app` normally from Applications.

Only run the quarantine-removal command for an app copy you trust. It bypasses macOS's download warning for that installed copy of ScopedFind.

## Features

- Dependency-free native SwiftUI app for scoped local search
- Separate Names and Contents modes
- Contents search for regular text files, text-based PDFs, `.docx`, `.xlsx`/`.xlsm`, and `.pptx`/`.pptm` files
- Extension, preset/custom modified-time, preset/custom size, result-type, case-sensitivity, and hidden-file filters
- Unicode-aware fallback matching plus contains, regex, and fuzzy filename matching
- Live, cancellable results with elapsed search activity plus Open, Reveal in Finder, and Copy Path actions
- A prominent Learn/Exact guide that explains every command pass and app-side matching stage used by a search

## Search Behavior

Searches are recursive and stay inside the folder you choose.

Names mode searches file and folder names with `/usr/bin/find`. By default it uses contains matching, so `report` matches names containing `report`. Regex matching uses regular expressions against names, and fuzzy matching can match ordered characters, so `sf` can match `ScopedFind` and `rpt` can match `report-final.txt`. Regex and fuzzy matching are only for file and folder names; fuzzy matching is not typo correction, ranked `fzf` search, or content search.

Contents mode searches regular files with `/usr/bin/grep`, text-based PDFs with PDFKit, and modern Office document text with in-process ZIP/XML readers. Word support covers `.docx`; Excel support covers `.xlsx` and `.xlsm`; PowerPoint support covers `.pptx` and `.pptm`. The query is literal text, not a regular expression.

Excel searches shared and inline cell text, stored formulas and raw stored values, and cell comments. ScopedFind does not recalculate formulas or reproduce Excel's displayed formatting, so formatted dates, currencies, and other display-only representations may differ from what is visible in Excel. PowerPoint searches slide text, speaker notes, comments, and comment-author text. Scanned or image-only PDFs are not OCRed. Legacy binary Office formats such as `.doc`, `.xls`, and `.ppt` are not supported.

When Case sensitive is off, ScopedFind adds Unicode-aware, diacritic-insensitive fallback matching for names and supported file contents. For example, `sevket` can match `şevket`. Case-sensitive searches stay literal.

The Extensions field accepts extensions with or without a leading dot, separated by commas, semicolons, spaces, or newlines. Modified and Size filters use filesystem attributes and work in both modes. Custom modified-date filters support on, before, since, and inclusive between checks for chosen calendar dates. Custom size filters support less than, more than, exact byte size, and inclusive between checks after unit conversion. KB, MB, and GB use decimal units (for example, 1 KB is 1,000 bytes); use B for an exact byte count. In Names mode, you can search by extension, modified time, or size without a text query. In Contents mode, a text query is required.

## Learn From Each Search

The **Learn what ScopedFind ran** card stays visible above the results so the educational feature is discoverable before the first search. After a search starts, the whole card becomes an **Open Guide** action for that search.

- **Learn** describes the search as a sequence of understandable stages: name enumeration, ordinary-text matching, Unicode fallback matching, PDFKit extraction, modern Office ZIP/XML reading, and app-side filters as applicable.
- **Exact** shows every planned executable and argument array as a shell-formatted command, provides a short guide to flags such as `-type`, `-iname`, `-print0`, `-exec`, and the `grep` options, and lets you copy each command. Each full Argument guide row is clickable and scrolls its expanded explanation into view.

The exact display is generated from the same execution plan the search service uses. It does not pretend that a hybrid search is one command: Foundation regular expressions, Unicode-aware matching, PDFKit, Office ZIP/XML parsing, and modified-time/size checks are labeled as app-side stages. A search that is cancelled or fails can stop before a later planned command is launched.

The copied form is safe shell notation for learning or manual use. ScopedFind itself still passes the executable path and arguments directly to `Process`; it does not execute the displayed text through a shell.

## How It Searches

ScopedFind builds commands with `Process`, fixed executable paths, and argument arrays. It does not invoke `/bin/sh`, `/bin/zsh`, or any other shell.

Names mode is equivalent to:

```bash
/usr/bin/find "/selected/folder" -iname "*query*" -print0
```

Regex name matching, Unicode fallback matching, and modified/size filters are applied in process using Foundation APIs.

Contents mode uses `find` plus literal `grep` for regular files:

```bash
/usr/bin/find "/selected/folder" -type f -exec /usr/bin/grep -I -l --null -F -i -e "query" {} +
```

PDF and modern Office files are handled as dependency-free in-process passes after `find` enumerates matching files:

```bash
/usr/bin/find "/selected/folder" -type f -iname "*.pdf" -print0
/usr/bin/find "/selected/folder" -type f -iname "*.docx" -print0
/usr/bin/find "/selected/folder" -type f \( -iname "*.xlsx" -o -iname "*.xlsm" \) -print0
/usr/bin/find "/selected/folder" -type f \( -iname "*.pptx" -o -iname "*.pptm" \) -print0
```

If Extensions are empty, ordinary files and every supported document format are included. If Extensions are set, each specialized pass only runs for matching extensions.

The in-process ZIP reader limits archive size, entry count, individual decompressed entry size, total extracted XML size, and suspicious compression ratios before parsing document text.

## Privacy

ScopedFind is intentionally local and transparent.

- It makes no network requests.
- It contains no analytics, telemetry, ads, crash-reporting SDK, tracking SDK, updater, launch agent, or background service.
- It does not request Full Disk Access.
- It searches only inside the folder you choose.
- Names mode does not read file contents.
- Contents mode reads file contents inside the chosen folder to find matching files.
- It does not log filenames or search queries.

The source code is public so you can inspect exactly how folder access and search execution work.

## Why Not Finder Search?

Finder and Spotlight are excellent for broad macOS search, but they often combine filename matches and file-content matches. ScopedFind is for narrower searches where the chosen folder and search mode should be explicit.

| Need | Finder search | ScopedFind |
| --- | --- | --- |
| Find by filename only | Can mix filename and content matches | Names mode searches names only |
| Search file text without Spotlight | Depends on indexing and metadata behavior | Uses `grep`, PDFKit, and modern Office ZIP/XML readers directly |
| Search exactly one chosen folder tree | Can be broad depending on scope | Stays inside the folder you choose |
| Filter by extension, modified time, or size | Possible, but not always obvious | Dedicated filter controls |
| Find apps in `/Applications` | Can be mixed with other result types | Use Names mode with `Files and folders` or `Folders/apps only` |

## Folder Access

ScopedFind uses the folder access granted by the native macOS folder picker for the current app session. The code is structured so security-scoped bookmarks can be added later if persistent access is needed.

## Building Locally

Open `ScopedFind.xcodeproj` in Xcode and run the `ScopedFind` scheme.

To build an app you can keep in Applications:

1. Open `ScopedFind.xcodeproj` in Xcode.
2. Select the `ScopedFind` scheme and `My Mac`.
3. Choose `Product > Build`.
4. Choose `Product > Show Build Folder in Finder`.
5. Open `Products/Debug` or `Products/Release`.
6. Drag `ScopedFind.app` into `/Applications`.

After that, you can launch ScopedFind from Applications, Spotlight, or your Dock without opening Xcode.

## Local Development

The repository includes a `Package.swift` test harness for non-UI logic:

```bash
swift test
```

A full app build needs Xcode, not only Command Line Tools.

## Project Scope

This is a personal, single-maintainer project published for source transparency. Issues are open for bug reports and small questions, but pull requests are intentionally disabled because the project is not intended to be community-maintained.

## License

MIT License. See `LICENSE`.
