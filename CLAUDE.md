# Beanbox — engineering notes

Native iOS/iPadOS 26 app that measures the colours of origami paper and jelly beans from
photos, pairs every flavour with its best sheet, and splits piles of look-alike beans into
groups. Swift 6, SwiftUI. Everything runs on the device.

It is the native successor of the `beanbox` service in the homelab repo (FastAPI + React);
`BeanCore` is a port of that service's Python, pinned to it by reference values in
`ColorScienceTests`.

## Layout

- `Package.swift`, `Sources/BeanCore` — portable, dependency-free core (builds on Linux too).
  - `ColorScience.swift` camera RGB → white-balanced CIELAB (Bradford adaptation, sRGB and
    Display P3 primaries), CIEDE2000, Lab → display colour, `PixelImage`.
  - `Sampling.swift` the colour under a tap (`sample`), the white under a tap or guessed
    (`autoWhite`), `bodyColor` (trimmed median that ignores glints and contact shadow).
  - `Matching.swift` flavour → sheet assignment (`Matching.solve`, Hungarian in `Assignment`).
  - `Sorting.swift` the sorter (`Sorting.analyze`; pipeline in its doc comment), with
    `Raster.swift` (morphology, connected components, exact distance/nearest-site transform)
    and `Clustering.swift` (Ward, silhouette, 3×3 eigen).
- `Tests/BeanCoreTests` — Swift Testing. `Synth.swift` renders synthetic photos (look-alike
  trios for five colour families, on white paper or a dark sheet, under warm uneven light).
- `App/` — Xcode project (`BeanBox.xcodeproj`, synchronized folders: adding files needs no
  project edits) with the SwiftUI app.
- `tools/` — `swift.sh`, `icon/make_icon.py`.
- `ci/`, `.github/workflows/ci.yml` — see CI below.

## Building & testing on Linux (no Xcode here)

- `tools/swift.sh test` — runs the package tests in the `swift:6.2-noble` Docker image
  (a few seconds; both targets are compiled `-O`, the tests render megapixel images).
- The app itself only compiles on CI's macOS runner. See the feedback loop below.

## Invariants

- **Every stored Lab value is relative to its photo's white paper**, pinned to
  `ColorScience.whiteY` (L* ≈ 96). That is what makes photos comparable. Changing `whiteY`
  or the adaptation invalidates every saved measurement.
- **Photos are Display P3.** `PhotoLoader` renders every photo into P3 and the core applies
  the P3 → XYZ matrix when measuring. Converting to sRGB first would clip the saturated reds
  the sorter has to tell apart.
- **The sorter and the tap sampler adapt in the same (Bradford cone) space**, so a group
  saved from a sort is comparable with a tapped sample. Don't change one without the other.
- **Changing a photo's white re-measures its tapped samples** (`Project.setWhite`). Colours
  saved from a sorted group have no tap and are not re-measured.
- **Saved data** is `Application Support/Project/project.json` (`ProjectData`) beside the
  photos' original files. Add fields with defaults; never rename them.
- **The interface is neutral grey and light-only on purpose**: a coloured or dark surround
  shifts how a swatch looks.
- **Group colours** (`Theme.groups`) are six hues from the dataviz reference palette validated
  for all-pairs use. Beans can be any colour, so identity never rests on the ring colour
  alone: every ring has a contrasting casing and is paired with the group letter.
  `Sorting.maxGroups` is tied to their count.

## Sorter notes

- The sheet is whatever colour fills most of the frame (`dominant`). Darker-than-sheet is
  down-weighted (`shadowLWeight`) so cast shadows stay background; lighter-than-sheet counts
  in full once the lighting is flattened, which is what makes pale beans visible on a dark
  sheet.
- Where the white comes from (`referenceWhite`), in order: the sheet itself if it is neutral
  and nothing sizeable outshines it; the photo's tapped white; white paper showing around a
  dark sheet (bright neutral pixels in components that hug the frame, so white beans never
  qualify); otherwise the result is flagged `calibrated: false` and the app refuses to save
  its groups as flavours.
- `coreDepth` trades splitting touching beans against cutting single beans in two.
- Unsupported: pale beans on white paper, dark beans on a dark sheet, and speckles (body
  colour is a trimmed median, so speckled and plain beans of one base colour group together).
- Thresholds are reasoned and tested on synthetic photos, not tuned on real ones. When a
  real photo goes wrong, reproduce it in `Synth` first.

## App (App/)

- `Model/Project.swift` — `@Observable` store of photos, samples and locks; decodes and sorts
  off the main actor (`@concurrent` static functions), everything else on it.
- `Features/Shell` — tabs, `PhotoCanvas` (photo + annotations in photo pixels, taps reported in
  photo pixels), `PhotoStrip` (camera / library intake shared by the tabs).
- `Features/Sampler` — Papers and Beans tabs (one view, two kinds).
- `Features/Match`, `Features/Sort` (overlay, `GroupChart`), `Features/Mat` (printable dark
  sorting mat).
- The app target isolates to the main actor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION`);
  value types and helpers used off it are marked `nonisolated`.
- Demo scenarios (`App/DemoMode.swift`, Debug only): `-demo <name>` fills a scratch project
  with synthetic photos through the same calls a person's taps make, so each CI screenshot
  also proves the real decode → measure → sort path. `ci/scenarios.txt` lists them;
  `Launch` maps a scenario to the interface state it shows.

## CI feedback loop (no Xcode locally)

1. Commit, push to a branch: `git push -u origin HEAD:<branch>` (CI runs on every branch).
2. Run `CI_BRANCH=<branch> ci/fetch.sh <sha> <outdir>` in the background; it waits for the
   report CI publishes to `ci-shots/<branch>`: `STATUS.md` (job results), trimmed `*.log`,
   `core/core-test.log`, `iphone/errors.txt` (compiler errors and Release-check failures),
   `iphone/shots/*.png` plus `*-app.log` and `*-steps.log`, and `ipa/errors.txt`.
3. Read errors and screenshots, fix, repeat. Batch fixes; one validated push beats many guesses.
4. Device builds: every branch archives an unsigned Release IPA (so device-only failures show
   early); pushes to `main` also publish it as the `build-<run>` prerelease (the five newest
   are kept) and rewrite the SideStore source on the `sidestore` branch
   (`ci/sidestore_source.py`). Work on `dev`; merge to `main` to ship.

## Conventions

- Swift 6 language mode, strict concurrency. Core types are `Sendable` value types.
- Keep `BeanCore` free of Apple-only frameworks.
- Deterministic output for identical inputs.
- Comments explain *why*, sparingly. No dead code, no TODO litter.
