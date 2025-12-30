#!/bin/bash

set -euo pipefail
set +x


main() {


  local N="$(cat /home/dnanexus/job_input.json  | jq -r '.chr' )"

  local mask_files=()
  local outputs_idx=()



mkdir regenie_input regenie_masks regenie_logs regenie_output regenie_tmp


###########################
# Plink, Phen, Covar, Step1
###########################

echo "INFO: Downloading input files ..." >&2


# step1 files
if ! dx download --no-progress -r -f "$DX_PROJECT_CONTEXT_ID:/REGENIE/Step1/";then

    echo "ERROR: Download failed: Step 1 files" >&2
    return 1

# pgen
elif ! dx download --no-progress "$DX_PROJECT_CONTEXT_ID:/Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${N}_b0_v1.pgen" -o regenie_input/WGS.pgen; then

    echo "ERROR: Download failed: pgen file" >&2
    return 1

# psam
elif ! dx cat "$DX_PROJECT_CONTEXT_ID:/Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${N}_b0_v1.psam" |\
awk 'BEGIN{print "#FID","IID","PAT","MAT","SEX","PHENO1"}{ $6="-9";print}' > regenie_input/WGS.psam; then

    echo "ERROR: Download failed: psam file" >&2
    return 1


# pvar
elif ! dx cat "$DX_PROJECT_CONTEXT_ID:/Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${N}_b0_v1.pvar" |\
awk '{if($1 !~ "^#" && $1 !~ "^chr") $1 = "chr"$1; print }' > regenie_input/WGS.pvar; then

    echo "ERROR: Download failed: pvar file" >&2
    return 1


# phenotypes
elif ! dx download --no-progress "$DX_PROJECT_CONTEXT_ID:/Phenotypes/ukb_phenotypes_copied_from_wh3_files.txt" -o regenie_input/ukb_phenotype.txt; then

    echo "ERROR: Download failed: phenotype file" >&2
    return 1


# annotations
elif ! dx download --no-progress "$DX_PROJECT_CONTEXT_ID:/CSQ/csq_chr${N}.tsv.gz" -o regenie_input/CSQ.tsv.gz; then

    echo "ERROR: Download failed: annotation file" >&2
    return 1

else

    echo "INFO: Finished downloading files ..." >&2

fi




############
# Processing
############

echo "INFO: processing annotation files ..." >&2

# variants failing QC
if ! awk 'NR>1{if($7 ~ "PASS");else print $3}' regenie_input/WGS.pvar > regenie_input/low_quality_variants.txt; then

    echo "ERRIR: failed to create variant exclusion list" >&2
    return 1

elif ! {

  zcat regenie_input/CSQ.tsv.gz |\
  sed 's/Unlikley/Unlikely/g' |\
  awk -F"\t" '$13 == "NCRNA" ' |\
  awk -F"\t" 'NR==FNR{++qc_failed[$1];next}{if($3 in qc_failed) next; if($6 !~ "ENS") next; if( $13 == "PROT") print $3,$6,$13"_"$14; if($13 == "LRNA" || $13 == "NCRNA" || $14 ~ "PROM_" || $14 ~ "ENH_") print $3,$6,$13"_"$14"_"$12 }' OFS="\t" regenie_input/low_quality_variants.txt - |\
  tee >(gzip > regenie_input/ANN.txt.gz) |\
  awk '{print $2,$1 > "regenie_tmp/"$2".ann"}';

  ls regenie_tmp/*.ann |\
  xargs -P $(( $(nproc) - 1 )) -I {} awk \
  '{if(NR==1){gene_name=$1;gene_var=$2;split(gene_var,gene_info,":");gene_chr=gene_info[2];gene_pos=gene_info[3]} else gene_var=gene_var","$2}END{ gene_set_file="regenie_tmp/"gene_name".set";print gene_name,gene_chr,gene_pos,gene_var > gene_set_file}' {};

}; then

    echo "ERROR: failed to create annotation files" >&2
    return 1

elif ! cat regenie_tmp/*.set | gzip > regenie_input/SET.txt.gz  ; then

    echo "ERROR: failed to concatenate variant set files" >&2
    return 1

else

  echo "INFO: Finished processing annotation files ..." >&2
  rm -rf regenie_tmp/* || true

fi




############
# mask files
############



# cat > regenie_masks/ctrl_masks.txt <<EOL
# SYNON PROT_SYN
# HC_LOF PROT_PTV_HC,PROT_SPLICE_HC
# HC_MIS PROT_MIS_HC
# EOL

#INTRON PROT_INTRON,LRNA_INTRON_Plausible,LRNA_INTRON_Possible,LRNA_INTRON_Unlikely,NCRNA_INTRON_Plausible,NCRNA_INTRON_Possible,NCRNA_INTRON_Unlikely
#CTCF CRE_EMAR_CTCF_Plausible,CRE_EMAR_CTCF_Possible,CRE_EMAR_CTCF_Unlikely


# cat > regenie_masks/transcript_masks.txt <<EOL
# HC_LOF PROT_PTV_HC,PROT_SPLICE_HC
# HC_MIS PROT_MIS_HC
# LC_LOF PROT_PTV_LC,PROT_SPLICE_LC
# LC_MIS PROT_MIS_LC
# INDEL PROT_INFRAME
# BEN PROT_MIS_NC,PROT_UTR_uORF
# UTR PROT_UTR_5prime,PROT_UTR_3prime
# RNA3 LRNA_SPLICE_HC_Plausible,LRNA_SPLICE_HC_Possible,LRNA_SPLICE_HC_Unlikely,NCRNA_SPLICE_HC_Plausible,NCRNA_SPLICE_HC_Possible,NCRNA_SPLICE_HC_Unlikely
# RNA2 LRNA_EXON_Plausible,LRNA_SPLICE_LC_Plausible,NCRNA_EXON_Plausible,NCRNA_SPLICE_LC_Plausible
# RNA1 LRNA_EXON_Possible,LRNA_SPLICE_LC_Possible,NCRNA_EXON_Possible,NCRNA_SPLICE_LC_Possible
# RNA0 LRNA_EXON_Unlikely,LRNA_SPLICE_LC_Unlikely,NCRNA_EXON_Unlikely,NCRNA_SPLICE_LC_Unlikely
# EOL



# cat > regenie_masks/regulatory_masks.txt <<EOL
# PROM_5 CRE_PROM_ActH_Plausible,CRE_PROM_ActH_Possible,CRE_PROM_ActH_Unlikely
# PROM_4 CRE_PROM_ActM_Plausible,CRE_PROM_ActM_Possible,CRE_PROM_ActM_Unlikely
# PROM_3 CRE_PROM_Act_Plausible
# PROM_2 CRE_PROM_Act_Possible
# PROM_1 CRE_PROM_Act_Unlikely
# PROM_0 CRE_PROM_InactH_Plausible,CRE_PROM_InactH_Possible,CRE_PROM_InactH_Unlikely,CRE_PROM_InactM_Plausible,CRE_PROM_InactM_Possible,CRE_PROM_InactM_Unlikely,CRE_PROM_Inact_Plausible,CRE_PROM_Inact_Possible,CRE_PROM_Inact_Unlikely
# ELS4 CRE_ENH_ActProx_Plausible,CRE_ENH_ActDist_Plausible
# ELS3 CRE_ENH_ActProx_Possible,CRE_ENH_ActDist_Possible
# ELS2 CRE_ENH_ActProx_Unlikely,CRE_ENH_ActDist_Unlikely
# ELS1 CRE_ENH_InactProx_Plausible,CRE_ENH_InactProx_Possible,CRE_ENH_InactProx_Unlikely,CRE_ENH_InactDist_Plausible,CRE_ENH_InactDist_Possible,CRE_ENH_InactDist_Unlikely
# EOL


cat > regenie_masks/ncrna_masks.txt <<EOL
RNA3 LRNA_SPLICE_HC_Plausible,LRNA_SPLICE_HC_Possible,LRNA_SPLICE_HC_Unlikely,NCRNA_SPLICE_HC_Plausible,NCRNA_SPLICE_HC_Possible,NCRNA_SPLICE_HC_Unlikely
RNA2 LRNA_EXON_Plausible,LRNA_SPLICE_LC_Plausible,NCRNA_EXON_Plausible,NCRNA_SPLICE_LC_Plausible
RNA1 LRNA_EXON_Possible,LRNA_SPLICE_LC_Possible,NCRNA_EXON_Possible,NCRNA_SPLICE_LC_Possible
RNA0 LRNA_EXON_Unlikely,LRNA_SPLICE_LC_Unlikely,NCRNA_EXON_Unlikely,NCRNA_SPLICE_LC_Unlikely
EOL


# cat > regenie_masks/enhancer_masks.txt <<EOL
# ELS4 CRE_ENH_ActProx_Plausible,CRE_ENH_ActDist_Plausible
# ELS3 CRE_ENH_ActProx_Possible,CRE_ENH_ActDist_Possible
# ELS2 CRE_ENH_ActProx_Unlikely,CRE_ENH_ActDist_Unlikely
# ELS1 CRE_ENH_InactProx_Plausible,CRE_ENH_InactProx_Possible,CRE_ENH_InactProx_Unlikely,CRE_ENH_InactDist_Plausible,CRE_ENH_InactDist_Possible,CRE_ENH_InactDist_Unlikely
# EOL


#mask_files+=("transcript_masks.txt" "regulatory_masks.txt" "ctrl_masks.txt")

mask_files+=("ncrna_masks.txt")

#############
# run wrapper
#############


echo "INFO: Running regenie" >&2


if ! parallel \
    --jobs $(( $(nproc) / 15 )) \
    --results "${HOME}/regenie_logs" \
    --joblog "${HOME}/regenie_output/${DX_JOB_ID}.parallel.log" \
    regenie \
  --step 2 \
  --mask-def ${HOME}/regenie_masks/{} \
  --out ${HOME}/regenie_output/{} \
  --pred ${HOME}/Step1/step1_loco.list \
  --pgen ${HOME}/regenie_input/WGS \
  --exclude ${HOME}/regenie_input/low_quality_variants.txt \
  --phenoFile ${HOME}/regenie_input/ukb_phenotype.txt \
  --covarFile ${HOME}/regenie_input/ukb_phenotype.txt \
  --anno-file ${HOME}/regenie_input/ANN.txt.gz \
  --set-list ${HOME}/regenie_input/SET.txt.gz \
  --phenoColList react.time,all.iq2 \
  --covarColList sex2,birth.year,age2,age.squared2,agebysex2,age.squaredbysex2,pca{1:25} \
  --maxCatLevels 30 \
  --qt \
  --firth \
  --approx \
  --aaf-bins 0.00001,0.0001 \
  --vc-tests acato-full \
  --vc-maxAAF 0.0001 \
  --minMAC 10 \
  --apply-rint \
  --threads 15 \
  --bsize 500 \
  --gz \
  --verbose ::: "${mask_files[@]}"; then

        echo "WARNING: Some regenie jobs failed or killed" >&2
        awk '$7 != 0' "${HOME}/regenie_output/${DX_JOB_ID}.parallel.log" >&2

else

        echo "INFO: Finished running all regenie jobs" >&2

fi            




##########
# log file
##########


if [[ -f "${HOME}/regenie_output/${DX_JOB_ID}.parallel.log" ]]; then
echo "==== OUPUT LOGS ====" >> "${HOME}/regenie_output/${DX_JOB_ID}.parallel.log"

find "${HOME}/regenie_logs" -name stdout -exec cat {} + >> "${HOME}/regenie_output/${DX_JOB_ID}.parallel.log" || true

echo "==== ERROR LOGS ====" >> "${HOME}/regenie_output/${DX_JOB_ID}.parallel.log"
  
find "${HOME}/regenie_logs" -name stderr -exec cat {} + >> "${HOME}/regenie_output/${DX_JOB_ID}.parallel.log" || true

fi



########
# Upload
########


if ! mapfile -t outputs_idx < <(dx upload --recursive "${HOME}/regenie_output" -p --brief); then


    echo "ERROR: Failed to upload results" >&2
    return 1

elif ! printf "%s\n" "${outputs_idx[@]}" |\
  xargs -P1 -I{} dx-jobutil-add-output output_files "{}" --class=array:file ; then

    echo "ERROR: Failed to commit uploaded results" >&2
    return 1

else

    echo "INFO: Successfully added regenie outputs to applet's record of final outputs" >&2

fi



}