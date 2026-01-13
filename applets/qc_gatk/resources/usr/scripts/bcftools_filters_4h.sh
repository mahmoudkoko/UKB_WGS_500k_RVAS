bcf_filter_gt() {

    local input_bcf="$1"
    local output_bcf="$3"

    # Decompress & stream bcf
    bcftools view --no-version -Ou "${input_bcf}" |\
    # Keep this set of tags: MQ,AAScore,QD,QDalt - GT,GQ,DP,AD,PL
    bcftools annotate --no-version -Ou -x ID,^INFO/MQ,^INFO/AAScore,^INFO/QD,^INFO/QDalt,^FORMAT/GT,^FORMAT/GQ,^FORMAT/DP,^FORMAT/AD,^FORMAT/PL |\
    # Split multi-allelic sites
    bcftools norm --no-version -Ou -m-any -N -w 1 --keep-sum AD |\
    # Unphase if any (new) alleles are phased
    bcftools +setGT --no-version -Ou -- -n u -t a |\
    # Set to missing if any (new) alleles are ambiguous
    bcftools +setGT --no-version -Ou -- -n . -t ./x |\
    # Add FORMAT annotations (Depth from AD, GQ from PL, Allele Balance)
    bcftools +fill-tags --no-version -Ou -- -t 'FMT/GD:1=sSUM(FMT/AD),FMT/plGQ:1=int(sMEDIAN(FMT/PL)-sMIN(FMT/PL)),VAF' |\
    # Count genotypes befefore QC
    bcftools +fill-tags --no-version -Ou -- -t 'INFO/NN_NS0:1=COUNT(GT="mis"),INFO/RR_NS0:1=COUNT(GT="0/0"),INFO/RA_NS0:1=COUNT(GT = "0/1"),INFO/AA_NS0:1=COUNT(GT = "1/1")' |\
    # Calculate the # reference/heterozygous/homozygous with low allele balance
    bcftools +fill-tags --no-version -Ou -- -t 'INFO/RR_LAB0:1=COUNT( GT="0/0" & VAF > 0.1 ),INFO/RA_LAB0:1=COUNT( GT="0/1" & (VAF < 0.4 | VAF > 0.6) ),INFO/AA_LAB0:1=COUNT( GT="1/1" & VAF < 0.9 )' |\
    # Calculate # reference/heterozygous,homozygous calls with GQ < 40
    bcftools +fill-tags --no-version -Ou -- -t 'INFO/RR_LGQ0:1=COUNT(GT="0/0" & FMT/GQ < 40 & FMT/plGQ < 40),INFO/RA_LGQ0:1=COUNT(GT="0/1" & FMT/GQ < 40 & FMT/plGQ < 40),INFO/AA_LGQ0:1=COUNT(GT="1/1" & FMT/GQ < 40 & FMT/plGQ < 40)' |\
    # Set all reference to missing if the PL field does not support ref call
    bcftools filter --no-version -Ou -S . -e ' GT="0/0" & ( (PL[:0] >= PL[:1]) | (PL[:0] >= PL[:2]) ) ' |\
    # Set all heterozygous to missing if PL field does not support het call
    bcftools filter --no-version -Ou -S . -e ' GT="0/1" & ( (PL[:1] >= PL[:0]) | (PL[:1] >= PL[:2]) ) ' |\
    # Set all homozygous to missing if PL field does not support hom call        
    bcftools filter --no-version -Ou -S . -e ' GT="1/1" & ( (PL[:2] >= PL[:0]) | (PL[:2] >= PL[:1]) ) ' |\
    # Set non-reference genotypes to missing if GQ < 11
    bcftools filter --no-version -Ou -S . -e ' (GT="0/1" | GT="1/1") & GQ < 10 & plGQ < 10 ' |\
    # Set reference to missing if VAF is lower than 0.3 or depth < 6
    bcftools filter --no-version -Ou -S . -e ' GT="0/0" & (FMT/AD[:0] < 6 | FMT/VAF > 0.3 )' |\
    # Set homozygous to missing if VAF is lower than 0.7 or depth < 6
    bcftools filter --no-version -Ou -S . -e ' GT="1/1" & (FMT/AD[:1] < 6 | FMT/VAF < 0.7 )' |\
    # Set heterozygous to missing if VAF < 0.1/ > 0.9, or allele depth < 3
    bcftools filter --no-version -Ou -S . -e ' GT="0/1" & (FMT/AD[:0] < 3 | FMT/AD[:1] < 3 | FMT/VAF < 0.1 | FMT/VAF > 0.9 )' |\
    # Set non-reference to missing if allele depth is lower than 33% of total depth (i.e. more than 2/3 of the alleles do not support non-ref call)
    bcftools filter --no-version -Ou -S . -e ' (GT="0/1" | GT="1/1") & ( FMT/GD / FMT/DP ) < 0.333 ' |\
    # Annotate any records with AC0 as such
    bcftools filter --no-version -Ou -s 'AC0' -m+ -e 'AC=0' |\
    # Annotate variant types and allele length
    bcftools +fill-tags --no-version -Ou -- -t 'TYPE,INFO/LEN_REF:1=STRLEN(REF),INFO/LEN_ALT:1=STRLEN(ALT)' |\
    # Recalculate allele and genotype counts after QC
    bcftools +fill-tags --no-version -Ou -- -t 'AC,AF,ExcHet,INFO/GQ_AVG:1=MEAN(FMT/GQ),INFO/DP_AVG:1=MEAN(FMT/DP),INFO/GD_AVG:1=SUM(FMT/GD)/SUM(FMT/DP)' |\
    # Count genotypes after QC
    bcftools +fill-tags --no-version -Ou -- -t 'INFO/NN_NS1:1=COUNT(GT="mis"),INFO/RR_NS1:1=COUNT(GT="0/0"),INFO/RA_NS1:1=COUNT(GT = "0/1"),INFO/AA_NS1:1=COUNT(GT = "1/1")' |\
    # Calculate the # reference/heterozygous/homozygous with low allele balance
    bcftools +fill-tags --no-version -Ou -- -t 'INFO/RR_LAB1:1=COUNT( GT="0/0" & VAF > 0.1 ),INFO/RA_LAB1:1=COUNT( GT="0/1" & (VAF < 0.4 | VAF > 0.6) ),INFO/AA_LAB1:1=COUNT( GT="1/1" & VAF < 0.9 )' |\
    # Calculate # reference/heterozygous,homozygous calls with GQ < 40
    bcftools +fill-tags --no-version -Ou -- -t 'INFO/RR_LGQ1:1=COUNT(GT="0/0" & FMT/GQ < 40 & FMT/plGQ < 40),INFO/RA_LGQ1:1=COUNT(GT="0/1" & FMT/GQ < 40 & FMT/plGQ < 40),INFO/AA_LGQ1:1=COUNT(GT="1/1" & FMT/GQ < 40 & FMT/plGQ < 40)' |\
    # Remove FORMAT tags to reduce file size (keep depth & pl to calculate QD)
    bcftools annotate --no-version -Ou -x FORMAT/DP,FORMAT/GD,FORMAT/AD,FORMAT/VAF,FORMAT/GQ,FORMAT/plGQ,FORMAT/PL |\
    # Save intermediate BCF file
    bcftools view --no-version -Ob -o "${output_bcf}" --write-index=csi
}