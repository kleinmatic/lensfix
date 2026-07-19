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

## Not yet built (roadmap)

- Lens **presets** (the CLI's nickname/CSV database, reborn as a GUI feature)
- Dated `ImageDescription` stamp for self-documenting files (CLI parity)
- Bundled `exiftool` + a signed/notarized `.app` for sharing (needs Xcode)
- Recursive folder scanning (currently top-level only)
