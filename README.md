# ScopedFind

ScopedFind is a small native macOS app that wraps macOS's built-in `/usr/bin/find` command in a SwiftUI interface.

The app searches only inside a folder you explicitly choose. It searches file and folder names only, not file contents. It is an MVP for quick filename searches, not a Finder replacement.

![ScopedFind screenshot](docs/screenshot.png)

## Download

Download the latest DMG from the [Releases](https://github.com/dodoturkoz/ScopedFind/releases) page.

The release DMG is currently unsigned and not notarized. If macOS warns that it cannot verify the app, try the normal macOS approval flow first:

1. Drag `ScopedFind.app` into `/Applications`.
2. Control-click `ScopedFind.app`, choose Open, then confirm Open if macOS offers it.
3. If macOS still blocks the app, open System Settings > Privacy & Security and look for an Open Anyway button for ScopedFind.

As an advanced fallback, if you downloaded ScopedFind from this repository and trust this copy of the app, you can remove macOS's quarantine flag from that app bundle:

```bash
xattr -dr com.apple.quarantine /Applications/ScopedFind.app
```

Use the real app path if it is somewhere else, such as `~/Downloads/ScopedFind.app`. Do not run this command for apps you do not trust; it bypasses macOS's quarantine warning for that copy of the app.

Building from source is still available for users who prefer to inspect and compile the app themselves.

## Features

- Native Swift and SwiftUI macOS app
- Native folder picker
- Case-sensitive or case-insensitive filename search
- Optional extension filtering, such as `swift`, `.pdf`, or `jpg,png`
- Contains or fuzzy filename matching
- Searches file and folder names only, not file contents
- Recursive search inside the selected folder
- Result type filtering for files only, folders/apps only, or both
- Optional hidden-file search
- Optional auto-search after typing pauses
- Streaming results while `/usr/bin/find` is still running
- Cancel button for active searches
- Double-click to open results
- Context menu actions for Open, Reveal in Finder, and Copy Path

## Privacy

ScopedFind is intentionally local and transparent.

- It makes no network requests.
- It contains no analytics, telemetry, ads, crash-reporting SDK, tracking SDK, updater, launch agent, or background service.
- It does not request Full Disk Access.
- It searches only inside the folder you choose.
- It searches names only and does not read file contents.
- It executes only `/usr/bin/find`.
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

ScopedFind searches file and folder names only. It does not search inside documents, PDFs, text files, source files, or other file contents.

When Auto search is enabled, ScopedFind starts a new search about 1.2 seconds after you stop typing or change a search option.

The Name match control has two modes:

- Contains: `report` matches names containing `report`.
- Fuzzy: `sf` matches names where `s` and `f` appear in that order, such as `ScopedFind`. Spaces in the query are ignored in fuzzy mode.

## Why Not Finder Search?

Finder and Spotlight are excellent for broad macOS search, but they often combine filename matches and file-content matches. That can be confusing when you only want to know whether a file or folder with a specific name exists.

| Need | Finder search | ScopedFind |
| --- | --- | --- |
| Find by filename only | Can mix filename and content matches | Always names only |
| Avoid PDF/document text hits | Often returns content matches | Never reads file contents |
| Search exactly one chosen folder tree | Can be broad depending on scope and Spotlight behavior | Stays inside the folder you choose |
| Search without Spotlight indexing | Depends on macOS indexing behavior | Uses `/usr/bin/find` directly |
| Filter folders/apps vs regular files | Not the main workflow | Built-in Result type menu |
| Filter by extension | Possible, but not always obvious | Dedicated Extensions field |

In Contains mode, the basic name match is equivalent to:

```bash
/usr/bin/find "/selected/folder" -iname "*query*"
```

By default, ScopedFind also excludes hidden files and folders. When case-sensitive search is enabled, ScopedFind uses `-name` instead of `-iname`. When files-only or folders/apps-only search is selected, it adds the matching `find` type predicate.

The Extensions field is optional. It accepts extensions with or without a leading dot, separated by commas, semicolons, spaces, or newlines. For example, `swift,md` matches `.swift` and `.md` files. You can search by extension only without entering a filename query.

### Searching Applications

macOS apps are usually `.app` bundles, which the Unix filesystem treats as directories. If you search inside `/Applications`, keep Result type set to `Files and folders` or use `Folders/apps only`. A `Files only` search will not return `.app` bundles.

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
