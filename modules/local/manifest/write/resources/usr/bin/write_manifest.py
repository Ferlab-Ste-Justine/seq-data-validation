#!/usr/bin/env python
import argparse
import os
import sys
import hashlib

VERSION = "1.0.0"


def calculate_md5(filepath, chunk_size=8192):
    """Calculates the MD5 checksum of a file."""
    md5_hash = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(chunk_size), b""):
            md5_hash.update(chunk)
    return md5_hash.hexdigest()


def file_manifest(file, file_type, parent_path=None):
    """
    Generates a manifest entry for a given file.
    """
    name = os.path.basename(file) if parent_path is None else os.path.join(parent_path, os.path.basename(file))
    size = os.path.getsize(file)
    md5 = calculate_md5(file)
    return f"{name}\t{size}\t{md5}\t{file_type}\n"


def write_manifest(sample,file_list, outfile, parent_path=None):
    """
    Generates a manifest file listing all processed files with their
    names, sizes, MD5 checksums, and types.
    """
    with open(outfile, "w", encoding="utf-8") as manifest_file:
        manifest_file.write("sample_id\tfile_name\tfile_size\tfile_md5sum\tfile_type\n")
        for file_path, file_type in file_list:
            if os.path.exists(file_path):
                entry = file_manifest(file_path, file_type, parent_path)
                manifest_file.write(f"{sample}\t{entry}")


def main():
    """
    Main function to parse arguments and process files.
    """
    parser = argparse.ArgumentParser(
        description="Replace a string in files and write to new files.", add_help=True
    )
    parser.add_argument(
        "-v", "--version", action="version", version="%(prog)s " + VERSION
    )
    parser.add_argument(
        "-s", "--sample", type=str, help="Sample identifier", required=True
    )
    parser.add_argument(
        "--files", type=str, nargs="+", help="List of files to be processed"
    )
    parser.add_argument(
        "--types",
        type=str,
        nargs="+",
        help="Ordered List of file types to be processed",
    )
    parser.add_argument(
        "-o", "--outfile", type=str, required=True, help="Output file"
    )
    parser.add_argument(
        "-p", "--parent_path", type=str, help="path to prepend to file names in manifest", default=None
    )

    args = parser.parse_args()

    if len(args.files) != len(args.types):
        print("Error: The number of files must match the number of types.")
        sys.exit(1)

    print(f"Processing {len(args.files)} files...")

    output_list = []
    for file_path, file_type in zip(args.files, args.types):
        output_list.append((file_path, file_type))

    write_manifest(args.sample, output_list, args.outfile, args.parent_path)


if __name__ == "__main__":
    main()
