#!/usr/bin/env python
import argparse
import re
import os
import pysam.bcftools

VERSION = "1.0.0"

def process_header(header, oldID, newID, out):
    '''
    Replace any instance of oldID with newID in the header

    :param header: VCF header file path
    :param oldID: Old sample ID to be replaced
    :param newID: New sample ID to replace the old ID
    :param out: Output file path
    '''
    with open(out, 'wt') as outfile:
        for line in header:
            # Replace all substrings that look like a path with their basename
            if re.match(r'##.*Command.*', line):
                # Remove path components from any file paths in the Command line
                line = re.sub(r'([^\s]+/[^\s]+)', lambda m: os.path.basename(m.group(0)), line)
                # Replace any occurance of oldID with newID
                line = re.sub(r'(?=[^\W]?)' + re.escape(oldID) + r'(?=[^\W]?|$)', newID, line)
            elif line.startswith('#CHROM'):
                sample_id = line.strip().split('\t')[9]  # Sample IDs start from the 10th column
                if oldID not in sample_id:
                    raise ValueError("Old ID does not match sample ID in header.\n Found sample ID: " + sample_id + "\n Expected to find: " + oldID)
                # ID could have underscores.
                line = re.sub(r'(?=[^\W]?)' + re.escape(oldID) + r'(?=[^\W]?|$)', newID, line)
            outfile.write(line+'\n')


def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("-v", "--version", action='version', version='%(prog)s ' + VERSION)
    parser.add_argument("path", type=str, help="VCF header path")
    parser.add_argument("--new_id", type=str, required=True, help="New sample ID")
    parser.add_argument("--old_id", type=str, required=True, help="Sample ID to be replaced")
    parser.add_argument("-o", "--output", type=str, default="new.header.vcf", help="Output VCF path")
    args = parser.parse_args()

    header = pysam.bcftools.head(args.path, catch_stdout=True, split_lines=True)

    process_header(header, args.old_id, args.new_id, args.output)

if __name__ == "__main__":
    main()
