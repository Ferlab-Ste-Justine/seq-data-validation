#!/usr/bin/env python
"""Script to parse and modify VCF headers by replacing sample IDs."""
import argparse
import re
import os
import sys
import logging
import pysam.bcftools

VERSION = "1.0.1"


def process_header(header, old_id, new_id, out) -> None:
    """
    Replace any instance of old_id with new_id in the header

    :param header: VCF header file path
    :param old_id: Old sample ID to be replaced
    :param new_id: New sample ID to replace the old ID
    :param out: Output file path
    """
    with open(out, "wt", encoding="utf-8") as outfile:
        for line in header:
            # Replace all substrings that look like a path with their basename
            if re.match(r"##.*Command.*", line):
                # Remove path components from any file paths in the Command line
                line = re.sub(
                    r"([^\s]+/[^\s]+)", lambda m: os.path.basename(m.group(0)), line
                )
                # Replace any occurance of old_id with new_id
                line = re.sub(
                    r"(?=[^\W]?)" + re.escape(old_id) + r"(?=[^\W]?|$)", new_id, line
                )
            elif line.startswith("#CHROM"):
                try:
                    # Sample IDs start from the 10th column
                    sample_ids = line.strip().split("\t")[9:]
                    sample_id = sample_ids[0]
                    # make sure the is only one sample ID in the VCF
                    if len(sample_ids) != 1:
                        s = (
                            "VCF contains multiple sample IDs. "
                            "This script only supports single-sample VCFs."
                        )
                        logging.error(s)
                        raise ValueError(s)
                    if old_id not in sample_id:
                        s = (
                            f"Old ID does not match sample ID in header.\n"
                            f"Found sample ID: {sample_id}\n Expected to find: {old_id}"
                        )
                        logging.error(s)
                        raise ValueError(s)
                    # ID could have underscores.
                    line = re.sub(
                        r"(?=[^\W]?)" + re.escape(old_id) + r"(?=[^\W]?|$)",
                        new_id,
                        line,
                    )
                except IndexError:
                    # No sample ID/s found in header. VCF without Genotypes -> OK. Keep line as is
                    logging.info(
                        "No sample ID found in VCF header. Assuming VCF without genotypes."
                    )
            outfile.write(line + "\n")


def main():
    """
    Main function to parse arguments and process the VCF header
    """
    # Parse command line arguments
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument(
        "-v", "--version", action="version", version="%(prog)s " + VERSION
    )
    parser.add_argument("path", type=str, help="VCF header path")
    parser.add_argument("--new_id", type=str, required=True, help="New sample ID")
    parser.add_argument(
        "--old_id", type=str, required=True, help="Sample ID to be replaced"
    )
    parser.add_argument(
        "-o", "--output", type=str, default="new.header.vcf", help="Output VCF path"
    )
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[logging.StreamHandler(sys.stdout)]
        )

    header = pysam.bcftools.head(args.path, catch_stdout=True, split_lines=True)

    process_header(header, args.old_id, args.new_id, args.output)


if __name__ == "__main__":
    main()
