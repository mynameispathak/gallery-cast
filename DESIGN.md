# Gallery Cast — Design System

One page, three token layers, component specs with states, and the
anti-patterns the UI deliberately avoids. All values live in
`Sources/GalleryCast/Design/DesignTokens.swift`; views reference tokens,
never literals.

## Philosophy

A photo viewer's UI should recede. The strategy is **content-first
minimalism**: one accent color, near-black presentation surfaces, native
materials for chrome, and motion measured in tenths of a second. Nothing
decorative competes with a photograph.

## Style

macOS-native. Standard window chrome, sidebar, unified toolbar, and SF
Symbols throughout. Custom visual language is limited to two signatures:
the warm amber accent and the floating dark control pill.

## Color

### Primitive

| Token        | Value                        | Note                  |
|--------------|------------------------------|-----------------------|
| `amber`      | `#FF9500`                    | The single brand hue  |
| `viewerBlack`| `#0A0A0D`                    | Near-black backdrop   |

### Semantic

| Token             | Purpose                                  |
|-------------------|------------------------------------------|
| `Surface.viewer`  | Photo presentation — always dark         |
| `Surface.viewerChrome` | Floating controls over the viewer    |
| `Accent.primary`  | Selection, active toggles, tint        |
| `Ink.primary/secondary/tertiary` | Adaptive text hierarchy (100%/62%/40%) |
| `Ink.onChrome`    | Text on the dark control pill (92% white)|

Everything else uses system semantic colors, so light/dark mode parity
comes from AppKit, not from a maintained dark palette.

## Typography

SF Pro only, at system styles: `.largeTitle` semibold (welcome title),
`.title3`/`.headline` (empty state, panel titles), `.body`, `.callout`
(header bar), `.caption`/`.caption2` (metadata labels). Monospaced
(`.system(.caption, design: .monospaced)`) is reserved for data: EXIF
values and file names in the info panel.

## Spacing, radius, motion

- **Spacing:** 2/4/8/12/16/20/24/32/48/72 (`Token.Space`)
- **Radius:** 6 (thumbs), 10 (medium), 14 (chrome) (`Token.Radius`)
- **Motion:** 0.18s hover, 0.28s chrome, 0.45s photo change, 0.6s
  intended crossfade; chrome auto-hides after 2.5s idle
  (`Token.Duration`)

## Component specs

### Grid thumbnail

| Property | Default   | Hover          | Selected           |
|----------|-----------|----------------|--------------------|
| Fill     | placeholder 5% | image     | image              |
| Scale    | 1.0       | 1.02           | 1.0                |
| Shadow   | none      | black 25% r12  | none               |
| Border   | none      | none           | amber 3pt inset    |
| Overlay  | none      | filename scrim  | none               |

### Viewer control (chrome pill)

| Property | Default          | Active/toggled    |
|----------|------------------|-------------------|
| Icon     | white 92%        | amber             |
| Backdrop | none             | white 10% circle |
| Pill     | black 55%, radius 14, 1pt white 8% hairline | — |

### Empty states

Icon 44pt light, tertiary ink; `.title3` semibold title; `.body`
secondary message; centered with generous (48pt) padding. No decorative
illustrations.

## Motion rules

- Slideshow photo changes: ease-in-out 0.45s fade.
- Manual navigation: same fade — one motion language, not two.
- Chrome show/hide: ease-out 0.28s; only auto-hides while playing.
- Hover effects: ease-out 0.18s.

## Anti-patterns avoided

- **Flash of light content in the viewer.** The viewer surface is pinned
  dark in both appearances; opening a photo never strobes white.
- **Blocking the main thread.** All decode goes through actors; the grid
  and viewer stay responsive with multi-megabyte files.
- **Decorative gradients.** The only gradient is a functional scrim under
  hovered filenames.
- **Modal-heavy flow.** Browsing, viewing, and slideshow states are all
  inline; only the folder picker is modal, because the OS panel is.
- **Position-keyed viewer state.** The viewer tracks a photo by
  identity, so filtering or re-sorting mid-session never teleports it.
- **Overloaded menus.** Three commands do real work; everything else is
  discoverable in the toolbar or via keyboard.

## Pre-delivery checklist

- [x] Every color/spacing/duration value in views comes from a token
- [x] Text hierarchy has three levels, no more
- [x] Every interactive element has hover/active/disabled states
- [x] Empty states exist for: no folder, no photos, no search matches
- [x] Keyboard paths exist for all primary actions
- [x] Motion durations specified and consistent
- [x] Dark and light appearances both supported (viewer intentionally dark)
