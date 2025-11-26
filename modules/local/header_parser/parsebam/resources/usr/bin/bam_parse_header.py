#!/usr/bin/env python
import argparse
import re
import os
import pysam.samtools

VERSION = "1.0.0"

def process_header(header, oldID, newID, out):
    # Replace any instance of oldID with newID in the header
    # This in the header line where sampleID is (^#CHROM...) and any other line that may contain the sampleID (like the Command ones)
    with open(out, 'wt') as outfile:
        for line in header:
            if line.startswith('@PG'):
                line = re.sub(r'([^\s]+/[^\s]+)', lambda m: os.path.basename(m.group(0)), line)
                line = re.sub(r'(?=[^\W]?)' + re.escape(oldID) + r'(?=[^\W]?|$)', newID, line)
            elif line.startswith('@RG'):
                sample_id = re.search(r'SM:([^\t\n\r\f\v]+)', line).group(1)
                print(sample_id)
                if oldID not in sample_id:
                    raise ValueError("Old ID does not match SM record in @RG.\n Found sample ID: " + sample_id + "\n Expected to find: " + oldID)
                line = re.sub(r'(?<=[^(ID)]:)(\w*?\W?)' + re.escape(oldID) + r'(?=[^\W]?|$)', r'\1' + newID, line)
                print(line)
               # check if RGID contains the oldID - this will need to later be updated in the bam reads.
                if re.search(r'(?<=ID:)(\w*?)' + re.escape(oldID), line):
                    Warning("Warning: RG ID contains the old sample ID. Make sure to update the read group IDs in the BAM file accordingly.")
                    line = re.sub(r'(?<=ID:)(\w*?)' + re.escape(oldID) + r'(?=[^\W]?|$)', r'\1' + newID, line)
                    os.environ['REPLACE_RG'] = repr(line)
                # The ID in the header might have extra chars than just the sampleID, replace all of the id. example: oldID="sample1" and in the header, the sample ID is "sample1_L001". We want to replace the entire ID.
            outfile.write(line+'\n')

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("-v", "--version", action="version", version='%(prog)s ' + VERSION)
    parser.add_argument("path", type=str, help="BAM path")
    parser.add_argument("--new_id", type=str, required=True, help="New sample ID")
    parser.add_argument("--old_id", type=str, required=True, help="Sample ID to be replaced")
    parser.add_argument("--output", "-o", type=str, default="new.header.sam", help="Output path")
    args = parser.parse_args()

    # Verify EOF
    pysam.samtools.quickcheck(args.path)

    # Get header
    header = pysam.samtools.head(args.path, catch_stdout=True, split_lines=True) #False

    # head2 = pysam.AlignmentHeader.from_text(header)
    # print(head2.keys())

    os.environ['REPLACE_RG'] = 'False'
    # Process header
    process_header(header, args.old_id, args.new_id, args.output)

    print(os.getenv('REPLACE_RG'))

if __name__ == "__main__":
    main()
