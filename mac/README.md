# Lensfix (Mac app)

A native macOS GUI for tagging photos shot with vintage / manual lenses that
don't report their identity to the camera. It's the GUI counterpart to the
`lensfix.py` CLI in the parent directory — a **pre-import** workflow: fix the
files, *then* import them into Lightroom (no catalog round-trip, no plugin).

## What it does

- Open a folder or drag in photos (JPEG, HEIC, TIFF, and most RAW formats)
- Thumbnail grid; photos **missing a focal length** get a red badge
- **Select untagged** (or hand-pick), enter lens fields once, **Apply to selection**
- Writes EXIF via `exiftool` (same fields as the CLI: Lens, LensMake, LensModel,
  LensSerialNumber, MaxApertureValue, FocalLength, FocalLengthIn35mmFormat)
- "Keep original as backup" leaves a `<name>_original` copy (on by default)

## Requirements

- macOS 13+
- `exiftool` on PATH (`brew install exiftool`) — the app looks in the usual
  Homebrew/`which` locations and shows a banner if it's missing

## Run it

Built as a Swift Package so it runs with the Command Line Tools (no full Xcode):

```bash
cd mac
swift run          # debug build, launches the app
```

For a faster build: `swift run -c release`.

## Build a double-clickable app

To produce a real `Lensfix.app` you can keep in `/Applications` or the Dock:

```bash
cd mac
./build-app.sh          # -> dist/Lensfix.app
open dist/Lensfix.app    # or double-click it in Finder
```

`build-app.sh` builds the release binary, assembles the `.app` bundle
(`Info.plist` + generated icon), and **ad-hoc code-signs** it. This needs only
the Command Line Tools (`swift`, `codesign`, `iconutil`) — not full Xcode. The
app is ignored by git (`mac/dist/`); rebuild it any time from source.

Because it's ad-hoc signed and built locally, it launches without a Gatekeeper
prompt on *this* machine.

## Sharing the app with other people

Ad-hoc signing is fine for your own Mac, but if you send `Lensfix.app` to
someone else, macOS Gatekeeper will flag it as coming from an unidentified
developer (they can still run it via right-click → Open). To distribute without
that friction you need:

1. An **Apple Developer account** ($99/yr) and a **Developer ID Application** certificate
2. Sign with it: `codesign --force --options runtime --sign "Developer ID Application: …" dist/Lensfix.app`
3. **Notarize** with `xcrun notarytool submit` (notarytool ships with full Xcode) and `xcrun stapler staple dist/Lensfix.app`
4. Ship it as a zip or DMG

Also note: the app expects `exiftool` on the machine (Homebrew locations are
auto-detected). A recipient without it sees a banner; bundling a standalone
`exiftool` inside the app is a possible future step.

## Not yet built (roadmap)

- Dated `ImageDescription` stamp for self-documenting files (CLI parity)
- Bundled `exiftool` so the app is self-contained
- Developer ID signing + notarization for frictionless distribution
- Recursive folder scanning (currently top-level only)
