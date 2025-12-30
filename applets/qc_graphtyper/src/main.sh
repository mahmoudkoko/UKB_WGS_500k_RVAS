#!/bin/bash

set -euo pipefail
set +x


source /usr/scripts/export_global_vars.sh
source /usr/scripts/validate_input.sh
source /usr/scripts/process_graphtyper_vcf_block.sh
source /usr/scripts/check_ongoing_applet_runs.sh
source /usr/scripts/bcftools_filters.sh
source /usr/scripts/utilities.sh


##################
# Main entry point
##################

main() {

    local val_log_dx_id=""
    local qc_log_dx_id=""

    local all_input_files=()
    local qc_input_files=()

    local status_empty=()
    local status_skipped=()
    local status_valid=()
    local status_invalid=()
    local status_failed=()

    local status_qc_done=()
    local status_qc_empty=()
    local status_qc_failed=()



    # Export global vars
    export_global_vars

    # Export the functions used within the main entry point below for parallel runs
    
    export -f validate_input_vcf_files
    export -f process_graphtyper_vcf_block
#    export -f bcf_split_multi
    export -f bcf_filter_gt
    export -f log_message


    # Set global cleanup trap
    trap 'clean_temp_dirs' EXIT INT TERM RETURN




    # Create log directory
    mkdir -p "$RUNTIME_DIR/IN" "$RUNTIME_DIR/OUT" "$RUNTIME_DIR/LOG"

    # Track temp directory
    track_temp_dirs "$RUNTIME_DIR/IN"
    track_temp_dirs "$RUNTIME_DIR/OUT"
    track_temp_dirs "$RUNTIME_DIR/LOG"
    track_temp_dirs "$RUNTIME_DIR"


    # Validate context
    if ! validate_execution_context ; then

        return 1

    elif ! check_ongoing_applet_runs ; then

        return 1

    elif ! mapfile -t all_input_files < <(dx cat "${DX_PROJECT_CONTEXT_ID}:${VCF_LIST_HASH}") ; then

        log_message "ERROR: Failed to read the VCF list file - exiting"
        return 1

    fi


    ###########
    # Read VCFs 
    ###########


    if ! parallel \
        --jobs "$N_JOBS" \
        --results "${RUNTIME_DIR}/IN" \
        --joblog "${RUNTIME_DIR}/LOG/validate_input_vcf_files.log" \
        --timeout 300 \
        validate_input_vcf_files ::: "${all_input_files[@]}"; then

        log_message "ERROR: Failed to validate the VCF list file - exiting"
        return 1

    elif ! mapfile -t status_invalid < <(find "${RUNTIME_DIR}/IN" -name stderr -exec tail {} + | grep -h "INVALID: " | sed 's/.*file-/file-/'); then

        log_message "ERROR: Failed to map the list of invalid input lines - exiting"
        return 1

    elif ! mapfile -t status_failed < <(find "${RUNTIME_DIR}/IN" -name stderr -exec tail {} + | grep -h "FAILED: " | sed 's/.*file-/file-/'); then

        log_message "ERROR: Failed to map the list of failed input files - exiting"
        return 1

    elif ! mapfile -t status_skipped < <(find "${RUNTIME_DIR}/IN" -name stderr -exec tail {} + | grep -h "SKIPPED: " | sed 's/.*file-/file-/' ); then

        log_message "ERROR: Failed to map the list of skipped input files - exiting"
        return 1

    elif ! mapfile -t status_empty < <(find "${RUNTIME_DIR}/IN" -name stderr -exec tail {} + | grep -h "EMPTY: " | sed 's/.*file-/file-/' ); then

        log_message "ERROR: Failed to map the list of empty input files - exiting"
        return 1

    elif ! mapfile -t status_valid < <(find "${RUNTIME_DIR}/IN" -name stderr -exec tail {} + | grep -h "VALID: " | sed 's/.*file-/file-/' ); then

        log_message "ERROR: Failed to map the list of failed input files - exiting"
        return 1

    elif [[ "${#status_valid[@]}" == 0 && "${#status_empty[@]}" == 0 && "${#status_skipped[@]}" == 0 ]];then

        log_message "ERROR: All inputs are either invalid or failed - exiting"
        return 1

    elif ! mapfile -t qc_input_files < <(find "${RUNTIME_DIR}/IN" -name stdout -exec cat {} +); then

        log_message "ERROR: Failed to map the list of validated input hashes - exiting"
        return 1

    else

        log_message "INFO: Finished reading input list"
        log_message "INFO: ---- Validation Summary -----"
        log_message "INFO: Found ${#all_input_files[@]} lines"
        log_message "INFO: Rejected: ${#status_invalid[@]}"
        log_message "INFO: Failed: ${#status_failed[@]}"
        log_message "INFO: Skipped: ${#status_skipped[@]}"
        log_message "INFO: Empty: ${#status_empty[@]}"
        log_message "INFO: Valid: ${#status_valid[@]}"

    fi


    ################
    # Log validation
    ################

        log_message "INFO: Writing the validation runtime log"

    cat > ${RUNTIME_DIR}/LOG/${VAL_LOG_FILE} <<EOL
=== Execution Context ===
Job ID: ${DX_JOB_ID:-'Not available'}
Project ID: ${DX_PROJECT_CONTEXT_ID:-'Not available'}
Applet ID: ${DX_APPLET_ID:-'Not available'}"
Applet Name: ${DX_EXECUTABLE_NAME:-'Not available'}
Cores: ${DX_CPUS:-'Not available'}
Memory: ${DX_MEM:-'Not available'}
Processes: ${N_JOBS:-'Not available'}
Directory: ${DX_OUTPUT_DIR:-'Not available'}
Dependency: $(bcftools --version | head -n1)
=== Inputs ===
Directory: ${VCF_LIST_DIR:-'Not available'}
File name: ${VCF_LIST_NAME:-'Not available'}
File hash: ${VCF_LIST_HASH:-'Not available'}
=== Summary ===
Valid: $(( ${#status_valid[@]} + ${#status_empty[@]} + ${#status_skipped[@]} ))
Failed: ${#status_failed[@]}
Invalid: ${#status_invalid[@]}
=== Invalid inputs ===
$(printf "%s\n" ${status_invalid[@]})
=== Failed VCFs ===
$(printf "%s\n" ${status_failed[@]})
=== Skipped VCFs ===
$(printf "%s\n" ${status_skipped[@]})
=== Empty VCFs ===
$(printf "%s\n" ${status_empty[@]})
=== Require QC ===
$(printf "%s\n" ${status_valid[@]})
=== Runtime logs ===
EOL




    if [[ -f "${RUNTIME_DIR}/LOG/validate_input_vcf_files.log" ]]; then

        log_message "INFO: Located validation parallel log"

        if cat "${RUNTIME_DIR}/LOG/validate_input_vcf_files.log" >> "${RUNTIME_DIR}/LOG/${VAL_LOG_FILE}" ; then
        
            log_message "INFO: Copied validation parallel log"

        else

            log_message "ERROR: Failed to locate validation parallel log file"
            return 1

        fi


        if find "${RUNTIME_DIR}/IN" -name stderr -exec cat {} + 2> /dev/null >> "${RUNTIME_DIR}/LOG/${VAL_LOG_FILE}"; then
           
            log_message "INFO: Copied validation stderr logs"

        else

            log_message "ERROR: Failed to locate validation stderr files"
            return 1

        fi

    else

        log_message "ERROR: Could not locate validation parallel log"
        return 1

    fi



    # Upload

    if val_log_dx_id=$(dx upload "${RUNTIME_DIR}/LOG/${VAL_LOG_FILE}" -p --path "logs/${VAL_LOG_FILE}" --brief); then

        log_message "INFO: Uploaded validation log file"        
    
    else        
    
        log_message "ERROR: Failed to upload validation log file"
        return 1
    fi
    


    # Add log to job output list
    if dx-jobutil-add-output qc_log_files "${val_log_dx_id}" --class=array:file; then

        log_message "INFO: Registered uploaded validation log file"        

    else

        log_message "ERROR: Failed to add validation log to applet's record of final outputs"
        return 1

    fi



    ##############
    # Process VCFs 
    ##############


    if [[ ${#status_valid[@]} -eq 0 ]] ; then

        log_message "INFO: No valid files with variants. Skipping QC"


    elif [[ ${#status_valid[@]} -gt 0 ]] && [[ $DX_MEM -lt $JOB_MEM ]] ; then
        
        log_message "INFO: Instance memory of $DX_MEM is lower than input limit of ${JOB_MEM}GB. Skipping QC"

        status_qc_failed=${qc_input_files[@]}

    else

    ##########
    # START QC
    ##########

        log_message "INFO: Proceeding to QC of valid files (parallel jobs: $N_JOBS)"

        ###################################################

        if parallel \
            --jobs "$N_JOBS" \
            --results "${RUNTIME_DIR}/OUT" \
            --joblog "${RUNTIME_DIR}/LOG/process_graphtyper_vcf_block.log" \
            --timeout 15000 \
            process_graphtyper_vcf_block ::: "${qc_input_files[@]}"; then

            log_message "INFO: Finished QC of valid files"

        else
            log_message "ERROR: Failed to run QC"
        fi




        if mapfile -t status_qc_failed < <(find "${RUNTIME_DIR}/OUT" -name stderr -exec tail {} + | grep -h "FAILED: " | sed 's/.*file-/file-/'); then

            log_message "INFO: Finished scanning for files failing qc"

        else

            log_message "ERROR: Failed to map the list of failed vcfs - exiting"
            return 1

        fi



        if mapfile -t status_qc_empty < <(find "${RUNTIME_DIR}/OUT" -name stderr -exec tail {} + | grep -h "EMPTY: " | sed 's/.*file-/file-/'); then

            log_message "INFO: Finished scanning for files without variants after qc"

        else

            log_message "ERROR: Failed to map the list of empty vcfs after qc - exiting"
            return 1

        fi


        if mapfile -t status_qc_done < <(find "${RUNTIME_DIR}/OUT" -name stderr -exec tail {} + | grep -h "DONE: " | sed 's/.*file-/file-/'); then

            log_message "INFO: Finished scanning for correctly processed files"
        
        else

            log_message "ERROR: Failed to map the list of finished vcfs - exiting"
            return 1
        
        fi

        ###########################################

        log_message "INFO: ---- QC Summary -----"
        log_message "INFO: Successful: ${#status_qc_done[@]}"
        log_message "INFO: Empty: ${#status_qc_empty[@]}"
        log_message "INFO: Failed: ${#status_qc_failed[@]}"




    ################
    # Log processing
    ################



    cat > ${RUNTIME_DIR}/LOG/${QC_LOG_FILE} <<EOL
=== Summary ===
Total succesful or skipped: $(( ${#status_qc_done[@]} + ${#status_qc_empty[@]} + ${#status_empty[@]} + ${#status_skipped[@]} ))
Total failed or invalid: $(( ${#status_invalid[@]} + ${#status_failed[@]} + ${#status_qc_failed[@]} ))
=== Successful QC ===
$(printf "%s\n" ${status_qc_done[@]})
=== Empty after QC ===
$(printf "%s\n" ${status_qc_empty[@]})
=== Empty before QC ===
$(printf "%s\n" ${status_empty[@]})
=== Skipped ===
$(printf "%s\n" ${status_skipped[@]})
=== Failed during QC ===
$(printf "%s\n" ${status_qc_failed[@]})
=== Failed before QC ===
$(printf "%s\n" ${status_failed[@]})
=== Invalid inputs ===
$(printf "%s\n" ${status_invalid[@]})
=== QC logs ===
EOL





        if [[ -f "${RUNTIME_DIR}/LOG/process_graphtyper_vcf_block.log" ]]; then

            log_message "INFO: Located QC parallel log"


            if cat "${RUNTIME_DIR}/LOG/process_graphtyper_vcf_block.log" >> "${RUNTIME_DIR}/LOG/${QC_LOG_FILE}"; then

                log_message "INFO: Copied QC parallel log"

            else

                log_message "ERROR: Failed to locate QC log file"
                return 1

            fi



            if find "${RUNTIME_DIR}/OUT" -name stderr -exec cat {} + 2> /dev/null >> "${RUNTIME_DIR}/LOG/${QC_LOG_FILE}"; then

                log_message "INFO: Copied QC stderr logs"
            else

                log_message "ERROR: Failed to locate QC stderr files"
                return 1

            fi


        else

            log_message "ERROR: Could not locate QC parallel log"
            return 1

        fi


        # Upload

        if qc_log_dx_id=$(dx upload "${RUNTIME_DIR}/LOG/${QC_LOG_FILE}" -p --path "logs/${QC_LOG_FILE}" --brief); then

            log_message "INFO: Uploaded final summary file"

        else

            log_message "ERROR: Failed to upload final summary file"
            return 1

        fi





        # Add summary to output list

        if dx-jobutil-add-output qc_log_files "${qc_log_dx_id}" --class=array:file; then

            log_message "INFO: Registered uploaded summary file"        

        else

            log_message "ERROR: Failed to add final output summary and log to applet's record of final outputs"
            return 1

        fi


    ########
    # END QC
    ########
    fi



    ##########################################
    # Print all uploaded files & dir to stdout
    ##########################################

    echo "----- Final Outputs -----"
    dx ls logs



    ###########
    # Completed
    ###########

    log_message "INFO: QC completed successfully"

}