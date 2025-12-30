=head1 LICENSE

Copyright [2025] Wellcome Trust Sanger Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=head1 CONTACT

 HumGen Sanger <mm60@sanger.ac.uk>
    
=cut

=head1 NAME

 RegSc

=head1 SYNOPSIS

 vep -i variations.vcf --plugin RegSc,score1_name=score1_file.bed.gz,score2_name=score2_file.bed.gz
 vep -i variations.vcf --plugin RegSc,score1_name=score1_file.bed.gz,multi=max
 vep -i variations.vcf --plugin RegSc,score1_name=score1_file.bed.gz,multi=average
 vep -i variations.vcf --plugin RegSc,score1_name=score1_file.bed.gz,exact_indel_match=false

=head1 DESCRIPTION

 A VEP plugin that retrieves pre-calculated scores for variants from tabix-indexed region-based database files.
 
 Multiple score databases can be provided as comma-separated name=file pairs.
 Each database should be tabix-indexed and contain the following columns (BED-like format with zero-based coordinates):
 chr, start, end, gene_id, score
 
 Variants are matched if they fall within the genomic region (start <= variant_pos < end) and match the gene ID.
 
 When multiple scores exist for the same variant, the multi parameter controls how they are handled:
 - all (default): return all values as comma-separated list
 - max: return maximum value
 - min: return minimum value 
 - average: return average value

 When exact_indel_match=false, indels and MNVs that don't have exact matches will use positional
 overlap matching with any regions containing SNV-like entries from the database, applying the same aggregation logic.

# to use with vep, copy to your plugins folder

 mv RegSc.pm ~/.vep/Plugins

# call vep directly using pre-calculated scores
 ./vep -i variations.vcf --plugin RegSc,score1_name=score1_file.bed.gz,score2_name=score2_file.bed.gz
 ./vep -i variations.vcf --plugin RegSc,score1_name=score1_file.bed.gz,multi=max
 ./vep -i variations.vcf --plugin RegSc,score1_name=score1_file.bed.gz,exact_indel_match=false

# the scores should have this structure: chr,start,end,ens_gene_id,score
# coordinates are zero-based (BED format): start is inclusive, end is exclusive
# variant at position 100 matches region 50-150 but not region 100-200

=cut

package RegSc;

use strict;
use warnings;
use List::Util qw(max min sum);

use Bio::EnsEMBL::Utils::Sequence qw(reverse_comp);
use Bio::EnsEMBL::Variation::Utils::BaseVepTabixPlugin;

use base qw(Bio::EnsEMBL::Variation::Utils::BaseVepTabixPlugin);

sub new {
  my $class = shift;
  
  my $self = $class->SUPER::new(@_);

  # Test if tabix exists
  die "\nERROR: tabix does not seem to be in your path\n" unless `which tabix 2>&1` =~ /tabix$/;

  $self->expand_left(0);
  $self->expand_right(0);
  $self->get_user_params();
  
  # Parse parameters using the same method as CADD/SpliceAI
  my $params = $self->params_to_hash();
  my @files;
  
  # Initialize score databases hash and headers
  $self->{score_dbs} = {};
  $self->{headers} = {};
  
  # Set default aggregation method for multiple scores
  $self->{multi_method} = 'all';
  
  # Set default for exact indel matching
  $self->{exact_indel_match} = 1; # true by default
  
  if (!keys %$params) {
    die "\nERROR: No score databases provided. Use format: score1_name=file1.bed.gz,score2_name=file2.bed.gz\n";
  } else {
    foreach my $param_name (keys %$params) {
      my $param_value = $params->{$param_name};
      
      # Handle special multi parameter
      if ($param_name eq 'multi') {
        if ($param_value =~ /^(all|max|min|average)$/) {
          $self->{multi_method} = $param_value;
        } else {
          die "\nERROR: Invalid multi parameter value '$param_value'. Valid options: all, max, min, average\n";
        }
        next;
      }
      
      # Handle exact_indel_match parameter
      if ($param_name eq 'exact_indel_match') {
        if ($param_value =~ /^(true|false)$/i) {
          $self->{exact_indel_match} = ($param_value =~ /^true$/i) ? 1 : 0;
        } else {
          die "\nERROR: Invalid exact_indel_match parameter value '$param_value'. Valid options: true, false\n";
        }
        next;
      }
      
      # Handle score database files
      my $file_path = $param_value;
      
      # Validate file exists and is readable
      die "\nERROR: Score file $file_path does not exist or is not readable\n" unless -r $file_path;
      
      # Add file to tabix handler
      $self->add_file($file_path);
      push @files, $file_path;
      
      # Store mapping of score name to file
      $self->{score_dbs}->{$param_name} = $file_path;
      
      # Store header info for each score
      my $method_str = $self->{multi_method} eq 'all' ? "all values (comma-separated)" : 
                       $self->{multi_method} eq 'max' ? "maximum value" :
                       $self->{multi_method} eq 'min' ? "minimum value" : "average value";
      my $match_str = $self->{exact_indel_match} ? "region-based matching only" : "region-based matching with expanded overlap for indels/MNVs";
      $self->{headers}->{$param_name} = "Pre-calculated region-based score from $param_name database ($method_str when multiple scores exist, $match_str)";
    }
  }
  
  # Check that at least one score database was provided
  die "\nERROR: No valid score databases provided\n" unless @files > 0;

  return $self;
}

sub feature_types {
  return ['Transcript'];
}

sub get_header_info {
  my $self = shift;
  return $self->{headers};
}

sub run {
  my ($self, $tva) = @_;
  
  # Run for all variants with transcript context
  my $vf = $tva->variation_feature;
  
  # Get transcript and gene information
  my $transcript = $tva->transcript;
  my $gene_id = $transcript->{_gene}->stable_id;

  # Get chromosome (handle different naming conventions)
  my $chr = $vf->{chr};
  $chr =~ s/^chr//i; # Remove 'chr' prefix if present
  
  # Convert VCF position (1-based) to compare with BED regions (0-based)
  my $variant_pos = $vf->{start}; # VEP uses 1-based coordinates
  
  # Determine if this is a SNV
  my $allele_string = $vf->allele_string;
  my ($seq_ref, $seq_alt) = split /\//, $allele_string;
  my $is_snv = (length($seq_ref) == 1 && length($seq_alt) == 1);
  
  # Get data from all score databases and match variants
  my %results;
  
  # Get all data for this genomic region from all files
  # Handle insertions where end < start by adjusting query coordinates
  my $query_start = $vf->{start};
  my $query_end = $vf->{end};
  if ($query_end < $query_start) {
    # This is an insertion, query the insertion point
    $query_end = $query_start;
  }
  my @all_data = @{$self->get_data($chr, $query_start, $query_end)};
  
  # Group matching records by score database - first try normal region matching
  my %score_groups;
  
  foreach my $data_record (@all_data) {
    # Match variant if it falls within the region and matches gene
    # BED format: start is inclusive (0-based), end is exclusive
    # VEP variant position is 1-based, so we need to adjust for comparison
    # Convert variant position to 0-based for comparison: variant_pos - 1
    my $variant_pos_0based = $variant_pos - 1;
    
    if ($data_record->{start} <= $variant_pos_0based &&
        $variant_pos_0based < $data_record->{end} &&
        $data_record->{gene} eq $gene_id) {
      
      # Find which score database this record came from
      foreach my $score_name (keys %{$self->{score_dbs}}) {
        my $file_path = $self->{score_dbs}->{$score_name};
        if ($data_record->{file} eq $file_path) {
          push @{$score_groups{$score_name}}, $data_record->{score};
          last;
        }
      }
    }
  }
  
  # If no matches found and this is not a SNV and exact_indel_match is false,
  # try expanded overlap matching for indels/MNVs
  if (!%score_groups && !$is_snv && !$self->{exact_indel_match}) {
    
    # For indels/MNVs, check if any part of the variant overlaps with any region
    # Convert variant span to 0-based coordinates
    my $variant_start_0based = $vf->{start} - 1;
    my $variant_end_0based = $vf->{end} - 1;
    
    foreach my $data_record (@all_data) {
      # Check if variant span overlaps with the region and matches gene
      # Overlap condition: variant_start < region_end && variant_end >= region_start
      if ($variant_start_0based < $data_record->{end} &&
          $variant_end_0based >= $data_record->{start} &&
          $data_record->{gene} eq $gene_id) {
        
        # Find which score database this record came from
        foreach my $score_name (keys %{$self->{score_dbs}}) {
          my $file_path = $self->{score_dbs}->{$score_name};
          if ($data_record->{file} eq $file_path) {
            push @{$score_groups{$score_name}}, $data_record->{score};
            last;
          }
        }
      }
    }
  }
  
  # Process grouped scores according to multi_method
  foreach my $score_name (keys %score_groups) {
    my @scores = @{$score_groups{$score_name}};
    
    if (@scores == 1) {
      # Single score, format to 3 decimal places for consistency
      $results{$score_name} = sprintf("%.3f", $scores[0]);
    } elsif (@scores > 1) {
      # Multiple scores, apply aggregation method
      if ($self->{multi_method} eq 'all') {
        my @formatted_scores = map { sprintf("%.3f", $_) } @scores;
        $results{$score_name} = join(',', @formatted_scores);
      } elsif ($self->{multi_method} eq 'max') {
        $results{$score_name} = sprintf("%.3f", max(@scores));
      } elsif ($self->{multi_method} eq 'min') {
        $results{$score_name} = sprintf("%.3f", min(@scores));
      } elsif ($self->{multi_method} eq 'average') {
        my $avg = sum(@scores) / @scores;
        $results{$score_name} = sprintf("%.3f", $avg);
      }
    }
  }

  return \%results;
}

# Parse data from annotation database files
sub parse_data {
  my ($self, $line, $file) = @_;
  
  chomp $line;
  my @split = split /\t/, $line;
  
  # Ensure we have the expected number of columns (5)
  return {} unless @split >= 5;
  
  return {
    chr => $split[0],
    start => $split[1],    # 0-based start position (BED format)
    end => $split[2],      # 0-based end position (BED format, exclusive)
    gene => $split[3],     # Ensembl gene ID
    score => $split[4],    # Score value
    file => $file,         # Track which file this record came from
  };
}

sub get_start {
  return $_[1]->{start};
}

sub get_end {
  return $_[1]->{end};
}

1;