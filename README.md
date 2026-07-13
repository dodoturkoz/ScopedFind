# ScopedFind

ScopedFind is a small dependency-free native macOS app that wraps macOS's built-in `/usr/bin/find` and `/usr/bin/grep` commands, plus Apple's PDFKit for PDF text and an in-process DOCX text reader, in a SwiftUI interface.

The app searches only inside a folder you explicitly choose. It can search file and folder names, or search file contents with an explicit Contents mode. It is an MVP for scoped local searches, not a Finder replacement.

![ScopedFind screenshot](docs/screenshot.png)

## Download

Download the latest DMG from the [Releases](https://github.com/dodoturkoz/ScopedFind/releases) page.

The release DMG is currently unsigned and not notarized. macOS may say the app is damaged or cannot be verified until you remove the download quarantine flag:

1. Open the DMG.
2. Drag `ScopedFind.app` across the arrow onto the `Applications` shortcut in the DMG window.
3. Open Terminal.
4. Run:

    ```bash
    xattr -dr com.apple.quarantine /Applications/ScopedFind.app
    ```

5. Open `ScopedFind.app` normally from Applications.

Only run the quarantine-removal command for an app copy you trust. It bypasses macOS's download warning for that installed copy of ScopedFind.

Building from source is still available for users who prefer to inspect and compile the app themselves.

## Features

- Native Swift and SwiftUI macOS app
- Dependency-free: no bundled search binaries, package-manager dependencies, OCR engine, updater, telemetry, or cloud service
- Native folder picker
- Names or Contents search modes
- Case-sensitive or case-insensitive search
- Optional extension filtering, such as `swift`, `.pdf`, `.docx`, or `jpg,png`
- Optional fuzzy filename matching
- Content search through the built-in `/usr/bin/grep`, with PDF text search through Apple's PDFKit and DOCX text search through an in-process ZIP/XML reader
- Recursive search inside the selected folder
- Names-mode result type filtering for files only, folders/apps only, or both
- Optional hidden-file search
- Optional auto-search after typing pauses
- Streaming results while the search command is still running
- Cancel button for active searches
- Double-click to open results
- Context menu actions for Open, Reveal in Finder, and Copy Path

## Privacy

ScopedFind is intentionally local and transparent.

- It makes no network requests.
- It contains no analytics, telemetry, ads, crash-reporting SDK, tracking SDK, updater, launch agent, or background service.
- It does not request Full Disk Access.
- It searches only inside the folder you choose.
- Names mode does not read file contents.
- Contents mode reads file contents inside the chosen folder to find matching files.
- It executes only `/usr/bin/find` and `/usr/bin/grep`; Unicode fallback matching plus PDF and DOCX text extraction happens in-process.
- It does not invoke `/bin/sh`, `/bin/zsh`, or any other shell.
- It does not log filenames or search queries.

The source code is public so you can inspect exactly how folder access and search execution work. Search commands are built with `Process`, a fixed executable URL, and a separate arguments array so folder names and search text are not interpreted as shell syntax.

## Local Development

Open `ScopedFind.xcodeproj` in Xcode and run the `ScopedFind` scheme.

The repository also includes a `Package.swift` test harness for the non-UI logic, which is useful on machines that have the Swift toolchain installed:

```bash
swift test
```

## Search Behavior

Searches are recursive by default. When you choose a folder, ScopedFind searches that folder and its subfolders, but it does not leave the selected folder.

ScopedFind has two search modes:

- Names searches file and folder names with `/usr/bin/find`.
- Contents searches inside regular files with `/usr/bin/grep`, searches text-based PDFs with Apple's PDFKit, searches `.docx` Word document text in-process, and returns matching files.

When Auto search is enabled, ScopedFind starts a new search about 1.2 seconds after you stop typing or change a search option.

In Names mode, the query field uses contains matching:

- `report` matches names containing `report`.

If Fuzzy name matching is enabled, ScopedFind matches names where the typed characters appear in order:

- `sf` matches `ScopedFind`.
- `rpt` can match `report-final.txt`.
- Spaces in the query are ignored in fuzzy mode.

Fuzzy name matching is filename/folder-name search only. It is not typo correction, ranked `fzf` search, or content search.

In Contents mode, the query field is treated as literal text, not a regular expression. ScopedFind uses `grep -F` so punctuation in your query is not interpreted as pattern syntax. Contents mode searches regular files with `grep`, searches text-based PDFs with PDFKit, searches `.docx` Word document text in-process, and returns each matching file once. Scanned or image-only PDFs are not OCRed, and legacy `.doc` files are not supported. The Extensions field narrows which files are searched; unlike Names mode, content search requires a text query.

When Case sensitive is off, ScopedFind adds Unicode-aware, diacritic-insensitive fallback matching for names and supported file contents. For example, `sevket` can match `şevket`. Case-sensitive searches stay literal.

## Why Not Finder Search?

Finder and Spotlight are excellent for broad macOS search, but they often combine filename matches and file-content matches. That can be confusing when you only want to know whether a file or folder with a specific name exists.

| Need | Finder search | ScopedFind |
| --- | --- | --- |
| Find by filename only | Can mix filename and content matches | Names mode searches names only |
| Search file text without Spotlight | Depends on indexing and metadata behavior | Contents mode uses `/usr/bin/grep`, PDFKit, and the DOCX reader directly |
| Search exactly one chosen folder tree | Can be broad depending on scope and Spotlight behavior | Stays inside the folder you choose |
| Search without Spotlight indexing | Depends on macOS indexing behavior | Uses `/usr/bin/find`, `/usr/bin/grep`, PDFKit, and the DOCX reader directly |
| Filter folders/apps vs regular files | Not the main workflow | Built-in Result type menu in Names mode |
| Filter by extension | Possible, but not always obvious | Dedicated Extensions field |

In Names mode, the basic contains match is equivalent to:

```bash
/usr/bin/find "/selected/folder" -iname "*query*"
```

By default, ScopedFind also excludes hidden files and folders. When case-sensitive search is enabled, ScopedFind uses `-name` instead of `-iname`. When files-only or folders/apps-only search is selected, it adds the matching `find` type predicate.

The Extensions field is optional. It accepts extensions with or without a leading dot, separated by commas, semicolons, spaces, or newlines. For example, `swift,md` matches `.swift` and `.md` files. You can search by extension only without entering a filename query.

In Contents mode, text-file search is equivalent to `find` enumerating regular files and running `grep` over them:

```bash
/usr/bin/find "/selected/folder" -type f -exec /usr/bin/grep -I -l --null -F -i -e "query" {} +
```

When Extensions are set in Contents mode, the `find` step filters files by extension before running `grep`.

PDF files are handled as a second dependency-free pass. ScopedFind enumerates matching PDFs with `find`, then extracts searchable text with Apple's PDFKit:

```bash
/usr/bin/find "/selected/folder" -type f -iname "*.pdf" -print0
```

DOCX files are handled as another dependency-free pass. ScopedFind enumerates matching DOCX files with `find`, opens the `.docx` ZIP structure in-process, and searches Word document XML text:

```bash
/usr/bin/find "/selected/folder" -type f -iname "*.docx" -print0
```

If the Extensions field is empty, PDF and DOCX files are included. If Extensions are set, the PDF or DOCX pass runs only when the matching extension is included.

### Searching Applications

macOS apps are usually `.app` bundles, which the Unix filesystem treats as directories. In Names mode, if you search inside `/Applications`, keep Result type set to `Files and folders` or use `Folders/apps only`. A `Files only` search will not return `.app` bundles.

Some Apple/system apps may also live in `/System/Applications` instead of `/Applications`, so choose that folder if the app you expect is not found.

## Building Locally

When you are happy with the app, you can build it once and use it like a normal macOS app:

1. Open `ScopedFind.xcodeproj` in Xcode.
2. Select the `ScopedFind` scheme and `My Mac`.
3. Choose `Product > Build`.
4. Choose `Product > Show Build Folder in Finder`.
5. Open `Products/Debug` or `Products/Release`.
6. Drag `ScopedFind.app` into `/Applications`.

After that, you can launch ScopedFind from Applications, Spotlight, or your Dock without opening Xcode.

## Folder Access

The first version uses the folder access granted by the native macOS folder picker for the current app session. The code is structured so security-scoped bookmarks can be added later if persistent access is needed.

## Project Scope

This is a personal, single-maintainer project published for source transparency. Issues are open for bug reports and small questions, but pull requests are intentionally disabled because the project is not intended to be community-maintained.

## License

MIT License. See `LICENSE`.
