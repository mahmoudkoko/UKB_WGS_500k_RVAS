import requests
import pyBigWig
import gc
import os
import sys
from datetime import datetime

# fix: read the url and the output prefix dynamically from arguments --url --prefix
# Simple logging setup
# fix: build the file name from the argument --prefix
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

# Redirect all print statements to both console and file
sys.stdout = Logger("bigwig_split.log")

def download_bigwig(url, output_path):
    """Download BigWig file with streaming"""

    if not os.path.exists(output_path):
        print(f"Downloading {url}...")
        response = requests.get(url, stream=True)
        response.raise_for_status()
        
        with open(output_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)
    
    print(f"Downloaded to {output_path}")

def split_single_chromosome(bigwig_path, score_name, chrom, chrom_length, chunk_size=1000000):
    """Process a single chromosome with aggressive memory management"""
    
    print(f"\nProcessing chromosome {chrom} (length: {chrom_length:,})...")
    output_file = f"{score_name}_chr{chrom}.bw"
    
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
                        
                        # Remove any intervals that overlap with already written data
                        valid_intervals = []
                        
                        for start_pos, end_pos, value in interval_data:
                            # Only add if this interval starts at or after our last written position
                            if start_pos >= last_written_end:
                                valid_intervals.append((start_pos, end_pos, value))
                            else:
                                print(f"    Skipping overlapping interval: {start_pos}-{end_pos} (last_end: {last_written_end})")
                        
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

def split_bigwig_by_chromosome_safe(bigwig_path):
    """Safely split BigWig by chromosome with minimal memory usage"""
    
    print("Getting chromosome information...")
    
    # Open briefly just to get chromosome info
    bw = pyBigWig.open(bigwig_path)
    chrom_sizes = dict(bw.chroms())
    bw.close()
    
    allowed_chroms = {f"{i}" for i in range(1, 23)} | {"X", "Y"}
    
    # Process each chromosome separately to minimize memory usage
    for chrom in sorted(chrom_sizes.keys()):
        if chrom in allowed_chroms:
            chrom_length = chrom_sizes[chrom]
            
            # Process this chromosome completely before moving to next
            split_single_chromosome(bigwig_path, chrom, chrom_length, chunk_size=12000000)
            
            # Force cleanup between chromosomes
            gc.collect()
    
    print("\n✓ All chromosomes processed successfully!")

def main():
    url = "https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/gerp_conservation_scores.homo_sapiens.GRCh38.bw"
    output_path = "gerp_scores_hg38.bw"
    
    # Download the file first
    # fix this: check if the file exists to prevent downloading the file twice
    download_bigwig(url, output_path)
    
    # Split by chromosome with safe memory usage
    split_bigwig_by_chromosome_safe(output_path)

if __name__ == "__main__":
    main()