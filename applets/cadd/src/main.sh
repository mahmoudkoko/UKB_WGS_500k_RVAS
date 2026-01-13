#!/bin/bash

set -euo pipefail
set +x

main() {

# Variable declarations
local CADD_DATA_PROJECT
local CADD_DATA_DIR
local CADD_JOBS
local cadd_working_dir
local input_vcfs_list=() 
local v
local input_file
local tsv_file
local job_num
local log_file
local retry_num

# Define CADD working directory
cadd_working_dir="${HOME}/CADD"

# Install apptainer
if ! sudo apt-get install -y /usr/local/assets/apptainer_1.4.1_amd64.deb; then
	echo "ERROR: Failed to install apptainer" >&2
	exit 1
# Source utility scripts
elif ! source /usr/local/scripts/utilities.sh; then
	echo "ERROR: Failed to source utilities.sh" >&2
	exit 1
# Create working directory
elif ! mkdir -p "${cadd_working_dir}/input_vcfs" "${cadd_working_dir}/parallel_dir"; then
	log_message "ERROR: Failed to create CADD working directory"
	exit 1
elif ! get_input_param; then
	log_message "ERROR: Failed to get input parameters (CADD_DATA_PROJECT, CADD_DATA_DIR, CADD_JOBS, CADD_TIMEOUT)"
	exit 1
elif ! prepare_cadd_vcfs > "${cadd_working_dir}/parallel_dir/input_vcfs.txt"; then
	log_message "ERROR: Failed to prepare CADD input VCFs"
	exit 1
elif ! mapfile -t input_vcfs_list < "${cadd_working_dir}/parallel_dir/input_vcfs.txt"; then
	log_message "ERROR: Failed to read input VCF filenames into array"
	exit 1
elif [[ ${#input_vcfs_list[@]} -eq 0 ]]; then
	log_message "ERROR: No input VCF files found for CADD processing"
	exit 1
elif ! dx ls --brief "$CADD_DATA_PROJECT:$CADD_DATA_DIR" &> /dev/null; then
	log_message "ERROR: CADD data directory $CADD_DATA_DIR not found in project $CADD_DATA_PROJECT"
	exit 1
elif ! dx_parallel_download \
	--dx_project "${CADD_DATA_PROJECT}" \
	--dx_folder "${CADD_DATA_DIR}" \
	--strip_prefix "${CADD_DATA_DIR}" \
	--target_dir "${cadd_working_dir}"; then
	log_message "ERROR: Failed to download CADD data directory"
	exit 1
elif ! chown -R dnanexus:dnanexus "${cadd_working_dir}"; then
	log_message "ERROR: Failed to change ownership of CADD working directory"
	exit 1
elif ! runuser -u dnanexus -- singularity exec \
	--writable-tmpfs \
	--bind "${cadd_working_dir}"/annotations:/opt/CADD/data/annotations \
	--bind "${cadd_working_dir}"/prescored:/opt/CADD/data/prescored \
	--bind "${cadd_working_dir}"/containers:/opt/CADD/src/sif \
	"${cadd_working_dir}"/containers/CADD_scripts_v1_7.sif \
	bash -c 'set -e; run_cadd -c2 /opt/CADD/test/input.vcf.gz && test -s /opt/CADD/test/input.tsv.gz'; then
	log_message "ERROR: Test run of CADD-scripts from singularity container failed"
	exit 1
else
	log_message "INFO: CADD environment setup and test run completed successfully"
fi


# Run CADD

	log_message "INFO: Running CADD scoring with $CADD_JOBS parallel jobs"

if runuser -u dnanexus -- singularity exec \
	--writable-tmpfs \
	--bind "${cadd_working_dir}"/parallel_dir:/opt/CADD/parallel_dir \
	--bind "${cadd_working_dir}"/input_vcfs:/opt/CADD/input_vcfs \
	--bind "${cadd_working_dir}"/annotations:/opt/CADD/data/annotations \
	--bind "${cadd_working_dir}"/prescored:/opt/CADD/data/prescored \
	--bind "${cadd_working_dir}"/containers:/opt/CADD/src/sif \
	"${cadd_working_dir}"/containers/CADD_scripts_v1_7.sif \
	parallel \
		--jobs "$CADD_JOBS" \
		--timeout "$CADD_TIMEOUT" \
		--retries 2 \
		--results /opt/CADD/parallel_dir \
		--joblog /opt/CADD/parallel_dir/parallel.log \
		run_cadd -c2 /opt/CADD/input_vcfs/{} \
		:::: /opt/CADD/parallel_dir/input_vcfs.txt; then

	log_message "INFO: CADD scoring run completed"
else
	log_message "WARNING: Error(s) occurred during CADD scoring run"
fi


# Generate summary statistics

if [[ -f "${cadd_working_dir}/parallel_dir/parallel.log" ]]; then

	log_message "INFO: Summary of CADD jobs:"
	awk -F"\t" 'BEGIN{t=0;f=0;s=0}NR>1{t+=$4}NR>1{if($7==0) ++s ; else ++f}END{print "Pass/Fail: " s"/"f ; printf "Average time: %.2fmin\n", t/(NR-1)/60 }' "${cadd_working_dir}/parallel_dir/parallel.log"

else
	log_message "ERROR: parallel.log file not found"
	exit 1
fi

# Generate CADD summary log
log_message "INFO: Generating CADD summary log"

mkdir -p "${HOME}/out/cadd_summary_log/"

{
	echo "CADD Parallel Jobs Summary"
	echo "=========================="
	echo ""
	awk -F"\t" 'BEGIN {
		printf "%-8s %-40s %-12s %-10s %-10s\n", "Job", "Filename", "Runtime(min)", "Status", "ExitCode"
		printf "%-8s %-40s %-12s %-10s %-10s\n", "--------", "----------------------------------------", "------------", "----------", "----------"
	}
	NR==1 {next}
	{
		# Job number is in column 1
		job_num = $1
		# Extract filename from field 9 (or last field with $NF)
		arg = $9
		# Remove leading/trailing whitespace
		gsub(/^[ \t]+|[ \t]+$/, "", arg)
		# Extract just the filename from the path
		split(arg, path, "/")
		filename = path[length(path)]
		# Calculate runtime in minutes (column 4)
		runtime = $4 / 60
		# Determine pass/fail status (column 7)
		status = ($7 == 0) ? "PASS" : "FAIL"
		# Exit code is in column 7
		exit_code = $7
		# Print formatted table row
		printf "%-8s %-40s %-12.2f %-10s %-10d\n", job_num, filename, runtime, status, exit_code
	}' "${cadd_working_dir}/parallel_dir/parallel.log"
} > "${HOME}/out/cadd_summary_log/CADD-${DX_JOB_ID}.log"


# Collect results: move TSV files and logs to output directories
log_message "INFO: Collecting results"

# Read input VCF filenames into an array
for ((v=0; v < ${#input_vcfs_list[@]}; ++v)); do
	# Create output subdirectories

	# Get the input filename without path
	input_file="${input_vcfs_list[$v]}"
	tsv_file="${cadd_working_dir}/input_vcfs/${input_file%.vcf.gz}.tsv.gz"
	log_file="${HOME}/out/cadd_logs/${v}/${input_file%.vcf.gz}.log"

	if [[ -f "$tsv_file" ]]; then

		# Move CADD TSV output to scores directory
		mkdir -p "${HOME}/out/cadd_scores/${v}" "${HOME}/out/cadd_logs/${v}"
		mv "$tsv_file" "${HOME}/out/cadd_scores/${v}/"
	
	else
		log_message "WARNING: TSV file not found: ${tsv_file}"
	fi

	# Concatenate stdout and stderr into a single log file named after the input
	# Parallel results are stored by retry attempt number (1 for first attempt, 2 for retry, etc.)
	# Directory structure: parallel_dir/{retry_num}/_path_with_underscores/stdout


	# Try to find the log in retry directories (1 for first attempt, 2+ for retries)
	for retry_num in {1..2}; do
		if [[ -f "${cadd_working_dir}/parallel_dir/${retry_num}/${input_file}/stderr" ]]; then
			{
				echo "CADD Log ${retry_num} for ${input_file}"
				echo "================================"
				echo ""
				echo "==== STDOUT ===="
					cat "${cadd_working_dir}/parallel_dir/${retry_num}/${input_file}/stdout"
				echo ""
				echo "==== STDERR ===="
					cat "${cadd_working_dir}/parallel_dir/${retry_num}/${input_file}/stderr"
			} >> "$log_file"
		fi
	done

	if [[ ! -f "$log_file" ]]; then
		echo "WARNING: No parallel output found for ${input_file}" > "$log_file"
		log_message "WARNING: No parallel output found for ${input_file}"
	fi

done




log_message "INFO: Uploading results..."

dx-upload-all-outputs

echo "Summary:"
echo "========"

cat "${HOME}/out/cadd_summary_log/CADD-${DX_JOB_ID}.log"

}