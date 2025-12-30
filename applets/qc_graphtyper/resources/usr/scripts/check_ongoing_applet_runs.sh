check_ongoing_applet_runs() {
    local ongoing_jobs=""
    local job_count=""
    local job_id=""
    local job_describe=""
    local job_input=""
    local job_status=""
    local job_created_ms=""
    local job_created=""



    if [[ -z "$DX_APPLET_ID" ]] || [[ "$DX_APPLET_ID" == null ]]; then
        log_message "ERROR: Could not determine current applet ID from environment."
        return 1
    else
        log_message "INFO: Applet ID: $DX_APPLET_ID"
    fi
    
    log_message "INFO: Checking for current or previous runs with same input $VCF_LIST_HASH ..."
    
    # Find running or runnable jobs for this applet (using actual applet ID)
    ongoing_jobs=$(dx find jobs \
        --project ${DX_PROJECT_CONTEXT_ID} \
        --executable "$DX_APPLET_ID" \
        --brief |\
        sed 's/project-.*://' 2>/dev/null || true)
    
    if [[ -z "$ongoing_jobs" ]]; then
        log_message "ERROR: Failed to properly identify running jobs (should at least identify self)"
        return 1
    fi

    job_count=$(echo "$ongoing_jobs" | wc -l)
    log_message "INFO: Found $(( $job_count - 1)) other job(s) for this applet"
    
    # Check each ongoing job for matching input
    while read -r job_id; do
        if [[ -n "$job_id" ]]; then

            # Skip checking our own job
            if [[ "$job_id" == "$DX_JOB_ID" ]]; then
                continue
            fi
            
            # Get job details with jq - parse the describe output directly to get the input file
            job_describe=$(dx describe --json "$job_id"  | sed 's/project-.*://' 2>/dev/null || echo "")
            
            # Skip of no description
            if [[ -z "$job_describe" ]]; then
                log_message "ERROR: Could not describe job $job_id"
                return 1

            else

                # Parse JSON to get the input file ID
                job_input=$(echo "$job_describe" | jq -r '.runInput.ukb23374_vcf_list["$dnanexus_link"]' | sed 's/project-.*://' 2>/dev/null || echo "")

                # If that didn't work or the result isn't as expected, fail
                if [[ -z "$job_input" ]] || [[ ! "$job_input" =~ ^file- ]]; then
                    log_message "ERROR: Could not parse the input of job $job_id"
                    return 1

                else


                    job_status=$(echo "$job_describe" | jq -r .state | sed 's/project-.*://' 2>/dev/null || echo "unknown")

                    # Get creation time
                    job_created_ms=$(echo "$job_describe" | jq -r .created | sed 's/project-.*://' 2>/dev/null || echo "0")

                    # Parse creation time
                    job_created=$(date -u -d "@$(( job_created_ms / 1000))" 2>/dev/null || echo "unknown")

                fi


            fi

            # Check if input is indentical
            if [[ "$job_input" == "$VCF_LIST_HASH" ]]; then
                log_message "INFO: Found ongoing applet run with same input $VCF_LIST_HASH:"
                log_message "INFO:   Job ID: $job_id"
                log_message "INFO:   Job input: $job_input"
                log_message "INFO:   Created: $job_created"
                log_message "INFO:   Status: $job_status"

                case "$job_status" in
                  "terminated"|"failed"|"done")
                    log_message "INFO: Previous job status is $job_status - Proceeding"
                    ;;
                  *)
                    log_message "ERROR: The previous job is $job_status - Aborting to avoid duplicate processing"
                    return 1
                    ;;
                esac

            else
                continue
            fi
        fi
    done <<< "$ongoing_jobs"
    
    log_message "INFO: No ongoing runs using the same input"
    return 0
}
