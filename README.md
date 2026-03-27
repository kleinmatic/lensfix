# lensfix

A collection of EXIF metadata tools for photographers who shoot with vintage or manual lenses that don't communicate electronically with the camera body.

Requires [exiftool](https://exiftool.org/).

## Tools

### lensfix.py

Writes lens metadata (make, model, focal length, max aperture, serial number) into photo EXIF data using a personal lens database stored in a CSV file. By default, creates a copy of the file before modifying it.

```bash
# List available lenses
./lensfix.py --list

# Show details for a specific lens
./lensfix.py --info takumar_55

# Apply lens metadata to a photo (creates a -lensfix copy)
./lensfix.py --lens takumar_55 photo.jpg

# Apply to multiple photos, modifying originals in place
./lensfix.py --lens takumar_55 --unsafe *.jpg
```

### datefix.py

Sets EXIF date fields (DateTimeOriginal, CreateDate, ModifyDate) on photos that have missing or incorrect dates. Useful for scanned photos or files with corrupted date metadata. Creates a copy by default.

```bash
# Set dates to the current time
./datefix.py --now photo.jpg

# Set dates to the file's OS creation time
./datefix.py --creation photo.jpg

# Modify in place
./datefix.py --now --unsafe photo.jpg
```

### lens-info.py

Checks photos for missing FocalLength EXIF data and applies a red macOS Finder tag to flag files that need lens metadata added. Useful as a first pass before running lensfix.

```bash
./lens-info.py *.jpg
```

## Setup

1. Install exiftool: `brew install exiftool` (macOS) or `sudo apt install libimage-exiftool-perl` (Debian/Ubuntu)
2. Copy `lensfix.csv.example` to `lensfix.csv` and add your own lenses
3. Make scripts executable: `chmod +x lensfix.py datefix.py lens-info.py`

## Lens Database

The lens database is a CSV file (`lensfix.csv`) with the following columns:

| Column | Description |
|--------|-------------|
| nickname | Short name used on the command line |
| Lens | Full lens name written to EXIF |
| LensMake | Manufacturer |
| LensModel | Model name |
| LensSerialNumber | Serial number |
| MaxApertureValue | Maximum aperture (numeric) |
| FocalLength | Focal length with units (e.g. 50mm) |
| FocalLengthIn35mmFormat | 35mm equivalent focal length |

See `lensfix.csv.example` for the format. The actual `lensfix.csv` is gitignored since it may contain personal lens serial numbers.
