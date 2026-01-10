#!/bin/bash

set -euo pipefail
set +x

main() {

# Variable declarations
local CADD_DATA_PROJECT
local CADD_DATA_DIR
local CADD_JOBS
local cadd_working_dir
local input_vcfs_path
local v
local input_file
local input_basename
local input_name
local tsv_file
local job_num
local log_file
local escaped_path

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
elif ! mkdir -p "${cadd_working_dir}/input_vcfs" "${cadd_working_dir}/parallel_dir" ; then
	log_message "ERROR: Failed to create CADD working directory"
	exit 1
fi

# Read inputs and set up environment
CADD_DATA_PROJECT=$(cat ${HOME}/job_input.json  | jq -r '.cadd_dir_project' || echo "null" )
CADD_DATA_DIR=$(cat ${HOME}/job_input.json  | jq -r '.cadd_dir_path' || echo "null" )
CADD_JOBS=$(cat ${HOME}/job_input.json  | jq -r '.cadd_jobs' || echo "null" )


if [[ "$CADD_DATA_PROJECT" == "null" || -z "$CADD_DATA_PROJECT" ]]; then
	log_message "WARNING: CADD data project not specified. Using current project $DX_PROJECT_CONTEXT_ID"
	CADD_DATA_PROJECT="$DX_PROJECT_CONTEXT_ID"
fi


if [[ "$CADD_DATA_DIR" == "null" || -z "$CADD_DATA_DIR" ]]; then
	log_message "WARNING: CADD data directory not specified. Using default /Resources/cadd_v1_7_data"
	CADD_DATA_DIR="/Resources/cadd_v1_7_data"
fi

if [[ "$CADD_JOBS" == "null" || -z "$CADD_JOBS" || "$CADD_JOBS" -le 0 ]]; then
	log_message "WARNING: Number of CADD parallel jobs not specified or invalid. Auto-calculated from available memory"
	CADD_JOBS=$(($(free -g | awk '/^Mem:/{print $2}') / 8))
	CADD_JOBS=$((CADD_JOBS > 0 ? CADD_JOBS : 1))
fi

# Process input VCFs for CADD: the function prepare_cadd_vcfs downloads and prepares the input VCFs (cuts first 5 cols); it returns a list of paths

log_message "INFO: Preparing input VCFs for CADD scoring"
if ! mapfile -t input_vcfs_path < <(prepare_cadd_vcfs); then
	log_message "ERROR: Failed to prepare CADD input VCFs"
	exit 1
fi

# Write VCF paths to file for parallel to read
printf '%s\n' "${input_vcfs_path[@]}" > "${cadd_working_dir}/parallel_dir/input_vcfs.txt"

# Check CADD data directory: it should exist in the specified DNAnexus project
# Download CADD data directory: the function dx_parallel_download downloads a DNAnexus folder in parallel

log_message "INFO: Downloading CADD data directory $CADD_DATA_PROJECT:$CADD_DATA_DIR"

if ! dx ls --brief "$CADD_DATA_PROJECT:$CADD_DATA_DIR" &> /dev/null; then
	log_message "ERROR: CADD data directory $CADD_DATA_DIR not found in project $CADD_DATA_PROJECT"
	exit 1
elif ! dx_parallel_download \
	--dx_project "${CADD_DATA_PROJECT}" \
	--dx_folder "${CADD_DATA_DIR}" \
	--strip_prefix "${CADD_DATA_DIR}" \
	--target_dir "${cadd_working_dir}"; then
	log_message "ERROR: Failed to download CADD data directory"
	exit 1
fi

# Run CADD

log_message "INFO: Running CADD scoring with $CADD_JOBS parallel jobs"

# Run parallel inside a single container (parallel jobs run within the same container)
# This approach has lower overhead - container starts once and all jobs run inside it

if singularity exec \
	--writable-tmpfs \
	--bind ${cadd_working_dir}/parallel_dir:/opt/CADD/parallel_dir \
	--bind ${cadd_working_dir}/input_vcfs:/opt/CADD/input_vcfs \
	--bind ${cadd_working_dir}/annotations:/opt/CADD/data/annotations \
	--bind ${cadd_working_dir}/prescored:/opt/CADD/data/prescored \
	--bind ${cadd_working_dir}/containers:/opt/CADD/src/sif \
	${cadd_working_dir}/containers/CADD_scripts_v1_7.sif \
	parallel \
		--jobs "$CADD_JOBS" \
		--results /opt/CADD/parallel_dir \
		--joblog /opt/CADD/parallel_dir/parallel.log \
		--timeout 3000 \
		run_cadd -c2 {} \
		:::: /opt/CADD/parallel_dir/input_vcfs.txt; then
		
	log_message "INFO: Summary of CADD jobs:"
	cat "${cadd_working_dir}/parallel_dir/parallel.log" | \
		awk -F"\t" 'BEGIN{t=0;f=0;s=0}NR>1{t+=$4}NR>1{if($7==0) ++s ; else ++f}END{print "Pass/Fail: " s"/"f ; printf "Average time: %.2fmin\n", t/(NR-1)/60 }'
else
	log_message "ERROR: Failed to run CADD-scripts from its singularity container"
	exit 1
fi

# Version 2: 
# Run parallel outside container (each job spawns a new Singularity container)
# This approach has higher overhead due to container startup for each job

# if parallel \
# 	--jobs "$CADD_JOBS" \
# 	--results "${cadd_working_dir}/parallel_dir" \
# 	--joblog "${cadd_working_dir}/parallel_dir/parallel.log" \
# 	--timeout 3000 \
# 	singularity exec \
# 		--writable-tmpfs \
# 		--bind ${cadd_working_dir}/parallel_dir:/opt/CADD/parallel_dir \
# 		--bind ${cadd_working_dir}/input_vcfs:/opt/CADD/input_vcfs \
# 		--bind ${cadd_working_dir}/annotations:/opt/CADD/data/annotations \
# 		--bind ${cadd_working_dir}/prescored:/opt/CADD/data/prescored \
# 		--bind ${cadd_working_dir}/containers:/opt/CADD/src/sif \
# 		${cadd_working_dir}/containers/CADD_scripts_v1_7.sif \
# 		run_cadd {} \
# 	:::: "${cadd_working_dir}/parallel_dir/input_vcfs.txt"; then
# 	log_message "INFO: All CADD jobs completed successfully"
# else
# 	log_message "WARNING: Some CADD jobs failed"
# fi

log_message "INFO: Collecting results"

for ((v=0; v < ${#input_vcfs_path[@]}; ++v)); do
	# Create output subdirectories
	mkdir -p "${HOME}/out/cadd_scores/${v}" "${HOME}/out/cadd_logs/${v}"

	# Get the input filename without path
	input_file="${input_vcfs_path[$v]}"
	input_basename=$(basename "$input_file")
	input_name="${input_basename%.vcf.gz}"

	# Move CADD TSV output to scores directory (example2.cadd.vcf.gz -> example2.cadd.tsv.gz)
	tsv_file="${cadd_working_dir}/input_vcfs/${input_name}.tsv.gz"
	if [[ -f "$tsv_file" ]]; then
		mv "$tsv_file" "${HOME}/out/cadd_scores/${v}/"
	else
		log_message "WARNING: TSV file not found: ${tsv_file}"
	fi

	# Concatenate stdout and stderr into a single log file named after the input
	# Parallel results are stored by job sequence number (v+1 since jobs start at 1)
	# Directory structure: parallel_dir/{job_num}/_path_with_underscores/stdout
	job_num=$((v + 1))
	log_file="${HOME}/out/cadd_logs/${v}/${input_name}.log"

	# Convert input path to parallel's escaped format (replace / with _)
	escaped_path=$(echo "$input_file" | sed 's/\//_/g')

	{
		echo "CADD Log for ${input_basename}"
		echo "================================"
		echo ""
		echo "==== STDOUT ===="
		if [[ -f "${cadd_working_dir}/parallel_dir/${job_num}/${escaped_path}/stdout" ]]; then
			cat "${cadd_working_dir}/parallel_dir/${job_num}/${escaped_path}/stdout"
		else
			echo "No stdout found for job ${job_num} at ${escaped_path}"
		fi
		echo ""
		echo "==== STDERR ===="
		if [[ -f "${cadd_working_dir}/parallel_dir/${job_num}/${escaped_path}/stderr" ]]; then
			cat "${cadd_working_dir}/parallel_dir/${job_num}/${escaped_path}/stderr"
		else
			echo "No stderr found for job ${job_num} at ${escaped_path}"
		fi
	} > "$log_file"

done


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


log_message "INFO: Uploading results..."

dx-upload-all-outputs

echo "Summary:"
echo "========"

cat "${HOME}/out/cadd_summary_log/CADD-${DX_JOB_ID}.log"

}


