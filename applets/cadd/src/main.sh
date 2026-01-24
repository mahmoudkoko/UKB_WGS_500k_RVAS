#!/bin/bash

set -euo pipefail
set +x

main() {

# Install apptainer
if ! apt-get install -y /usr/local/assets/apptainer.deb; then
	echo "ERROR: Failed to install apptainer" >&2
	exit 1
# Source utilities scripts
elif ! source /usr/local/scripts/utilities.sh; then
	echo "ERROR: Failed to source utilities.sh" >&2
	exit 1
elif ! {
# Export utility functions to be used by 'runuser'
export -f log_message
export -f get_input_param
export -f process_vcf_file
export -f prepare_cadd_vcfs
export -f dx_download_file
export -f dx_parallel_download
export -f deploy_cadd_locally
export -f run_cadd_on_input_vcfs
export -f collect_cadd_output_files
}; then

	echo "ERROR: Failed to export utility functions" >&2
	exit 1

# Validate input parameters
elif ! get_input_param; then
	log_message "ERROR: Failed to get input parameters"
	exit 1
fi




# Initialize CADD working directory and parameters
if ! runuser -u dnanexus --  bash -c 'deploy_cadd_locally'; then
	echo "ERROR: Failed to deploy CADD locally" >&2
	exit 1
else
	log_message "INFO: CADD deployed locally. Starting VCF processing..."
fi


# Run CADD
if ! runuser -u dnanexus -- bash -c 'run_cadd_on_input_vcfs'; then
	log_message "WARNING: Error(s) occurred during CADD scoring"
else
	log_message "INFO: CADD scoring completed"
fi


# Collect results: move TSV files and logs to output directories
if ! runuser -u dnanexus -- bash -c 'collect_cadd_output_files'; then
	log_message "WARNING: Failed to collect CADD TSV and log files"
else
	log_message "INFO: Available CADD TSV and log files collected to ${HOME}/out/"
fi

# Upload results
if ! dx-upload-all-outputs; then

	log_message "WARNING: Failed to upload results"

else

	log_message "INFO: CADD TSV and log files uploaded successfully"

	echo "Summary:"
	echo "========"
	awk -F"\t" 'BEGIN{t=0;f=0;s=0}NR>1{t+=$4}NR>1{if($7==0) ++s ; else ++f}END{print "Pass/Fail: " s"/"f ; printf "Average time: %.2fmin\n", t/(NR-1)/60 }' "${CADD_WD}/parallel_dir/parallel.log"

fi

}