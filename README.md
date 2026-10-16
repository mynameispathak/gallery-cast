# Gallery Cast

A native Mac app for browsing the photos in any folder and playing them
as a slideshow. Built with SwiftUI; designed to stay out of the photo's way.

## Features

- **Folder browsing** — pick any folder; its photos appear in a responsive
  grid (JPEG, PNG, HEIC, HEIF, WebP, GIF, TIFF, BMP, AVIF). The scan is
  flat (subfolders are not included) and recent folders are remembered.
- **Viewer** — double-click a photo for a full-window, dark-surface
  presentation with zoom (pinch, `+`/`-`, double-click), pan, and
  keyboard navigation.
- **Slideshow** — plays through the folder in the current grid order
  (name or date), with a configurable interval (2/5/10/15 s), crossfade
  transitions, and controls that hide themselves while playing.
- **Info panel** — EXIF capture data (camera, lens, ISO, aperture,
  shutter, focal length, taken date) plus file details.
- **Search & sort** — filter by filename, sort naturally by name or by
  date; the slideshow always follows the order you see.

## Requirements

- macOS 14 or later
- Xcode with Swift 6 (Command Line Tools alone cannot compile SwiftUI on
  this SDK generation — the SwiftUIMacros plugin ships only with Xcode)

## Build & run

From the repository root:

```bash
swift run                 # debug build, launches immediately
swift test                # unit tests
scripts/build-app.sh      # debug .app bundle
scripts/build-app.sh release   # optimized .app bundle
```

The bundle script produces `GalleryCast.app` — double-click it, or
`open GalleryCast.app`, for proper Dock/menu-bar behavior. The plain
binary (`swift run`) also works for development.

## Keyboard shortcuts

| Key             | Action                          |
|-----------------|---------------------------------|
| `⌘O`            | Open a folder                   |
| `←` / `→`       | Previous / next photo (viewer)  |
| `Space`         | Start / pause the slideshow     |
| `⌘⇧P`           | Play / pause the slideshow      |
| `+` / `-` / `0` | Zoom in / out / reset           |
| `I`             | Toggle the info panel           |
| `F`             | Toggle full screen              |
| `Esc`           | Reset zoom, then close viewer   |

## Project structure

```
Sources/GalleryCast/
├── GalleryCastApp.swift        App entry, menus, shortcuts
├── Design/DesignTokens.swift   Design system (all values, no literals)
├── Models/                     Photo + PhotoLibrary (scan, sort, filter)
├── Services/                   Images, EXIF, slideshow state machine, folder picker
├── State/AppModel.swift        Single source of truth for UI state
└── Views/                      Grid, viewer, slideshow chrome, sidebar, panels
Tests/GalleryCastTests/         Scan/sort/filter and slideshow tests
scripts/build-app.sh            .app bundle builder
```

The UI never touches the file system directly: `AppModel` owns the photo
list, the viewer tracks photos by identity, and all image decoding
happens off the main actor with a modification-time-aware cache.

## Roadmap

- **Casting to Android TV** — discover Chromecast-enabled devices on the
  local network via Bonjour (`_googlecast._tcp`) and stream the current
  slideshow using the Cast V2 protocol. The slideshow already renders from
  a single ordered photo source, so a cast sink is just one more consumer
  of that stream. This is the next planned feature.
- App icon and about panel
- Recursive folder scanning option
- RAW format support (DNG, CR3, NEF…)
- Slideshow transitions (Ken Burns, wipe) and multi-select
