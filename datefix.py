#!/usr/bin/env python3
import subprocess
import sys
import os
from datetime import datetime
import shutil
import argparse

def update_exif_dates(filename, mode, unsafe=False):
    if not unsafe:
        base, ext = os.path.splitext(filename)
        new_filename = f"{base}-datefix{ext}"
        shutil.copy2(filename, new_filename)
        filename = new_filename
        print(f"Created a copy of the file: {new_filename}")

    try:
        if mode == "now":
            subprocess.run([
                'exiftool',
                '-overwrite_original',
                '-DateTimeOriginal=now',
                '-CreateDate=now',
                '-ModifyDate=now',
                filename
            ], check=True)
            print(f"EXIF dates updated to now for {filename}")
        elif mode == "creation":
            creation_time = datetime.fromtimestamp(os.path.getctime(filename)).strftime('%Y:%m:%d %H:%M:%S')
            subprocess.run([
                'exiftool',
                '-overwrite_original',
                f'-DateTimeOriginal={creation_time}',
                f'-CreateDate={creation_time}',
                f'-ModifyDate={creation_time}',
                filename
            ], check=True)
            print(f"EXIF dates updated to creation time for {filename}")
        else:
            print("Invalid mode. Use --now or --creation.")
            sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Error updating EXIF dates for {filename}: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Update EXIF dates of file(s).")
    parser.add_argument("filename", nargs="+", help="The name(s) of the file(s) to update.")

    mode_group = parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument("--now", action="store_true", help="Update dates to now")
    mode_group.add_argument("--creation", action="store_true", help="Update dates to file creation time")

    parser.add_argument("--unsafe", action="store_true", help="Make changes without creating a new file.")

    args = parser.parse_args()

    mode = "now" if args.now else "creation"
    for file in args.filename:
        update_exif_dates(file, mode, args.unsafe)