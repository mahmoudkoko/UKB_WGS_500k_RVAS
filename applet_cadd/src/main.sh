#!/bin/bash

set -e -x -o pipefail



#########





########

mv ${HOME}/conda/Miniforge3-Linux-x86_64 ${HOME}/conda/Miniforge3-Linux-x86_64.sh

bash ${HOME}/conda/Miniforge3-Linux-x86_64.sh -u -b -p ${HOME}/conda 2>&1 > /dev/null

cat ${HOME}/conda/apptainer-install-unprivileged | bash -s - ${HOME}/conda/  2>&1 > /dev/null


export PATH=${HOME}/conda/bin:${PATH}

conda config --set channel_priority strict
conda install -p ${HOME}/conda/ -y -c conda-forge -c bioconda 'snakemake=8' 2>&1 > /dev/null


#########


main() {


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




get_cadd_data_file "envs/CADD_v1_7.sif"



	# Move to cadd dir

	cd "${HOME}/cadd_dir"

	echo "Downloading annotations. This takes > 1hr"

    # Download bundled annotations to target dur

	dx cat "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/GRCh38_v1.7.tar.gz" |\
	gunzip |\
	tar -xf - -C ./data/annotations/


	dx download --no-progress -o ./data/prescored/GRCh38_v1.7/no_anno/ \
#	"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/whole_genome_SNVs.tsv.gz" \
#	"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/whole_genome_SNVs.tsv.gz.tbi" \
	"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/gnomad.genomes.r4.0.indel.tsv.gz" \
	"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/gnomad.genomes.r4.0.indel.tsv.gz.tbi" 


	dx download --no-progress -o ./envs/ \
	"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/CADD_v1_7.sif" 

	echo "Downloading Input VCFs"

	# Download all inputs

	dx-download-all-inputs --parallel


export CADD_DATA_DIR_REMOTE="/Resources/cadd_v1_7_data"


mkdir -p "${HOME}/parallel"


mapfile -t cadd_files_list < <(dx cat "${DX_PROJECT_CONTEXT_ID}:${CADD_DATA_DIR_REMOTE}/CADD_v1_7_resources_list.txt" | sort | uniq | shuf)


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
