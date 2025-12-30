bcf_filter_gt() {

    local input_bcf="$1"
    local output_bcf="$2"

    # Decompress & stream bcf
    bcftools view -M 10 --no-version -Ou "${input_bcf}" |\
    # Keep this set of tags: INFO/AAScore,QD,QDalt - FORMAT/GT,GQ,AD,PL
    bcftools annotate --no-version -Ou -x ^INFO/AAScore,^INFO/QD,^INFO/QDalt,^FORMAT/GT,^FORMAT/GQ,^FORMAT/AD,^FORMAT/PL |\
    # Split multi-allelic sites
    bcftools norm --no-version -Ou -m-any -N -w 1 --keep-sum AD |\
    # Remove FORMAT/PL tags to reduce file size
    bcftools annotate --no-version -Ou -x FORMAT/PL |\
    # Add FORMAT/VAF annotations (allele balance)
    bcftools +fill-tags --no-version -Ou -- -t 'VAF' |\
    # Keep GT if above min GQ (10), DP (8), VAF (ref/hom:0.3,0.7 | het:0.1,0.9)
    bcftools filter --no-version -Ou -S . -e 'GT="mis" | GQ < 10 | (GT="hom" & (FMT/AD[:1] < 8 | FMT/VAF < 0.7)) | (GT="het" & (FMT/AD[:0] < 4 | FMT/AD[:1] < 4 | FMT/VAF < 0.1 | FMT/VAF > 0.9))' |\
    # Count genotypes after QC
    bcftools +fill-tags --no-version -Ou -- -t 'TYPE,AC,AF,INFO/GQ_AVG:1=MEAN(FMT/GQ),NS,INFO/NS_MIS:1=COUNT(GT="mis"),INFO/NS_REF:1=COUNT(GT="ref"),INFO/NS_HET:1=COUNT(GT = "het"),INFO/NS_HOM:1=COUNT(GT = "hom"),INFO/GQ40_REF:1=COUNT(GT="ref" & FMT/GQ < 40 ),INFO/GQ40_HET:1=COUNT(GT="het" & FMT/GQ < 40 ),INFO/GQ40_HOM:1=COUNT(GT="hom" & FMT/GQ < 40 )' |\
    # Remove FORMAT tags to reduce file size
    bcftools annotate --no-version -Ou -x FORMAT/GQ,FORMAT/AD,FORMAT/VAF |\
    # Annotate any records with AC0 as such
    bcftools filter --no-version -Ou -s 'AC0' -m+ -e 'AC=0' |\
    # Save BCF file
    bcftools view --no-version -Ob -o "${output_bcf}" --write-index=csi
}