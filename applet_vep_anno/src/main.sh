#!/bin/bash

set -euo pipefail
set +x



main() {


    source /usr/scripts/export_global_vars.sh
    source /usr/scripts/check_ongoing_applet_runs.sh
    source /usr/scripts/utilities.sh
    source /usr/scripts/validate_input.sh
    source /usr/scripts/stage_vep.sh
    source /usr/scripts/process_vep_vcf_block.sh
    source /usr/scripts/annotate_vep.sh


    ######
    # Apps
    ######


    local tabix_=$(which tabix || echo "not found")
    local bgzip_=$(which bgzip || echo "not found")
    local bcftools_=$(which bcftools || echo "not found")
    local parallel_=$(which parallel || echo "not found")

    if [[ $tabix_ =~ "not found" || $bgzip_ =~ "not found" || $bcftools_ =~ "not found" || $parallel_ =~ "not found"  ]]; then
        return 1
    fi
   




    ##################
    # Prep environment
    ##################

    local vep_log_dx_id=""
    local vep_out_dx_ids=()

    local vep_input_files=()
    local vep_valid_files=()



    if ! export_global_vars; then
        return 1
    elif ! {
        export -f validate_input_vcf_files;
        export -f process_vep_vcf_block;
        export -f annotate_vep;
        export -f log_message;
    }; then
        return 1
    elif ! mkdir -p "$RUNTIME_DIR/VEP" "$RUNTIME_DIR/LOG"; then
        return 1
    elif ! check_ongoing_applet_runs ; then
        return 1
    elif ! mapfile -t vep_input_files < <(dx cat "${DX_PROJECT_CONTEXT_ID}:${VCF_LIST_HASH}") ; then
        return 1
    elif [[ ${#vep_input_files[@]} -eq 0 ]]; then
        return 1
    else
         log_message "INFO: Proceeding to validate ${#vep_input_files[@]} input files ..."
    fi


    ################
    # Validate input
    ################

    if ! parallel \
            --jobs "$N_JOBS" \
            --results "${RUNTIME_DIR}/LOG" \
            --joblog "${RUNTIME_DIR}/LOG/${VAL_LOG}" \
            --timeout 300 \
            validate_input_vcf_files ::: "${vep_input_files[@]}"; then

        log_message "INFO: Some validation jobs failed or killed"

    fi            



    if ! [[ -f "${RUNTIME_DIR}/LOG/${VAL_LOG}" ]]; then

        log_message "ERROR: Could not find validation log"


    elif ! mapfile -t vep_valid_files < <(get_validation_results); then

        log_message "ERROR: Failed to get a list of validated file IDs - exiting"
        return 1

    elif [[ ${#vep_valid_files[@]} -eq 0 || ${vep_valid_files[0]} == "NA" ]]; then
        
        log_message "INFO: No valid files to process - terminating applet"
        return 0

    else

        log_message "INFO: Proceeding with ${#vep_valid_files[@]} valid files ..."

    fi

    ##################
    # Load VEP docker
    ##################
    
    log_message "INFO: Loading and testing vep"

    if ! stage_vep; then

        log_message "ERROR: Failed to load VEP - exiting"
        return 1
    
    else

        log_message "INFO: Starting a progress monitor"

        progress_monitor_fx "${#vep_valid_files[@]}" &
        
        trap cleanup_and_exit EXIT

    fi



    ###################################################
    # Call the annotation function on requiested files
    ###################################################


    if ! parallel \
        --jobs "$N_JOBS" \
        --results "${RUNTIME_DIR}/LOG" \
        --joblog "${RUNTIME_DIR}/LOG/${PAR_LOG}" \
        --timeout ${VEP_TIMEOUT} \
        process_vep_vcf_block ::: "${vep_valid_files[@]}"; then

        log_message "INFO: Some annotation jobs failed or killed"

    fi            



    if ! [[ -f "${RUNTIME_DIR}/LOG/${PAR_LOG}" ]] ; then

        log_message "ERROR: Failed to find parallel session log - exiting"

        return 1

    
    elif ! create_session_log; then

        log_message "ERROR: Failed to create session log - exiting"

        return 1

    else

        log_message "INFO: Finished running VEP"

        return 0

    fi


}