###################
# Utility functions
###################


# Function to print STDERR message with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}



# Function to safely add directories to cleanup list
track_temp_dirs() {
    local dir="$1"
    GLOBAL_TEMP_DIRS+=("$dir")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Tracking temp directory: $dir" >&2
}



progress_monitor_fx() {

local total_chunks="$1"
local processed_chunks=0
local successful_chunks=0
local timedout_chunks=0
local average_time=0

while [[ $processed_chunks -lt $total_chunks ]] ; do


    if [[ -f "${RUNTIME_DIR}/LOG/${PAR_LOG}" ]] ; then
    
        processed_chunks=$(awk 'END{print NR-1}' "${RUNTIME_DIR}/LOG/${PAR_LOG}" 2> /dev/null || echo 0 )
        successful_chunks=$(awk 'BEGIN{success=0}$7==0{++success}END{print success}' "${RUNTIME_DIR}/LOG/${PAR_LOG}" 2> /dev/null || echo 0 )
        timedout_chunks=$(awk 'BEGIN{timedout=0}$7==-1{++timedout}END{print timedout}' "${RUNTIME_DIR}/LOG/${PAR_LOG}" 2> /dev/null || echo 0 )
        average_time=$(awk 'NR>1{proc_time += $4 }END{avg_time=proc_time/(NR-1)/60; printf("%.1f\n", avg_time) }' "${RUNTIME_DIR}/LOG/${PAR_LOG}" 2> /dev/null || echo 0 )
        
        log_message "INFO: Successful/Processed/Total files: $successful_chunks/$processed_chunks/$total_chunks (average: $average_time min - timed-out: $timedout_chunks)"

    fi

    # Print progress every 2 mins
    sleep 120

done
}


get_validation_results() {

    local vep_log_dx_id=""
    local vep_input_files=()

    local status_vcf_attempt="NA"
    local status_vcf_valid=()
    local status_vcf_empty=()
    local status_vcf_skipped=()
    local status_vcf_failed=()
    local status_vcf_rejected=()

    local status_warn_msgs=()
    local status_error_msgs=()



    if ! status_vcf_attempt=$(awk 'END{print NR-1}' "${RUNTIME_DIR}/LOG/${VAL_LOG}"); then

        return 1

    elif ! mapfile -t status_vcf_rejected < <(find "${RUNTIME_DIR}/LOG" -name stderr -exec tail {} + | grep -h "REJECTED: " | sed 's/.*file-/file-/'); then

        return 1

    elif ! mapfile -t status_vcf_failed < <(find "${RUNTIME_DIR}/LOG" -name stderr -exec tail {} + | grep -h "FAILED: " | sed 's/.*file-/file-/'); then

        return 1

    elif ! mapfile -t status_vcf_skipped < <(find "${RUNTIME_DIR}/LOG" -name stderr -exec tail {} + | grep -h "SKIPPED: " | sed 's/.*file-/file-/'); then

        return 1

    elif ! mapfile -t status_vcf_empty < <(find "${RUNTIME_DIR}/LOG" -name stderr -exec tail {} + | grep -h "EMPTY: " | sed 's/.*file-/file-/'); then

        return 1

    elif ! mapfile -t status_vcf_valid < <(find "${RUNTIME_DIR}/LOG" -name stderr -exec tail {} + | grep -h "VALID: " | sed 's/.*file-/file-/'); then

        return 1

    elif [[ "${#status_vcf_valid[@]}" == 0 && "${#status_vcf_empty[@]}" == 0 && "${#status_vcf_skipped[@]}" == 0 ]];then

        log_message "ERROR: All inputs are either invalid or failed - exiting"
        return 1

    elif ! mapfile -t vep_input_files < <(find "${RUNTIME_DIR}/LOG" -name stdout -exec cat {} +); then

        return 1

    elif ! cat > ${RUNTIME_DIR}/LOG/${RUNTIME_LOG} <<EOL
=== Execution Context ===
Job ID: ${DX_JOB_ID:-'Not available'}
Project ID: ${DX_PROJECT_CONTEXT_ID:-'Not available'}
Applet ID: ${DX_APPLET_ID:-'Not available'}
Applet Name: ${DX_EXECUTABLE_NAME:-'Not available'}
Cores: ${DX_CPUS:-'Not available'}
Memory: ${DX_MEM:-'Not available'}
Processes: ${N_JOBS:-'Not available'}
Directory: ${DX_OUTPUT_DIR:-'Not available'}
Dependency: ${BCFTOOLS_VERSION:-'Not available'}
=== Inputs ===
File name: ${VCF_LIST_NAME:-'Not available'}
Directory: ${VCF_LIST_DIR:-'Not available'}
File hash: ${VCF_LIST_HASH:-'Not available'}
Valid inputs: $(( ${#status_vcf_valid[@]} + ${#status_vcf_empty[@]} + ${#status_vcf_skipped[@]} ))
Invalid input lines: ${#status_vcf_rejected[@]}
Failed validation: ${#status_vcf_failed[@]}
=== Invalid inputs ===
$(printf "%s\n" ${status_vcf_rejected[@]})
=== Failed validation ===
$(printf "%s\n" ${status_vcf_failed[@]})
=== Skipped VCFs ===
$(printf "%s\n" ${status_vcf_skipped[@]})
=== Empty VCFs ===
$(printf "%s\n" ${status_vcf_empty[@]})
EOL
    then

        return 1
    
    else

        log_message "INFO: Finished reading input list"
        log_message "INFO: ---- Validation Summary -----"
        log_message "INFO: Attempted: ${status_vcf_attempt}"
        log_message "INFO: Rejected: ${#status_vcf_rejected[@]}"
        log_message "INFO: Failed: ${#status_vcf_failed[@]}"
        log_message "INFO: Skipped: ${#status_vcf_skipped[@]}"
        log_message "INFO: Empty: ${#status_vcf_empty[@]}"
        log_message "INFO: Has variants: ${#status_vcf_valid[@]}"
    fi


    # Final return
    if [[ ${#status_vcf_valid[@]} -gt 0 ]]; then 
        printf "%s\n" ${status_vcf_valid[@]}
    else
        echo "NA"
    fi
}



create_session_log() {

    local vep_log_dx_id=""
    local status_vcf_attempt="NA"
    local status_vcf_done=()
    local status_vcf_failed=()
    local status_warn_msgs=()
    local status_error_msgs=()



    if ! status_vcf_attempt=$(awk 'END{print NR-1}' "${RUNTIME_DIR}/LOG/${PAR_LOG}"); then

        return 1

    elif ! mapfile -t status_vcf_failed < <(find "${RUNTIME_DIR}/LOG" -name stderr -exec tail {} + | grep -h "FAILED: " | sed 's/.*file-/file-/'); then

        return 1

    elif ! mapfile -t status_vcf_done < <(find "${RUNTIME_DIR}/LOG" -name stderr -exec tail {} + | grep -h "DONE: " | sed 's/.*file-/file-/'); then

        return 1
    
    elif ! mapfile -t status_warn_msgs < <(find "${RUNTIME_DIR}/LOG" -name stderr -exec grep -h -i "WARN" {} + ); then

        return 1
    
    elif ! mapfile -t status_error_msgs < <(find "${RUNTIME_DIR}/LOG" -name stderr -exec grep -h -i -e "ERROR" -e "FAIL" {} + ); then

        return 1

    elif ! cat >> ${RUNTIME_DIR}/LOG/${RUNTIME_LOG} <<EOL
=== Failed VCFs ===
$(printf "%s\n" ${status_vcf_failed[@]})
=== Successfully annotated VCFs ===
$(printf "%s\n" ${status_vcf_done[@]})
=== Warnings ===
$(printf "%s\n" "${status_warn_msgs[@]}")
=== Errors ===
$(printf "%s\n" "${status_error_msgs[@]}")
=== Complete logs ===
EOL

    then

        return 1

    elif ! find "${RUNTIME_DIR}/LOG" -name stderr -exec cat {} + 2> /dev/null >> "${RUNTIME_DIR}/LOG/${RUNTIME_LOG}"; then

        return 1

    elif ! vep_log_dx_id=$(dx upload "${RUNTIME_DIR}/LOG/${RUNTIME_LOG}" -p --path "logs/${RUNTIME_LOG}" --brief); then

        return 1

    elif ! dx-jobutil-add-output vep_log "${vep_log_dx_id}" --class=array:file; then

        return 1

    else

        log_message "INFO: Finished annotating vcf files"
        log_message "INFO: ---- Annotaiton Summary -----"
        log_message "INFO: Successful: ${#status_vcf_done[@]}"
        log_message "INFO: Failed: ${#status_vcf_failed[@]}"

    fi


    
}


    cleanup_and_exit() {

        local exit_code=$?

        # print all error logs to screen if non-zero
        if [[ $exit_code -gt 0 ]]; then

            log_message "INFO: Run completed with error (last exit code: $exit_code)"
         
        fi

        # Kill any remaining parallel jobs
        pkill -P $$ 2>/dev/null || true


        # Delete runtime dir
        rm -rf "${RUNTIME_DIR}/" 2>/dev/null || true

    }

