#!/usr/bin/env python
import argparse
import re
import os
import gzip
import shutil
import sys
import xml.etree.ElementTree as ET
import hashlib

VERSION = "1.0.0"

ignore_files = [
    ".bai",
    ".bam",
    ".cram",
    ".crai",
    ".fai",
    ".fa",
    ".gvcf.gz",
    ".vcf.gz",
    ".tbi",
    ".dict",
    ".idx",
    ".md5sum",
    ".md5",
    ".bin"
]


def calculate_md5(filepath, chunk_size=8192):
    """Calculates the MD5 checksum of a file."""
    md5_hash = hashlib.md5()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(chunk_size), b""):
            md5_hash.update(chunk)
    return md5_hash.hexdigest()


def file_manifest(file, file_type):
    """
    Generates a manifest entry for a given file.
    """
    name = os.path.basename(file)
    size = os.path.getsize(file)
    md5 = calculate_md5(file)
    return f"{name}\t{size}\t{md5}\t{file_type}\n"


def write_manifest(file_list):
    """
    Generates a manifest file listing all processed files with their
    names, sizes, MD5 checksums, and types.
    """
    manifest_path = os.path.join(os.getcwd(), "file_manifest.tsv")
    with open(manifest_path, "w") as manifest_file:
        manifest_file.write("Filename\tSize\tMD5\tfileType\n")
        for file_path, file_type in file_list:
            if os.path.exists(file_path):
                entry = file_manifest(file_path, file_type)
                manifest_file.write(entry)


def process_xml(input_file, old_id, new_id):
    """
    Parses an XML file, replaces all occurrences of an old ID with a new ID
    in both element text and attribute values, and saves the result to a new file.

    Args:
        input_file (str): Path to the input XML file.
        output_file (str): Path to the output XML file.
        old_id (str): The string to be replaced.
        new_id (str): The new string to replace with.
    """
    try:
        # Parse the XML file into an element tree
        tree = ET.parse(input_file)
        root = tree.getroot()

        # Use root.iter() to traverse all elements in the tree
        for element in root.iter():
            # 1. Replace ID in element's text content
            if element.text and old_id in element.text:
                element.text = element.text.replace(old_id, new_id)

            # 2. Replace ID in element's attribute values
            for attr_name, attr_value in element.attrib.items():
                if old_id in attr_value:
                    # Update the attribute value
                    element.set(attr_name, attr_value.replace(old_id, new_id))
        return tree

    except ET.ParseError as e:
        print(f"Error: Failed to parse the XML file '{input_file}'. Details: {e}")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")


def process_file(input_path, output_path, old_id, new_id):
    """
    Reads a file line-by-line, replaces occurrences of old_id with new_id,
    and writes the result to a new file.

    Args:
        input_path (str): Path to the input file.
        output_path (str): Path to the output file.
        old_id (str): The ID to be replaced.
        new_id (str): The new ID to replace with.
    """
    try:
        is_gzipped = input_path.endswith(".gz")
        with (
            gzip.open(input_path, "rt") if is_gzipped else open(input_path, "r")
        ) as infile:
            # Use a temporary file for writing to avoid creating an empty file if there's an error
            temp_output_path = output_path + ".tmp"
            with (
                gzip.open(temp_output_path, "wt")
                if is_gzipped
                else open(temp_output_path, "w")
            ) as outfile:
                replacements_made = False
                # Compile regex for efficiency
                pattern = re.compile(re.escape(old_id))

                for line in infile:
                    new_line, count = pattern.subn(new_id, line)
                    if count > 0:
                        replacements_made = True
                    outfile.write(new_line)

        return replacements_made, temp_output_path

    except Exception as e:
        print(f"Error processing file {input_path}: {e}")
        # Clean up temp file on error
        if "temp_output_path" in locals() and os.path.exists(temp_output_path):
            os.remove(temp_output_path)


def process_input(files, types, old_id, new_id, outdir):
    """
    Processes a list of files, replacing occurrences of old_id with new_id
    based on their types, and writes the results to an output directory.
    Args:
        files (list): List of file paths to be processed.
        types (list): List of file types corresponding to the files.
        old_id (str): The ID to be replaced.
        new_id (str): The new ID to replace with.
        outdir (str): The output directory where processed files will be saved.
    """
    processed_files = []
    invalid_files = []
    for i, (file_path, file_type) in enumerate(zip(files, types), start=1):
        base_name = os.path.basename(file_path)
        file_ext = os.path.splitext(file_path)[1]
        print(file_ext, file_type)
        print(f"[{i}/{len(files)}]")
        new_base_name = os.path.join(outdir, base_name.replace(old_id, new_id))

        if file_ext in ignore_files:
            print(f"Ignoring {file_path}. - file type cannot be processed.")
            invalid_files.append(file_path)
            continue

        elif file_ext in (".bed", ".bw", ".bed.gz", ".gff3"):
            shutil.copy(file_path, new_base_name)

        elif file_ext == ".xml":
            tree = process_xml(file_path, old_id, new_id)
            # Write the modified tree to a new file
            tree.write(new_base_name, encoding="utf-8", xml_declaration=True)
            print(
                f"Successfully processed '{file_path}' and saved to '{new_base_name}'."
            )

        else:
            replacements_made, tmp_out = process_file(
                file_path, new_base_name, old_id, new_id
            )
            # If no replacements were made, copy the original file. Otherwise, move the temp file.
            if not replacements_made:
                print(f"No changes made to '{file_path}'. Copied to '{new_base_name}'.")
                shutil.copy(file_path, new_base_name)
                os.remove(tmp_out)  # Clean up temp file
            else:
                shutil.move(tmp_out, new_base_name)
                print(
                    f"Successfully processed '{file_path}' and wrote to '{new_base_name}'."
                )

        processed_files.append((new_base_name, file_type))

    return processed_files, invalid_files


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
        "--files", type=str, nargs="+", help="List of files to be processed"
    )
    parser.add_argument(
        "--types",
        type=str,
        nargs="+",
        help="Ordered List of file types to be processed",
    )
    parser.add_argument("--new_id", type=str, required=True, help="New sample ID")
    parser.add_argument(
        "--old_id", type=str, required=True, help="Sample ID to be replaced"
    )
    parser.add_argument(
        "--outdir", "-o", type=str, required=True, help="Output directory"
    )
    args = parser.parse_args()

    if len(args.files) != len(args.types):
        print("Error: The number of files must match the number of types.")
        sys.exit(1)

    # Create the output directory if it doesn't exist
    if not os.path.exists(args.outdir):
        os.makedirs(args.outdir)

    print(f"Processing {len(args.files)} files...")

    output_list, invalid_files = process_input(
        args.files, args.types, args.old_id, args.new_id, args.outdir
    )

    write_manifest(output_list)

    with open(os.path.join("unprocessed_files.txt"), "w") as invalid_file:
        for invalid in invalid_files:
            invalid_file.write(f"{invalid}\n")

if __name__ == "__main__":
    main()
