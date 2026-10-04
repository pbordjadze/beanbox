# Beanbox

A small native iOS app for a craft project: folding an origami masu box for every flavour in a
tub of jelly beans, each box made from the sheet of paper that best matches its bean.

It answers two questions from photos, entirely on the device:

- **Which sheet for which flavour?** Tap sheets and beans in photos to measure their colours;
  the app gives every flavour its own sheet so that the whole set matches as well as it can.
- **Which beans are the same flavour?** Photograph a pile of look-alikes; every bean is found,
  measured and lettered by group.

## How it works

- **Measuring.** Each photo is balanced against the white paper in it (one tap), so colours
  from photos taken at different moments are comparable. Colours are CIELAB; iPhone photos are
  read as Display P3, so saturated reds aren't clipped before they are measured.
- **Matching.** One sheet per flavour by the assignment (Hungarian) method over squared
  CIEDE2000, with lightness half-weighted. Lock the pairs you fold; the rest re-solves.
- **Sorting.** The photo is flat-fielded against the sheet the beans lie on, every bean is
  segmented and measured, and the beans are clustered. An exaggerated-colour view and a scatter
  plot show whether the groups are real. White and cream beans go on a dark sheet (the app
  prints one) with some white paper showing.

## Install with SideStore

Add this source in SideStore (Sources → +):

    https://raw.githubusercontent.com/pbordjadze/beanbox/sidestore/source.json

SideStore signs the app with your Apple ID and offers each new build as an update.

## Privacy

No accounts, no analytics, no network code. Photos and measurements stay on the device.

## Project layout

| Path | What |
| --- | --- |
| `Sources/BeanCore` | Colour maths, sampling, matching and the sorter: pure Swift, no dependencies |
| `Tests/BeanCoreTests` | Swift Testing suite, run on Linux and macOS |
| `App/` | Xcode project: the SwiftUI app |
| `tools/` | `swift.sh` (Swift in Docker), the icon generator |
| `ci/`, `.github/workflows/` | CI: Linux core tests, macOS build with simulator screenshots, SideStore builds |

## Building

Open `App/BeanBox.xcodeproj` in Xcode 26 and run the `BeanBox` scheme (iOS 26). The core also
builds and tests with plain SwiftPM:

```sh
swift test
```

See `CLAUDE.md` for development notes.
