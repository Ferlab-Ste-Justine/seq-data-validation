#!/usr/bin/env python
import argparse
import re
import os
import pysam.samtools

VERSION = "1.0.0"

class InvalidDataError(Exception):
    """Raised when data provided is in an invalid format."""
    def __init__(self, message="Invalid data provided", details=None):
        super().__init__(message)

def process_pg_line(line, oldID, newID):
    # Process a @PG line, replacing oldID with newID in the command field and
    # simplifying file paths to just the base name
    line = re.sub(r'([^\s:]+/[^\s]+)', lambda m: os.path.basename(m.group(0)), line)
    line,n = re.subn(r'(?=[^\W]?)' + re.escape(oldID) + r'(?=[^\W]?|$)', newID, line)
    return line,n
def process_rg_line(rg_line, oldID, newID):
    sm_match = False
    rgid = None
    for f in re.finditer(r'(\w{2}:)((\w*?)\.?'+ re.escape(oldID) +r'(\.?[^\W]*))', rg_line):
        replacement = f.group(3)+newID+f.group(4)
        rg_line = re.sub(f.group(2),replacement,rg_line)
        if f.group(1) == 'SM:': sm_match = True
        elif f.group(1) == 'ID:': rgid = f.group(2)
    if not sm_match and not re.search(r'SM:\w*?\.?'+re.escape(newID), rg_line):
        raise InvalidDataError(f"RGSM record does not match any given IDs. Expected SM containing: {oldID} or {newID}")
    return rg_line, rgid

def process_header(header, oldID, newID, out, rg_out=None):
    # Replace any instance of oldID with newID in the header
    # Output the new header to 'out', and if an @RG line's ID contains oldID, output all such RGIDs to rg_out (one per line)
    new_header = []
    rgid_pairs = []
    rg_lines = []
    for line in header:
        if line.startswith('@PG'):
            line, n = process_pg_line(line, oldID, newID)
        elif line.startswith('@RG'):
            line, rgid = process_rg_line(line, oldID, newID)
            rg_lines.append(line)
            if rgid:
                rgid_pairs.append((rgid, line))
            continue  # Defer writing RG lines until after processing all lines
        new_header.append(line)
    # Write all RGID pairs (original and replacement) to rg_out, tab-separated
    if rg_out and rgid_pairs:
        new_header.append(rgid_pairs[0][1])  # Add first RG line to header
        with open(rg_out, 'wt') as rgfile:
            for rgid, new_rgid in rgid_pairs:
                rgfile.write(f"{rgid}\t{repr(new_rgid)}\n")
    else:
        new_header += rg_lines
    with open(out, 'wt') as outfile:
        outfile.write('\n'.join(new_header) + '\n')

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("-v", "--version", action="version", version='%(prog)s ' + VERSION)
    parser.add_argument("path", type=str, help="BAM path")
    parser.add_argument("--new_id", type=str, required=True, help="New sample ID")
    parser.add_argument("--old_id", type=str, required=True, help="Sample ID to be replaced")
    parser.add_argument("--output", "-o", type=str, default="new.header.sam", help="Output path")
    parser.add_argument("--rg_output", type=str, default="rg_line.txt", help="Output file for RG line if RGID contains old_id")
    args = parser.parse_args()

    # Verify EOF
    pysam.samtools.quickcheck(args.path)

    # Get header
    header = pysam.samtools.head(args.path, catch_stdout=True, split_lines=True) #False

    # Process header and output RG line if needed
    process_header(header, args.old_id, args.new_id, args.output, args.rg_output)

if __name__ == "__main__":
    main()
