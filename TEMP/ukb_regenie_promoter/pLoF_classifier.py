import pandas as pd
import numpy as np
import re
import gzip
import sys
import os
from typing import Dict, List, Tuple, Optional

class VEPpLofClassifier:
    """
    Classifier for predicted Loss-of-Function variants from VEP output
    Based on the comprehensive framework designed for QC filtering
    """
    
    def __init__(self, lof_intolerant_genes: Optional[List[str]] = None, gene_list_file: Optional[str] = None):
        """
        Initialize classifier with gene lists
        
        Args:
            lof_intolerant_genes: List of LoF-intolerant/haploinsufficient/triplosensitive genes
            gene_list_file: Path to file containing gene list (one gene per line)
        """
        if gene_list_file:
            self.lof_intolerant_genes = self._load_gene_list_from_file(gene_list_file)
        elif lof_intolerant_genes:
            self.lof_intolerant_genes = set(lof_intolerant_genes)
        else:
            raise ValueError("Must provide either lof_intolerant_genes list or gene_list_file path")
    
    def _load_gene_list_from_file(self, file_path: str) -> set:
        """Load gene list from file (one gene per line)"""
        try:
            with open(file_path, 'r') as f:
                genes = [line.strip() for line in f if line.strip()]
            print(f"Loaded {len(genes)} genes from {file_path}")
            return set(genes)
        except FileNotFoundError:
            raise FileNotFoundError(f"Gene list file not found: {file_path}")
        except Exception as e:
            raise Exception(f"Error reading gene list file: {e}")
        
    def classify_plof_variants(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Main function to classify all pLoF variants
        
        Args:
            df: DataFrame with VEP output
            
        Returns:
            DataFrame with added pLoF classification columns
        """
        # Add classification columns
        df = df.copy()
        df['pLoF_Level1'] = 'Not_pLoF'  # HC, LC, or Not_pLoF
        df['pLoF_Level2'] = 'Not_pLoF'  # Mechanism-specific subgroup
        df['pLoF_Combined'] = 'Not_pLoF'  # Level1_Level2 format
        
        # Apply gnomAD filtering first
        df_filtered = self._filter_gnomad_variants(df)
        
        # Classify each variant type
        df_filtered = self._classify_stop_gain_frameshift(df_filtered)
        df_filtered = self._classify_splice_variants(df_filtered)
        df_filtered = self._classify_5utr_variants(df_filtered)
        
        # Create combined classification
        mask = df_filtered['pLoF_Level1'] != 'Not_pLoF'
        df_filtered.loc[mask, 'pLoF_Combined'] = (
            df_filtered.loc[mask, 'pLoF_Level1'] + '_' + 
            df_filtered.loc[mask, 'pLoF_Level2']
        )
        
        return df_filtered
    
    def _filter_gnomad_variants(self, df: pd.DataFrame) -> pd.DataFrame:
        """Filter out variants seen in gnomAD (all frequency fields must be '-')"""
        gnomad_cols = [
            'gnomADg_AF', 'gnomADg_AFR_AF', 'gnomADg_AMI_AF', 'gnomADg_AMR_AF',
            'gnomADg_ASJ_AF', 'gnomADg_EAS_AF', 'gnomADg_FIN_AF', 'gnomADg_MID_AF',
            'gnomADg_NFE_AF', 'gnomADg_REMAINING_AF', 'gnomADg_SAS_AF'
        ]
        
        # Keep only variants where ALL gnomAD fields are '-'
        mask = True
        for col in gnomad_cols:
            if col in df.columns:
                mask = mask & (df[col] == '-')
        
        print(f"gnomAD filtering: {mask.sum():,} / {len(df):,} variants retained")
        return df[mask].copy()
    
    def _classify_stop_gain_frameshift(self, df: pd.DataFrame) -> pd.DataFrame:
        """Classify stop-gain and frameshift variants"""
        
        # High-confidence: LoF=HC + NMD=missing + gene in intolerant list
        hc_mask = (
            (df['LoF'] == 'HC') & 
            (df['NMD'] == '-') &
            df['Gene'].isin(self.lof_intolerant_genes)
        )
        
        # Low-confidence: LoF=LC OR (LoF=HC + NMD=escapes_NMD) - any gene
        lc_mask = (
            (df['LoF'] == 'LC') | 
            ((df['LoF'] == 'HC') & (df['NMD'] == 'escapes_NMD'))
        ) & ~hc_mask  # Don't double-count HC variants
        
        # Apply classifications
        df.loc[hc_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['HC', 'StopGainFrameshift']
        df.loc[lc_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['LC', 'StopGainFrameshift']
        
        print(f"Stop-gain/Frameshift: {hc_mask.sum():,} HC, {lc_mask.sum():,} LC")
        return df
    
    def _classify_splice_variants(self, df: pd.DataFrame) -> pd.DataFrame:
        """Classify splice variants"""
        
        # Essential splice sites
        essential_splice = df['Consequence'].str.contains(
            'splice_donor_variant|splice_acceptor_variant', na=False
        )
        
        # Other splice consequences
        other_splice = (
            df['Consequence'].str.contains('splice', na=False) & 
            ~essential_splice
        )
        
        # Non-splice consequences (for cryptic sites)
        non_splice = ~df['Consequence'].str.contains('splice', na=False)
        
        # Parse SpliceAI scores
        df['SpliceAI_score'] = pd.to_numeric(df['SpliceAI'], errors='coerce')
        
        # High-confidence essential splice (unless vetoed)
        essential_hc_mask = (
            essential_splice &
            (df['LoF'] == 'HC') &
            (df['NMD'] == '-') &
            (df['SpliceAI_score'] > 0.2) &
            df['Gene'].isin(self.lof_intolerant_genes)
        )
        
        # High-confidence cryptic splice
        cryptic_hc_mask = (
            non_splice &
            (df['SpliceAI_score'] > 0.8) &
            df['Gene'].isin(self.lof_intolerant_genes)
        )
        
        # Low-confidence essential splice (vetoed)
        essential_lc_mask = (
            essential_splice &
            (
                (df['LoF'] == 'LC') |
                (df['NMD'] == 'escapes_NMD') |
                (df['SpliceAI_score'] <= 0.2)
            ) & ~essential_hc_mask
        )
        
        # Low-confidence non-essential splice
        non_essential_lc_mask = (
            other_splice &
            (df['SpliceAI_score'] >= 0.2) &
            (df['SpliceAI_score'] <= 0.5)
        )
        
        # Low-confidence cryptic splice
        cryptic_lc_mask = (
            non_splice &
            (df['SpliceAI_score'] >= 0.5) &
            (df['SpliceAI_score'] <= 0.8)
        )
        
        # Low-confidence variants in tolerant genes
        tolerant_gene_lc_mask = (
            (essential_hc_mask | cryptic_hc_mask) &
            ~df['Gene'].isin(self.lof_intolerant_genes)
        )
        
        # Apply classifications
        df.loc[essential_hc_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['HC', 'EssentialSplice']
        df.loc[cryptic_hc_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['HC', 'CrypticSplice']
        df.loc[essential_lc_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['LC', 'EssentialSplice']
        df.loc[non_essential_lc_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['LC', 'NonEssentialSplice']
        df.loc[cryptic_lc_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['LC', 'CrypticSplice']
        df.loc[tolerant_gene_lc_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['LC', 'TolerantGene']
        
        total_splice = (essential_hc_mask | cryptic_hc_mask | essential_lc_mask | 
                       non_essential_lc_mask | cryptic_lc_mask | tolerant_gene_lc_mask).sum()
        print(f"Splice variants: {total_splice:,} classified")
        return df
    
    def _classify_5utr_variants(self, df: pd.DataFrame) -> pd.DataFrame:
        """Classify 5'UTR variants"""
        
        # Parse existing ORF counts
        df['existing_InFrame_oORFs'] = self._parse_existing_orfs(df, 'Existing_InFrame_oORFs')
        df['existing_OutOfFrame_oORFs'] = self._parse_existing_orfs(df, 'Existing_OutOfFrame_oORFs')
        
        # Universal filter: creates oORF + strong evidence
        universal_filter = self._apply_5utr_universal_filter(df)
        
        # High-confidence consequences
        hc_consequences = df['5UTR_consequence'].str.contains(
            'uAUG_gained|uSTOP_lost|uFrameShift', na=False
        )
        
        # High-confidence: meets universal filter + HC consequences + gene context
        hc_5utr_mask = (
            universal_filter &
            hc_consequences &
            df['Gene'].isin(self.lof_intolerant_genes) &
            (df['existing_InFrame_oORFs'] == 0) &
            (df['existing_OutOfFrame_oORFs'] == 0)
        )
        
        # Low-confidence: meets universal filter but fails gene/context criteria
        lc_existing_orf_mask = (
            universal_filter &
            (
                (df['existing_InFrame_oORFs'] > 0) |
                (df['existing_OutOfFrame_oORFs'] > 0)
            )
        )
        
        lc_tolerant_gene_mask = (
            universal_filter &
            ~df['Gene'].isin(self.lof_intolerant_genes) &
            ~lc_existing_orf_mask
        )
        
        # Apply classifications
        df.loc[hc_5utr_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['HC', '5UTR']
        df.loc[lc_existing_orf_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['LC', 'ExistingORF']
        df.loc[lc_tolerant_gene_mask, ['pLoF_Level1', 'pLoF_Level2']] = ['LC', 'TolerantGene']
        
        total_5utr = (hc_5utr_mask | lc_existing_orf_mask | lc_tolerant_gene_mask).sum()
        print(f"5'UTR variants: {total_5utr:,} classified")
        return df
    
    def _parse_existing_orfs(self, df: pd.DataFrame, col_name: str) -> pd.Series:
        """Parse existing ORF counts from VEP output"""
        if col_name in df.columns:
            return pd.to_numeric(df[col_name], errors='coerce').fillna(0)
        else:
            return pd.Series(0, index=df.index)
    
    def _apply_5utr_universal_filter(self, df: pd.DataFrame) -> pd.Series:
        """Apply universal filter for 5'UTR variants: creates oORF + strong evidence"""
        
        # Check if creates overlapping ORF
        creates_oorf = self._check_creates_oorf(df)
        
        # Check for strong evidence (Kozak or translation)
        strong_evidence = self._check_strong_evidence(df)
        
        return creates_oorf & strong_evidence
    
    def _check_creates_oorf(self, df: pd.DataFrame) -> pd.Series:
        """Check if variant creates overlapping ORF"""
        
        # uAUG_gained creating oORF
        uaug_gained_oorf = (
            df['5UTR_consequence'].str.contains('uAUG_gained', na=False) &
            df['5UTR_annotation'].str.contains('uAUG_gained_type.*oORF', na=False)
        )
        
        # uSTOP_lost with no alternative stop (creates oORF)
        ustop_lost_oorf = (
            df['5UTR_consequence'].str.contains('uSTOP_lost', na=False) &
            df['5UTR_annotation'].str.contains('uSTOP_lost_AltStop:False', na=False)
        )
        
        # uFrameShift creating oORF
        frameshift_oorf = (
            df['5UTR_consequence'].str.contains('uFrameShift', na=False) &
            df['5UTR_annotation'].str.contains('uFrameshift_alt_type.*oORF', na=False)
        )
        
        return uaug_gained_oorf | ustop_lost_oorf | frameshift_oorf
    
    def _check_strong_evidence(self, df: pd.DataFrame) -> pd.Series:
        """Check for strong evidence: Moderate/Strong Kozak or translation evidence"""
        
        # Strong/Moderate Kozak - fix regex warning
        strong_kozak = df['5UTR_annotation'].str.contains(
            'KozakStrength:(?:Strong|Moderate)', na=False, regex=True
        )
        
        # Translation evidence (if available)
        translation_evidence = df['5UTR_annotation'].str.contains(
            'evidence:True', na=False, regex=False
        )
        
        return strong_kozak | translation_evidence
    
    def get_classification_summary(self, df: pd.DataFrame) -> pd.DataFrame:
        """Generate summary statistics of classification results"""
        
        summary_data = []
        
        # Overall counts
        total_variants = len(df)
        plof_variants = (df['pLoF_Level1'] != 'Not_pLoF').sum()
        
        summary_data.append({
            'Category': 'Total',
            'Level1': 'All',
            'Level2': 'All',
            'Count': total_variants,
            'Percentage': 100.0
        })
        
        summary_data.append({
            'Category': 'pLoF',
            'Level1': 'All_pLoF',
            'Level2': 'All_pLoF',
            'Count': plof_variants,
            'Percentage': (plof_variants / total_variants * 100) if total_variants > 0 else 0
        })
        
        # Detailed breakdown
        for level1 in ['HC', 'LC']:
            level1_mask = df['pLoF_Level1'] == level1
            level1_count = level1_mask.sum()
            
            if level1_count > 0:
                summary_data.append({
                    'Category': 'pLoF',
                    'Level1': level1,
                    'Level2': 'All',
                    'Count': level1_count,
                    'Percentage': (level1_count / total_variants * 100)
                })
                
                # Level2 breakdown
                for level2 in df.loc[level1_mask, 'pLoF_Level2'].unique():
                    if level2 != 'Not_pLoF':
                        level2_mask = level1_mask & (df['pLoF_Level2'] == level2)
                        level2_count = level2_mask.sum()
                        
                        summary_data.append({
                            'Category': 'pLoF',
                            'Level1': level1,
                            'Level2': level2,
                            'Count': level2_count,
                            'Percentage': (level2_count / total_variants * 100)
                        })
        
        return pd.DataFrame(summary_data)

def count_header_lines(filepath: str, compression: str = None) -> int:
    """Count how many header lines start with ##"""
    open_func = gzip.open if compression == 'gzip' else open
    mode = 'rt' if compression == 'gzip' else 'r'
    
    count = 0
    with open_func(filepath, mode) as f:
        for line in f:
            if line.startswith('##'):
                count += 1
            else:
                break
    return count

def process_file_in_chunks(input_file: str, output_file: str, classifier: VEPpLofClassifier, chunksize: int = 5000):
    """
    Process VEP file in chunks for memory efficiency
    Supports gzipped input and output files
    """
    print(f"Processing {input_file} -> {output_file}")
    print(f"Chunk size: {chunksize:,}")
    
    # Determine compression based on file extension
    input_compression = 'gzip' if input_file.endswith('.gz') else None
    output_compression = 'gzip' if output_file.endswith('.gz') else None
    
    # Count header lines to skip
    header_lines_to_skip = count_header_lines(input_file, input_compression)
    print(f"Skipping {header_lines_to_skip} header lines starting with ##")
    
    first_chunk = True
    total_variants = 0
    total_plof = 0
    
    try:
        # Read file in chunks
        chunk_reader = pd.read_csv(
            input_file, 
            sep='\t', 
            chunksize=chunksize,
            compression=input_compression,
            low_memory=False,
            skiprows=header_lines_to_skip
        )
        
        for chunk_num, chunk in enumerate(chunk_reader, 1):
            print(f"Processing chunk {chunk_num}: {len(chunk):,} variants")
            
            # Classify variants in this chunk
            chunk_classified = classifier.classify_plof_variants(chunk)
            
            # Count results
            chunk_plof = (chunk_classified['pLoF_Level1'] != 'Not_pLoF').sum()
            total_variants += len(chunk_classified)
            total_plof += chunk_plof
            
            print(f"  Found {chunk_plof:,} pLoF variants in chunk {chunk_num}")
            
            # Write to output file (append mode after first chunk)
            mode = 'w' if first_chunk else 'a'
            header = first_chunk
            
            chunk_classified.to_csv(
                output_file, 
                sep='\t', 
                index=False,
                mode=mode,
                header=header,
                compression=output_compression
            )
            
            first_chunk = False
            
            # Memory cleanup
            del chunk_classified
            del chunk
        
        print(f"\nCompleted processing {input_file}")
        print(f"Total variants: {total_variants:,}")
        print(f"Total pLoF variants: {total_plof:,} ({total_plof/total_variants*100:.2f}%)")
        
    except Exception as e:
        print(f"Error processing {input_file}: {e}")
        raise

def create_summary_file(input_file: str, output_file: str, classifier: VEPpLofClassifier, chunksize: int = 5000):
    """
    Create a summary statistics file for the processed variants
    """
    print(f"Creating summary for {input_file}")
    
    input_compression = 'gzip' if input_file.endswith('.gz') else None
    
    # Count header lines to skip
    header_lines_to_skip = count_header_lines(input_file, input_compression)
    
    # Read first chunk to get column structure
    first_chunk = pd.read_csv(
        input_file,
        sep='\t',
        nrows=100,
        compression=input_compression,
        skiprows=header_lines_to_skip
    )
    
    # Initialize counters
    summary_counts = {}
    total_variants = 0
    
    # Process in chunks to count classifications
    chunk_reader = pd.read_csv(
        input_file,
        sep='\t',
        chunksize=chunksize,
        compression=input_compression,
        usecols=['pLoF_Level1', 'pLoF_Level2', 'pLoF_Combined'],
        skiprows=header_lines_to_skip
    )
    
    for chunk in chunk_reader:
        total_variants += len(chunk)
        
        # Count classifications in this chunk
        for combined_class in chunk['pLoF_Combined'].value_counts().items():
            class_name, count = combined_class
            summary_counts[class_name] = summary_counts.get(class_name, 0) + count
    
    # Create summary DataFrame
    summary_data = []
    for class_name, count in summary_counts.items():
        if class_name != 'Not_pLoF':
            level1, level2 = class_name.split('_', 1) if '_' in class_name else (class_name, class_name)
            summary_data.append({
                'Category': 'pLoF',
                'Level1': level1,
                'Level2': level2,
                'Combined': class_name,
                'Count': count,
                'Percentage': (count / total_variants * 100)
            })
    
    summary_df = pd.DataFrame(summary_data)
    summary_df = summary_df.sort_values(['Level1', 'Level2'])
    
    # Save summary
    summary_file = output_file.replace('.txt', '_summary.txt').replace('.gz', '_summary.txt')
    summary_df.to_csv(summary_file, sep='\t', index=False)
    print(f"Summary saved to: {summary_file}")
    
    return summary_df

# Command-line interface
def main():
    """Command-line interface for processing single files"""
    
    if len(sys.argv) < 2:
        print("Usage: python pLoF_classifier.py <input_file.vep.txt.gz> [gene_list_file] [chunksize]")
        print("Example: python pLoF_classifier.py sample.vep.txt.gz lof_genes.txt 5000")
        sys.exit(1)
    
    # Parse command line arguments
    input_file = sys.argv[1]
    gene_list_file = sys.argv[2] if len(sys.argv) > 2 else 'lof_intolerant_genes.txt'
    chunksize = int(sys.argv[3]) if len(sys.argv) > 3 else 5000
    
    # Check input file exists
    if not os.path.exists(input_file):
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)
    
    # Check gene list file exists
    if not os.path.exists(gene_list_file):
        print(f"Error: Gene list file not found: {gene_list_file}")
        sys.exit(1)
    
    # Generate output filename
    output_file = input_file.replace('.vep.txt', '_classified.txt')
    if not output_file.endswith('.gz') and input_file.endswith('.gz'):
        output_file += '.gz'
    
    print(f"VEP pLoF Classifier - Single File Mode")
    print(f"Input: {input_file}")
    print(f"Output: {output_file}")
    print(f"Gene list: {gene_list_file}")
    print(f"Chunk size: {chunksize:,}")
    print("-" * 50)
    
    try:
        # Initialize classifier
        classifier = VEPpLofClassifier(gene_list_file=gene_list_file)
        
        # Process file in chunks
        process_file_in_chunks(input_file, output_file, classifier, chunksize)
        
        # Create summary
        summary_df = create_summary_file(output_file, output_file, classifier, chunksize)
        print("\nClassification Summary:")
        print(summary_df.to_string(index=False))
        
        print(f"\nSuccessfully processed: {input_file}")
        print(f"Results saved to: {output_file}")
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

def batch_process_files(file_pattern: str, gene_list_file: str, chunksize: int = 5000):
    """
    Process multiple files (for use with external parallelization)
    Usage: Call this from a wrapper script or use main() with parallel
    """
    import glob
    
    files = glob.glob(file_pattern)
    print(f"Found {len(files)} files matching pattern: {file_pattern}")
    
    for input_file in files:
        try:
            output_file = input_file.replace('.vep.txt', '_classified.txt')
            if not output_file.endswith('.gz') and input_file.endswith('.gz'):
                output_file += '.gz'
            
            classifier = VEPpLofClassifier(gene_list_file=gene_list_file)
            process_file_in_chunks(input_file, output_file, classifier, chunksize)
            
        except Exception as e:
            print(f"Error processing {input_file}: {e}")
            continue

# Example usage for testing
def test_mode():
    """Test mode with example data"""
    print("Test mode - using example data")
    
    # You can uncomment this to test with your actual files
    # classifier = VEPpLofClassifier(gene_list_file='lof_intolerant_genes.txt')
    # process_file_in_chunks('test.vep.txt.gz', 'test_classified.txt.gz', classifier, 1000)
    
    print("Test mode completed")

if __name__ == "__main__":
    main()
