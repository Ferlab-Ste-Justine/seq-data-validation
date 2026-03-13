#!/usr/bin/env python
import argparse
import re
import os
import gzip
import shutil
import sys
import xml.etree.ElementTree as ET
import hashlib
import logging

VERSION = "1.0.0"

ignore_files = [
    ".bai",
    ".bam",
    ".cram",
    ".crai",
    ".fai",
    ".fa",
    ".gvcf",
    ".gvcf.gz",
    ".vcf",
    ".vcf.gz",
    ".tbi",
    ".dict",
    ".idx",
    ".md5sum",
    ".md5",
    ".bin",
    ".png",
    ".jpg",
    ".jpeg",
    ".pdf"
]


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


def write_manifest(sample, file_list, parent_path=None):
    """
    Generates a manifest file listing all processed files with their
    names, sizes, MD5 checksums, and types.
    """
    manifest_path = os.path.join(os.getcwd(), "file_manifest.tsv")
    with open(manifest_path, "w", encoding="utf-8") as manifest_file:
        manifest_file.write("submitter_sample_id\tsubmitter_file_name\tfile_size\tfile_md5sum\tfile_type\n")
        for file_path, file_type in file_list:
            if os.path.exists(file_path):
                entry = file_manifest(file_path, file_type, parent_path)
                manifest_file.write(f"{sample}\t{entry}")


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
        logging.error("Error: Failed to parse the XML file '%s'. Details: %s", input_file, e)
    except Exception as e:
        logging.error("An unexpected error occurred: %s", e)


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
            gzip.open(input_path, "rt")
            if is_gzipped
            else open(input_path, "r", encoding="utf-8")
        ) as infile:
            # Use a temporary file for writing to avoid creating an empty file if there's an error
            temp_output_path = output_path + ".tmp"
            with (
                gzip.open(temp_output_path, "wt")
                if is_gzipped
                else open(temp_output_path, "w", encoding="utf-8")
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

    except IOError as e:
        logging.error("Error processing file %s: %s", input_path, e)
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
    modified_count = 0
    copied_count = 0
    for i, (file_path, file_type) in enumerate(zip(files, types), start=1):
        base_name = os.path.basename(file_path)
        file_ext = os.path.splitext(file_path)[1]
        logging.info("Processing file %d/%d: %s", i, len(files), os.path.basename(file_path))
        new_base_name = os.path.join(outdir, base_name.replace(old_id, new_id))

        if file_ext in ignore_files:
            logging.warning("Ignoring %s. - file type cannot be processed.", os.path.basename(file_path))
            invalid_files.append(os.path.basename(file_path))
            continue

        elif file_ext in (".bed", ".bw", ".bed.gz", ".gff3"):
            shutil.copy(file_path, new_base_name)
            copied_count += 1

        elif file_ext == ".xml":
            tree = process_xml(file_path, old_id, new_id)
            # Write the modified tree to a new file
            tree.write(new_base_name, encoding="utf-8", xml_declaration=True)
            logging.info(
                "Successfully processed '%s' and saved to '%s'.", os.path.basename(file_path), new_base_name
            )
            modified_count += 1

        else:
            replacements_made, tmp_out = process_file(
                file_path, new_base_name, old_id, new_id
            )
            # If no replacements were made, copy the original file. Otherwise, move the temp file.
            if not replacements_made:
                logging.info("No changes made to '%s'. Copied to '%s'.", os.path.basename(file_path), new_base_name)
                shutil.copy(file_path, new_base_name)
                os.remove(tmp_out)  # Clean up temp file
                copied_count += 1
            else:
                shutil.move(tmp_out, new_base_name)
                logging.info(
                    "Successfully processed '%s' and wrote to '%s'.", os.path.basename(file_path), new_base_name
                )
                modified_count += 1

        processed_files.append((new_base_name, file_type))

    return processed_files, invalid_files, modified_count, copied_count


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
    parser.add_argument(
        "-p", "--parent_path", type=str, help="path to prepend to file names in manifest", default=None
    )
    args = parser.parse_args()

    # Create the output directory if it doesn't exist
    if not os.path.exists(args.outdir):
        os.makedirs(args.outdir)

    # Setup logging
    log_file = os.path.join(f"{args.new_id}.sample_rename.others.log")
    logging.basicConfig(
        filename=log_file,
        level=logging.DEBUG,
        format="%(asctime)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    logging.info("Starting file processing. Sample %s", args.new_id)
    logging.info("Old Sample ID: %s", args.old_id)
    logging.info("New Sample ID: %s", args.new_id)

    if len(args.files) != len(args.types):
        logging.error("Error: The number of files must match the number of types.")
        sys.exit(1)

    logging.info("Processing %d files...", len(args.files))

    output_list, invalid_files, modified_count, copied_count = process_input(
        args.files, args.types, args.old_id, args.new_id, args.outdir
    )

    write_manifest(args.new_id, output_list, args.parent_path)

    if len(invalid_files) > 0:
        skipped_files_path = os.path.join(f"{args.new_id}.skipped_files.txt")
        with open(skipped_files_path, "w", encoding="utf-8") as invalid_file:
            for invalid in invalid_files:
                invalid_file.write(f"{invalid}\n")
        logging.warning("%d files were skipped. See %s", len(invalid_files), skipped_files_path)

    logging.info("File processing summary:")
    logging.info("Total files processed: %d", len(output_list))
    logging.info("Files modified: %d", modified_count)
    logging.info("Files copied/renamed: %d", copied_count)
    logging.info("Files skipped: %d", len(invalid_files))
    logging.info("Processing complete.")

if __name__ == "__main__":
    main()
