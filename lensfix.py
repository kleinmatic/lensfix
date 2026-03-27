#!/usr/bin/env python3

# Add photo lens metadata when using lenses that don't send data to camera.
# Confirmed safe by Phil Harvey 3/16/2025 https://exiftool.org/forum/index.php?topic=17196.0
# Requires lensfix.csv in same directory with columns: 
#   nickname, Lens, LensMake, LensModel, LensSerialNumber, MaxApertureValue,
#   FocalLength, FocalLengthIn35mmFormat

import csv
import subprocess
import sys
import os
import shutil
import argparse
import re
from datetime import datetime

# Function to load the lens database from a CSV file.
# The CSV should have a header row with: nickname, Lens, LensMake, LensModel, etc.
def load_lens_database(csv_path):
    lenses = {}
    try:
        with open(csv_path, newline='', encoding='utf-8') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                # 'nickname' column is used as key; remove it from the row dict if desired.
                nickname = row.pop('nickname')
                lenses[nickname] = row
    except FileNotFoundError:
        print(f"Error: CSV file '{csv_path}' not found.")
        sys.exit(1)
    return lenses

# Determine the absolute path of the CSV file relative to this script.
script_dir = os.path.dirname(os.path.abspath(__file__))
csv_path = os.path.join(script_dir, "lensfix.csv")
# Load lenses from the CSV.
LENSES = load_lens_database(csv_path)

# Return the current ImageDescription of the photo.
def get_current_image_description(photo):
    """
    Return the current ImageDescription of the photo.
    """
    try:
        result = subprocess.check_output(["exiftool", "-s3", "-ImageDescription", photo])
        return result.decode().strip() if result else ""
    except subprocess.CalledProcessError:
        return ""

# Build a new ImageDescription that appends or updates the lens comment.
def build_new_image_description(desc):
    """
    Build a new ImageDescription that appends or updates the lens comment.
    The comment will be in the format:
      Lens information added by a python script YYYY-MM-DD
    """
    comment_tag = "Lens information added by a python script"
    current_date = datetime.now().strftime('%Y-%m-%d')
    if comment_tag in desc:
        new_desc = re.sub(rf'{comment_tag} \d{{4}}-\d{{2}}-\d{{2}}',
                          f'{comment_tag} {current_date}', desc)
        if new_desc == desc:
            new_desc = desc + "\n" + f"{comment_tag} {current_date}"
    else:
        new_desc = f"{desc}\n{comment_tag} {current_date}" if desc else f"{comment_tag} {current_date}"
    return new_desc

# Build the exiftool command that updates the underlying lens fields and ImageDescription.
def build_exif_command(photo, lens_nickname, new_desc):
    """
    Return the exiftool command list to update lens metadata and ImageDescription.
    Note: We do not write to LensInfo so that exiftool recalculates it.
    """
    cmd = ["exiftool", "-overwrite_original"]
    # Write all underlying lens fields.
    for key, value in LENSES[lens_nickname].items():
        cmd.append(f"-{key}={value}")
    cmd.append(f"-ImageDescription={new_desc}")
    cmd.append(photo)
    return cmd

# Update lens metadata and ImageDescription for one photo.
def update_photo_file(photo, lens_nickname, unsafe=False):
    """
    Update lens metadata and ImageDescription for one photo.
    If not in unsafe mode, a copy of the file is created.
    """
    if lens_nickname not in LENSES:
        print(f"Error: Lens '{lens_nickname}' not found.")
        print("Available lenses:")
        for key in LENSES.keys():
            print(f"  - {key}")
        sys.exit(1)

    # Create a copy of the file if in safe mode.
    if not unsafe:
        base, ext = os.path.splitext(photo)
        new_photo = f"{base}-lensfix{ext}"
        shutil.copy2(photo, new_photo)
        photo = new_photo
        print(f"Created a copy of the file: {new_photo}")

    # Retrieve the current ImageDescription and build the new description.
    current_desc = get_current_image_description(photo)
    new_desc = build_new_image_description(current_desc)
    
    # Build and execute the exiftool command.
    cmd = build_exif_command(photo, lens_nickname, new_desc)
    try:
        subprocess.run(cmd, check=True)
        print(f"Successfully updated '{photo}' with lens metadata: {lens_nickname}")
    except subprocess.CalledProcessError as e:
        print(f"Error: Failed to update metadata for '{photo}'.\n{e}")
        sys.exit(1)

# List available lenses in short form (displaying the key and the 'Lens' field).
def list_lenses_short():
    """
    Print a short listing of available lenses and exit.
    """
    print("Available lenses:")
    for nickname in sorted(LENSES.keys()):
        # Display the nickname and the 'Lens' field.
        print(f"  {nickname}: {LENSES[nickname].get('Lens', 'N/A')}")
    sys.exit(0)

# Show detailed info for a specific lens.
def info_lens(lens_nickname):
    """
    Print detailed info for a specific lens and exit.
    """
    if lens_nickname not in LENSES:
        print(f"Error: Lens '{lens_nickname}' not found.")
        sys.exit(1)
    print(f"Detailed info for '{lens_nickname}':")
    for key, value in LENSES[lens_nickname].items():
        print(f"  {key}: {value}")
    sys.exit(0)

# Main execution block.
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Apply lens metadata to photos.")
    parser.add_argument("--lens", "-l", help="Lens nickname to use")
    parser.add_argument("photo", nargs="*", help="Photo filename(s)")
    parser.add_argument("--unsafe", action="store_true",
                        help="Modify the original file(s) without creating copies")
    parser.add_argument("--list", action="store_true",
                        help="List available lenses (display key and 'Lens' field) and exit")
    parser.add_argument("--info", help="Show detailed info for a specific lens and exit")
    args = parser.parse_args()

    if args.list:
        list_lenses_short()
    if args.info:
        info_lens(args.info)
    if not (args.lens and args.photo):
        parser.error("the following arguments are required: --lens and photo filename(s) (or use --list/--info to display lens info)")
    for photo in args.photo:
        update_photo_file(photo, args.lens, args.unsafe)
