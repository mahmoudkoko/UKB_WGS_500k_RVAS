import requests
import pyBigWig
import gc
import os
import sys
import argparse
from datetime import datetime

class Logger:
    def __init__(self, filename="bigwig_split.log"):
        self.terminal = sys.stdout
        self.log = open(filename, "a")
   
    def write(self, message):
        self.terminal.write(message)
        self.log.write(message)
        self.log.flush()
    
    def flush(self):
        pass

def download_bigwig(url, output_path):
    """Download BigWig file with streaming, skip if already exists"""
    
    if os.path.exists(output_path):
        print(f"Source file {output_path} already exists, skipping download.")
        return
    
    print(f"Downloading {url}...")
    response = requests.get(url, stream=True)
    response.raise_for_status()
    
    with open(output_path, "wb") as f:
        for chunk in response.iter_content(chunk_size=8192):
            f.write(chunk)
    
    print(f"Downloaded to {output_path}")

def split_single_chromosome(bigwig_path, output_prefix, chrom, chrom_length, overwrite=False, chunk_size=1000000):
    """Process a single chromosome with aggressive memory management"""
    
    print(f"\nProcessing chromosome {chrom} (length: {chrom_length:,})...")
    output_file = f"{output_prefix}_chr{chrom}.bw"
    
    # Check if output file already exists
    if os.path.exists(output_file):
        if overwrite:
            print(f"Output file {output_file} exists, overwriting as requested.")
        else:
            print(f"Output file {output_file} already exists, skipping.")
            return
    
    # Open source BigWig only when needed
    bw = pyBigWig.open(bigwig_path)
    
    try:
        # Open output BigWig
        with pyBigWig.open(output_file, "w") as new_bw:
            new_bw.addHeader([(chrom, chrom_length)])
            
            total_intervals = 0
            chunk_count = 0
            last_written_end = 0  # Track the last position we wrote
            
            # Process in smaller chunks with aggressive cleanup
            for start in range(0, chrom_length, chunk_size):
                # Ensure end doesn't exceed chromosome length
                end = min(start + chunk_size, chrom_length)
                chunk_count += 1
                
                print(f"  Processing chunk {start:,}-{end:,} (chunk {chunk_count})")
                
                # Get intervals for this small chunk
                try:
                    intervals = bw.intervals(chrom, start, end)
                    
                    if intervals:
                        # Process and sort intervals to ensure proper order
                        interval_data = []
                        for interval in intervals:
                            # Validate interval is within chromosome bounds
                            if (interval[0] >= 0 and interval[1] <= chrom_length and 
                                interval[0] < interval[1]):  # start < end
                                interval_data.append((interval[0], interval[1], interval[2]))
                        
                        # Sort by start position to ensure proper order
                        interval_data.sort(key=lambda x: x[0])
                        
                        # Handle intervals that overlap with already written data
                        valid_intervals = []
                        
                        for start_pos, end_pos, value in interval_data:
                            if start_pos >= last_written_end:
                                # No overlap, use as-is
                                valid_intervals.append((start_pos, end_pos, value))
                            elif end_pos > last_written_end:
                                # Partial overlap, adjust start position to preserve non-overlapping portion
                                adjusted_start = last_written_end
                                valid_intervals.append((adjusted_start, end_pos, value))
                                print(f"    Adjusted overlapping interval: {start_pos}-{end_pos} -> {adjusted_start}-{end_pos} (last_end: {last_written_end})")
                            else:
                                # Completely overlapping with already written data, skip
                                print(f"    Skipping completely overlapping interval: {start_pos}-{end_pos} (last_end: {last_written_end})")
                        
                        # Extract valid data and write
                        if valid_intervals:
                            starts = [x[0] for x in valid_intervals]
                            ends = [x[1] for x in valid_intervals]
                            values = [x[2] for x in valid_intervals]
                            
                            # Write the cleaned, sorted intervals
                            new_bw.addEntries([chrom] * len(starts), starts, ends=ends, values=values)
                            total_intervals += len(starts)
                            
                            # Update our tracking of the last written position
                            if ends:
                                last_written_end = max(ends)
                            
                            print(f"    Wrote {len(starts)} intervals, last_end now: {last_written_end}")
                        
                        # Aggressive cleanup
                        del interval_data, valid_intervals, starts, ends, values, intervals
                    
                    # Progress report every 50 chunks
                    if chunk_count % 50 == 0:
                        print(f"  Processed {chunk_count} chunks, position {end:,}, intervals: {total_intervals:,}")
                        gc.collect()  # Force garbage collection
                
                except Exception as e:
                    print(f"  Error processing chunk {start}-{end}: {e}")
                    print(f"  Chunk bounds: start={start}, end={end}, chrom_length={chrom_length}")
                    continue
            
            print(f"  ✓ Created {output_file} with {total_intervals:,} intervals")
    
    finally:
        # Always close source BigWig
        bw.close()
        gc.collect()

def split_bigwig_by_chromosome_safe(bigwig_path, output_prefix, chromosomes, overwrite=False):
    """Safely split BigWig by chromosome with minimal memory usage"""
    
    print("Getting chromosome information...")
    
    # Open briefly just to get chromosome info
    bw = pyBigWig.open(bigwig_path)
    chrom_sizes = dict(bw.chroms())
    bw.close()
    
    # Convert chromosome list to set for faster lookup
    allowed_chroms = set(chromosomes)
    
    # Process each chromosome separately to minimize memory usage
    for chrom in sorted(chrom_sizes.keys()):
        if chrom in allowed_chroms:
            chrom_length = chrom_sizes[chrom]
            
            # Process this chromosome completely before moving to next
            split_single_chromosome(bigwig_path, output_prefix, chrom, chrom_length, overwrite, chunk_size=12000000)
            
            # Force cleanup between chromosomes
            gc.collect()
    
    print("\n✓ All chromosomes processed successfully!")

def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description="Split BigWig files by chromosome")
    
    parser.add_argument("--url", required=True, 
                       help="URL of the BigWig file to download")
    
    parser.add_argument("--prefix", required=True,
                       help="Output prefix for chromosome files (e.g., 'gerp_scores_hg38')")
    
    parser.add_argument("--chromosomes", nargs="+", 
                       default=[str(i) for i in range(1, 23)] + ["X", "Y"],
                       help="List of chromosomes to process (default: 1-22, X, Y)")
    
    parser.add_argument("--overwrite", action="store_true",
                       help="Overwrite existing chromosome files (default: skip existing)")
    
    parser.add_argument("--log", default="bigwig_split.log",
                       help="Log file name (default: bigwig_split.log)")
    
    return parser.parse_args()

def main():
    # Parse command line arguments
    args = parse_arguments()
    
    # Set up logging with custom filename
    sys.stdout = Logger(args.log)
    
    # Create source file name from URL
    source_filename = os.path.basename(args.url)
    if not source_filename.endswith('.bw'):
        source_filename = f"{args.prefix}_source.bw"
    
    print(f"Starting BigWig splitting process...")
    print(f"URL: {args.url}")
    print(f"Output prefix: {args.prefix}")
    print(f"Chromosomes: {args.chromosomes}")
    print(f"Overwrite existing: {args.overwrite}")
    print(f"Source file: {source_filename}")
    print(f"Log file: {args.log}")
    print(f"Start time: {datetime.now()}")
    print("-" * 50)
    
    # Download the file first (skip if exists)
    download_bigwig(args.url, source_filename)
    
    # Split by chromosome with safe memory usage
    split_bigwig_by_chromosome_safe(source_filename, args.prefix, args.chromosomes, args.overwrite)
    
    print(f"\nCompleted at: {datetime.now()}")

if __name__ == "__main__":
    main()