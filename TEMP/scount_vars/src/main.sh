#!/bin/bash

set -euo pipefail
set +x




main(){

  local N="$(cat /home/dnanexus/job_input.json  | jq -r '.chr' )"
  local var_groups=()
  local var_item=""
  local upload_idx=()

scount(){

  local var="$1"

  plink2 \
  --threads 15 \
  --memory 30000 \
  --pfile plink/WGS 'vzs' \
  --extract "var/${var}.ids" \
  --max-mac 10 \
  --sample-counts 'zs' 'cols=het,homalt,single' \
  --out "scount/${var}"
}


export -f scount


  mkdir "var" "plink" "scount" "logs"


# download genotypes

echo "Downloading PLINK files"

# pgen
dx download --no-progress "$DX_PROJECT_CONTEXT_ID:/Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${N}_b0_v1.pgen" -o plink/WGS.pgen

# pvar
dx cat "$DX_PROJECT_CONTEXT_ID:/Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${N}_b0_v1.pvar"  |\
zstd --quiet - -o plink/WGS.pvar.zst

# psam
dx cat "$DX_PROJECT_CONTEXT_ID:/Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${N}_b0_v1.psam" |\
awk '{ $6="-9";print}' > plink/WGS.psam 



echo "Downloading CSQ file"

dx download --no-progress -o plink/CSQ.tsv.gz "$DX_PROJECT_CONTEXT_ID:CSQ/csq_chr${N}.tsv.gz"


echo "Creating variant groups for burden scores"


zcat plink/CSQ.tsv.gz |\
awk -F"\t" 'NR>1 && $NF == "Yes"' |\
uniq |\
awk -F"\t" -v N=${N} '{var_id=$3;var_file="var/chr"N"__"$7"__"$12"__"$13"__"$14".ids"; print var_id > var_file }' OFS="\t" 



# map

mapfile -t var_groups < <(find var/ -name "*.ids" -type f |sed -e 's/var\///' -e 's/.ids//')


echo "Found ${#var_groups[@]} groups"

printf "%s\n" ${var_groups[@]}




if parallel \
--jobs $(( $(nproc) / 15 )) \
--results logs \
--joblog scount/scount_parallel.log \
scount ::: "${var_groups[@]}" ; then

  echo "Finished processing all files without errors"


else

  echo "Finished processing files with errors."

  echo "Failed jobs:"

  cat scount/scount_parallel.log | awk -F"\t" '$7!=0{print $NF}' || true

  echo "==== OUPUT LOGS ====" >> scount/scount_parallel.log

  find logs -name stdout -exec cat {} + >> scount/scount_parallel.log || true

  echo "==== ERROR LOGS ====" >> scount/scount_parallel.log
  
  find logs -name stderr -exec cat {} + >> scount/scount_parallel.log || true

fi




if mapfile -t upload_idx < <(dx upload --recursive "scount" -p --brief); then

    echo "Successfully uploaded ${#upload_idx[@]} outputs"

else

    echo "ERROR: Failed to upload"
    return 1


fi





if printf "%s\n" "${upload_idx[@]}" | xargs -P1 -I{} dx-jobutil-add-output output_files "{}" --class=array:file ; then

    echo "Successfully added qc outputs to applet's record of final outputs"

else

    echo "Upload failed"
    return 1

fi




}