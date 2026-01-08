#!/bin/bash

set -euo pipefail
set +x



main() {


# Install apptainer
if ! sudo apt install -y /usr/local/assets/apptainer_1.4.1_amd64.deb; then
	echo "ERROR: Failed to install apptainer" >&2
	exit 1
# Source utility scripts
elif ! source /usr/local/scripts/utilities.sh; then
	echo "ERROR: Failed to source utilities.sh" >&2
	exit 1
# Create working directory
elif ! cadd_working_dir="${HOME}/CADD"; mkdir -p "${cadd_working_dir}/input_vcfs" "${cadd_working_dir}/parallel_dir" ; then
	log_message "ERROR: Failed to create CADD working directory"
	exit 1
fi

# Process input VCFs for CADD
log_message "INFO: Preparing input VCFs for CADD scoring"
if ! mapfile -t input_vcfs_path < <(prepare_cadd_vcfs \
	--output_dir "${cadd_working_dir}/input_vcfs" \
	--max_jobs 5); then
	log_message "ERROR: Failed to prepare CADD input VCFs"
	exit 1
fi

log_message "INFO: Successfully prepared ${#input_vcfs_path[@]} VCF files for CADD scoring"

# Write VCF paths to file for parallel to read
printf '%s\n' "${input_vcfs_path[@]}" > "${cadd_working_dir}/parallel_dir/input_vcfs.txt"

# Download CADD data directory in parallel
CADD_DATA=$(cat ${HOME}/job_input.json  | jq -r '.cadd_dir' || echo 1 )

log_message "INFO: Downloading CADD data directory $CADD_DATA"

if ! dx_parallel_download \
	--dx_project "$DX_PROJECT_CONTEXT_ID" \
	--dx_folder "$CADD_DATA" \
	--target_dir "${cadd_working_dir}/" \
	--max_jobs 5; then
	log_message "ERROR: Failed to download CADD data directory"
	exit 1
fi

# Run CADD in parallel
N_JOBS=$(cat ${HOME}/job_input.json  | jq -r '.cadd_jobs' || echo 1 )

log_message "INFO: Running CADD scoring with $N_JOBS parallel jobs"

if parallel \
	--jobs "$N_JOBS" \
	--results "${cadd_working_dir}/parallel_dir" \
	--joblog "${cadd_working_dir}/parallel_dir/parallel.log" \
	--timeout 3000 \
	singularity exec \
--bind ${cadd_working_dir}/parallel_dir:/opt/CADD/parallel_dir \
--bind ${cadd_working_dir}/input_vcfs:/opt/CADD/input_vcfs \
--bind ${cadd_working_dir}/cadd_v1_7_data/annotations:/opt/CADD/data/annotations \
--bind ${cadd_working_dir}/cadd_v1_7_data/prescored:/opt/CADD/data/prescored \
--bind ${cadd_working_dir}/cadd_v1_7_data/containers:/opt/CADD/src/sif \
${cadd_working_dir}/cadd_v1_7_data/containers/CADD_scripts_v1_7.sif \
 :::: "${cadd_working_dir}/parallel_dir/input_vcfs.txt"; then
	log_message "INFO: All CADD jobs completed successfully"
else
	log_message "WARNING: Some CADD jobs failed"
fi

log_message "INFO: Collecting results"

mkdir -p "${HOME}/out/cadd_scores/"

for ((v=0; v < ${#input_vcfs_path[@]}; ++v)); do
	mkdir -p "${HOME}/out/cadd_scores/${v}"

	# Remove input VCF file
	if [[ -f "${input_vcfs_path[$v]}" ]]; then
		rm "${input_vcfs_path[$v]}"
	fi

	# Move CADD results to output directory
	if [[ -d "${cadd_working_dir}/input_vcfs/${v}" ]]; then
		mv "${cadd_working_dir}/input_vcfs/${v}"/* "${HOME}/out/cadd_scores/${v}/"
	fi
done

mkdir -p "${HOME}/out/cadd_log/"

log_message "INFO: Generating summary log"
echo "==== Summary ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

cat "${cadd_working_dir}/parallel_dir/parallel.log" | \
	awk -F"\t" 'BEGIN{t=0;f=0;s=0}NR>1{t+=$4}NR>1{if($7==0) ++s ; else ++f}END{print "Pass/Fail: " s"/"f ; printf "Average time: %.2fmin\n", t/(NR-1)/60 }' >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

cat "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

echo "==== Parallel ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"
cat "${cadd_working_dir}/parallel_dir/parallel.log" >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

echo "==== Logs ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"
find "${cadd_working_dir}/parallel_dir/" -name 'std*' -exec cat {} + >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

log_message "INFO: Uploading results to DNAnexus"
dx-upload-all-outputs

log_message "INFO: CADD scoring pipeline completed successfully"
}


