scatter_pvar() {
local CHR="$1"
local IDX=()

if ! mkdir -p vep/chr$CHR; then

echo "Failed to create working dir" >&2

elif ! dx cat "$DX_PROJECT_CONTEXT_ID:/Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${CHR}_b0_v1.pvar" |\
    tr ' ' '\t' |\
    awk 'BEGIN{print "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"}!/^#/{var_id=$3;gsub(".+:chr","chr",var_id);split(var_id, var_info, ":");print var_info[1],var_info[2],var_id,var_info[3],var_info[4],".",".","."}' OFS="\t" |\
    bgzip > "vep/chr$CHR/chr${CHR}.vcf.gz"; then

echo "Failed to convert pvar to vcf" >&2

elif ! bcftools index "vep/chr$CHR/chr${CHR}.vcf.gz"; then

echo "Failed to convert pvar to vcf" >&2

elif ! bcftools +scatter --prefix "ukb24308_c${CHR}_b" --threads 2 -Oz -o "vep/chr$CHR/" -n50000 "vep/chr$CHR/chr${CHR}.vcf.gz"; then

echo "Failed to split vcf" >&2

elif ! rm "vep/chr$CHR/chr${CHR}.vcf.gz" "vep/chr$CHR/chr${CHR}.vcf.gz.csi"; then

echo "Failed to remove tmp vcf" >&2

elif ! rename.ul ".vcf" ".qc.sites.vcf" vep/chr$CHR/ukb24308_c${CHR}_b* ; then

echo "Failed to rename tmp vcf" >&2

elif ! mapfile -t IDX < <(dx upload --no-progress --brief --recursive "vep/chr$CHR/" -p --path "$DX_PROJECT_CONTEXT_ID:/WGS/chr${CHR}/vep_input/") ; then

echo "Failed to upload split vcfs" >&2

elif ! rm -rf "vep/chr$CHR/"; then

echo "Failed to remove tmp split vcfs" >&2

else

echo "Finished splitting chr $CHR" >&2

printf "%s\n" "${IDX[@]}"

fi
}