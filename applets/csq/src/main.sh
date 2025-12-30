#!/bin/bash

set -euo pipefail
set +x

chmod +x /usr/local/bin/vep_table_parser.R


main(){

local vep_chr="$(cat /home/dnanexus/job_input.json  | jq -r '.vep_chr' )"
local input_files=()
local output_files=()
local run_summary
local csq_files=()
local csq_item=""
local var_files=()
local var_item=""
local log_idx=""
local output_idx=""


# function to covert files
convert_gzip_to_bgzip() {
    local csq_item="$1"
    
is_gzip_empty() {
    local file="$1"
    local size
    
    # Extract uncompressed size from gzip header
    size=$(gunzip -l "$file" 2>/dev/null | awk 'NR==2 {print $2}')
    
    case "$size" in
        0) return 0 ;;      # Empty
        ''|*[!0-9]*) return 2 ;;  # Invalid/error
        *) return 1 ;;      # Not empty
    esac
}

    if is_gzip_empty "csq/${csq_item}"; then
        echo "Skipped empty item ${csq_item}"
        return 1
    elif ! zcat "csq/${csq_item}" | sort -k2,2n -k3,3 -k4,4 -k5,5 | bgzip > "var/${csq_item}"; then
        echo "Failed to convert ${csq_item}"
        return 1
    fi
}


export -f convert_gzip_to_bgzip




mkdir logs csq var


# Download

echo "Downloading VEP annotations"

dx download --no-progress -f -r "$DX_PROJECT_CONTEXT_ID:/WGS/chr${vep_chr}/vep"


# Read input files

input_files=(vep/*.tsv.gz)


# Create corresponding output file paths

for file in "${input_files[@]}"; do
    basename=$(basename "$file" | sed -e "s/ukb24308_c${vep_chr}_//" -e 's/.qc.sites.vep//')
    output_files+=("csq/$basename")
done


# process

echo "Processing ${#input_files[@]} files"

if parallel \
--jobs $(( $(nproc) * 90 / 100 )) \
--results logs \
--joblog csq_chr${vep_chr}.log.txt \
vep_table_parser.R --input {1} --output {2} \
::: "${input_files[@]}" \
:::+ "${output_files[@]}" ; then

  echo "Finished processing all files without errors"


else

  echo "Finished processing files with errors."

  echo "Failed jobs:"

  cat csq_chr${vep_chr}.log.txt | awk -F"\t" '$7!=0{print $NF}' || true


fi




run_summary=$(awk -F"\t" 'BEGIN{ok=0;fail=0}NR>1{if($7==0) {++ok ; ts+=$4} else {++fail;tf+=$4}}END{if(ts > 0) printf "Successful: %d (Avg: %.2fmin)", ok,(ts/(ok)/60); if(tf > 0) printf "Failed: %d (Avg: %.2fmin)\n", fail,(tf/(fail)/60)}' csq_chr${vep_chr}.log.txt 2> /dev/null || echo "Failed to create summary")
echo "$run_summary"

###########



###############
# BGZIP > BGZIP
###############

# read files

mapfile -t csq_files < <(ls csq/ | sort -V)

echo "Converting ${#csq_files[@]} files to bgzip"



if parallel \
--jobs $(( $(nproc) * 90 / 100 )) \
--results logs \
--joblog bgzip_chr${vep_chr}.log.txt \
convert_gzip_to_bgzip {} ::: "${csq_files[@]}"; then

  echo "Finished processing all files without errors"

else

  echo "Finished processing files with errors."

  echo "Failed jobs:"

  cat bgzip_chr${vep_chr}.log.txt | awk -F"\t" '$7!=0{print $NF}' || true

fi




######
# Bind
######


echo "Binding all variant tables"

# collect csq lists
echo -e "Chr\tPos\tID\tRef_allele\tAlt_allele\tEnsembl_ID\tVariant_type\tgnomADg\tCADD\tConserved\tConstrained\tDeleterious\tVariant_group\tVariant_csq\tWorst_group\tWorst_csq" |\
bgzip > csq_chr${vep_chr}.tsv.gz


mapfile -t var_files < <(ls var/ | sort -V)

for ((i=0; i < ${#var_files[@]}; ++i)); do

    var_item=${var_files[$i]}

    if ! cat "var/${var_item}" >>  csq_chr${vep_chr}.tsv.gz; then

           echo "Failed to append ${var_item}"
           exit 1;

    else

            continue;

    fi


done



echo "Uploading outputs"

# upload

log_idx=$(dx upload --brief csq_chr${vep_chr}.log.txt)


output_idx=$(dx upload --brief csq_chr${vep_chr}.tsv.gz)

dx-jobutil-add-output log_file "${log_idx}" --class=file

dx-jobutil-add-output output_file "${output_idx}" --class=file

}