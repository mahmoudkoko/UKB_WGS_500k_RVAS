#!/bin/bash

set -euo pipefail
set +x



main() {

# Install apptainer and source utilities.sh

if ! sudo apt install -y /usr/local/assets/apptainer_1.4.1_amd64.deb; then
	echo "ERROR: Failed to install apptainer" >&2
	exit 1
elif ! source /usr/local/scripts/utilities.sh; then
	echo "ERROR: Failed to source utilities.sh" >&2
	exit 1

fi


export CADD_DATA_DIR_REMOTE="/Resources/cadd_v1_7_data"



prepare_cadd_vcfs (){

	local vcf_file_id
	local vcf_file_prefix
	local cadd_vcfs=()
	
for (( vcf_idx = 0; vcf_idx < ${#input_vcfs[@]}; ++vcf_idx )); do

	vcf_file_id=$(echo "${input_vcfs[$vcf_idx]}" | jq -r ."$dnanexus_link")
	vcf_file_prefix="${input_vcfs_prefix[$vcf_idx]}"
	
	cadd_vcfs[$v]="${vcf_file_prefix}.cadd.vcf.gz"

done


# function to download data

get_cadd_data_files() {

local file_path="$1"
local file_name=$(basename "${file_path}" || echo "")
local file_dir=$(dirname "${file_path}" || echo "")
local file_id=$(dx describe --json --multi "${DX_PROJECT_CONTEXT_ID}:${CADD_DATA_DIR_REMOTE}/${file_path}" | jq -r '.[0].id' || echo "null")


if [[ "$file_path" =~ \/$ || "$file_id" =~ null ]]; then

    echo "Failed to identify file ID" >&2
    echo "FAILED: $file_path"
    return 1

elif ! mkdir -p "${HOME}/${file_dir}" ; then

    echo "Failed to create local dir" >&2
    echo "FAILED: $file_path"
    return 1

elif ! dx download --lightweight -r -f --no-progress -o "${HOME}/${file_dir}/${file_name}" ${DX_PROJECT_CONTEXT_ID}:${file_id}; then

    echo "Failed to download" >&2
    echo "FAILED: $file_path"
    return 1

else 

    echo "Downloaded successfully" >&2
    echo "DOWNLOADED: $file_path"
    return 0

fi

}


export -f get_cadd_data_files
##########







mkdir -p "${HOME}/parallel"



time parallel \
	--retry 1 \
	--resume \
    --jobs $(( $(nproc) * 2 )) \
    --results "${HOME}/parallel" \
    --joblog "${HOME}/parallel/parallel.log" \
    get_cadd_data_files ::: ${cadd_files_list[@]} &


            echo "Some CADD jobs failed"

    fi



	echo "Annotating VCFs"

	mkdir ${HOME}/parallel_dir/

	N_JOBS=$(cat ${HOME}/job_input.json  | jq -r '.cadd_jobs' || echo 1 )

	if parallel \
	        --jobs "$N_JOBS" \
	        --results "${HOME}/parallel_dir" \
	        --joblog "${HOME}/parallel_dir/parallel.log" \
	        --timeout 300 \
	        ./CADD.sh ::: "${input_vcfs_path[@]}"; then

			echo "All CADD jobs were successful"
	else

			echo "Some CADD jobs failed"

	fi


	echo "Collecting results"


	mkdir -p "${HOME}/out/cadd_scores/"

	for ((v=0;v< ${#input_vcfs_path[@]};++v)); do

		rm "${input_vcfs_path[$v]}"

		mv "${HOME}/in/input_vcfs/${v}" "${HOME}/out/cadd_scores/${v}"

	done



	mkdir -p "${HOME}/out/cadd_log/"

	echo "==== Summary ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

	cat "${HOME}/parallel_dir/parallel.log"  |\
	awk -F"\t" 'BEGIN{t=0;f=0;s=0}NR>1{t+=$4}NR>1{if($7==0) ++s ; else ++f}END{print "Pass/Fail: " s"/"f ; printf "Avergage time: %.2fmin\n", t/(NR-1)/60 }' >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

	cat "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

	echo "==== Parallel ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

	cat "${HOME}/parallel_dir/parallel.log" >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

	echo "==== Logs ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

	find "${HOME}/parallel_dir/" -name std* -exec cat {} + >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"


	echo "Uploading results"

	dx-upload-all-outputs
}








```bash
parallel \

	dx cat ${vcf_file_id} |\
	gunzip - |\
	awk -F'\t' '/^#/{gsub(/^chrM/,"MT",$1); gsub(/^chr/,"",$1); NF=5; print}' OFS="\t" |\
	gzip > "${cadd_working_dir}/input_vcfs/${input_vcf_name}"

}


	${cadd_vcfs_path[$v]}="${cadd_working_dir}/input_vcfs/${input_vcf_file}"

```


A list of these files can then be passed to parallel as we have shown above.

The output needs to be relocated to a new location under `${HOME}/out/`, each in its own directory, with numeric dir names to reflect the output array.


```bash
mv ${HOME}/in/input_vcfs ${HOME}/out/cadd_scores

for ((v=0;v<${#input_vcfs_path[@]};++v)); do

	if [[ -f "${input_vcfs_path[$v]}" ]]; then
		mv "${input_vcfs_path[$v]}" "${HOME}/out/cadd_scores/${v}/"
	fi

done
```

The outputs are ready for upload with `dx-upload-all-outputs`



Moreover, instead of downloading single directories, a more convenient approach to steamline the downloads (e.g., inside a script) will be to download the full `data` directory including prescored variants and annotations as follows:


```bash
dx download "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data" \
--recursive \
--no-progress \
--lightweight \
-o "${cadd_working_dir}/" 
```
