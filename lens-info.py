#!/usr/bin/env python3

import subprocess
import sys
import os

def check_lens_info(filepath):
    try:
        # Run exiftool to get FocalLength info
        result = subprocess.run(
            ['exiftool', '-FocalLength', filepath],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        if result.returncode != 0:
            print(f"Error reading file {filepath}: {result.stderr}")
            return None

        focal_found = False
        for line in result.stdout.splitlines():
            if "Focal Length" in line:
                focal_found = True
                parts = line.split(':', 1)
                if len(parts) < 2 or parts[1].strip() == "":
                    return False
                # Extract numeric value from output like "50.0 mm"
                value_str = parts[1].strip().split()[0]
                try:
                    focal_value = float(value_str)
                    if focal_value == 0:
                        return False
                    else:
                        return True
                except ValueError:
                    return False
        # If no "Focal Length" found, treat it as missing.
        if not focal_found:
            return False
        return True

    except Exception as e:
        print(f"Error processing {filepath}: {e}")
        return None

def apply_red_tag(filepath):
    try:
        # Red is label index 6 in Finder
        subprocess.run(
            ['xattr', '-w', 'com.apple.FinderInfo', '', filepath],
            stderr=subprocess.DEVNULL
        )
        subprocess.run(
            ['osascript', '-e', f'tell application "Finder" to set label index of (POSIX file "{filepath}" as alias) to 6']
        )
        print(f"Applied red tag to: {filepath}")
    except Exception as e:
        print(f"Failed to apply red tag to {filepath}: {e}")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tag_missing_lens.py /path/to/file [additional files...]")
        sys.exit(1)
    
    for filepath in sys.argv[1:]:
        if not os.path.isfile(filepath):
            print(f"File not found: {filepath}")
            continue

        # Convert relative path to absolute to ensure Finder can locate the file
        filepath = os.path.abspath(filepath)

        has_lens_info = check_lens_info(filepath)

        if has_lens_info is False:
            apply_red_tag(filepath)
        elif has_lens_info is True:
            print(f"FocalLength info found in {filepath}. No tag applied.")
        else:
            print(f"Could not determine FocalLength info for {filepath}.")

if __name__ == "__main__":
    main()