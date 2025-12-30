validate_input_vcf_files() {
#######
# BEGIN
#######


    #########################
    # Function initialization
    #########################

    local vcf_input=""
    local vcf_desc=""
    local vcf_hash=""
    local vcf_name=""
    local chr=""
    local blk=""
    local results_desc=""
    local results_hash=""
    local results_array=()



    ##################
    # Processing input
    ##################

    log_message "INFO: Processing Input: $1"        

    # Cleanup the input (remove any project reference and any quotes)
    vcf_input="$(echo $1 | sed -e "s/project-.*://" -e 's/^"//' -e 's/"$//' 2>/dev/null || echo '')"

    # Get the description (of the latest object if multiple)
    vcf_desc=$(dx describe --json --multi "${DX_PROJECT_CONTEXT_ID}:$vcf_input" | jq .[0] 2> /dev/null || echo '')

    # Get the VCF hash from the description
    vcf_hash="$(echo $vcf_desc | jq -r .id 2> /dev/null || echo '' )"

    # Get the vcf name from the description
    vcf_name="$(echo $vcf_desc | jq -r .name 2> /dev/null || echo '' )"

    # Extract chromosome and block
    chr=$(echo "$vcf_name" | cut -f2 -d'_' | tr -d 'c' 2> /dev/null || echo '' )
    blk=$(echo "$vcf_name" | cut -f3 -d'_' | tr -d 'b' 2> /dev/null || echo '' )
    

    # Input name validation
    if [[ ! "$vcf_hash" =~ ^file- ]] || [[ ! "$vcf_name" =~ ^ukb23374_c ]] || [[ ! "$vcf_name" =~ _v1.vcf.gz$ ]] || [[ ! "$chr" =~ ^([1-9]|1[0-9]|2[0-2]|X|x)$ ]] || [[ ! "$blk" =~ ^-?[0-9]+$ ]]; then

        log_message "ERROR: Malformed input or file name does not match expected pattern (ukb23374_cx_bx_v1.vcf.gz) - Rejected"

        log_message "INVALID: file-$vcf_input"
        return 1

    else

        log_message "INFO: Mapped to GraphTyper/GATK block $blk of chromosome $chr"
    
    fi



    ##################################
    # Skip if there is previous output
    ##################################

    log_message "INFO: Checking previous outputs ..."        

    results_desc=$(dx describe --json --multi "${DX_PROJECT_CONTEXT_ID}:${DX_OUTPUT_DIR}/logs/${vcf_name%.vcf.gz}.qc.outputs.txt" | jq .[0] 2> /dev/null || echo '')

    if [[ -z ${results_desc} ]] || [[ ${results_desc} == null ]]; then

        log_message "INFO: None found in ${DX_OUTPUT_DIR}/logs ..."        

    else

        results_hash=$(echo $results_desc | jq -r '.id' 2> /dev/null || echo "")

        #############################################################################
        if dx cat "${results_hash}" 2> /dev/null |\
            awk -v chr=$chr -v blk=$blk -v hash=$vcf_hash '$1 == chr && $2 == blk && $3 == hash' |\
            grep -q . 2> /dev/null; then

            log_message "INFO: Found existing outputs - Skipped"
            log_message "SKIPPED: $vcf_hash"
            return 0
        else

            log_message "ERROR: Found existing outputs but details don't match - Failed"
            log_message "FAILED: $vcf_hash"
            return 1        
        fi
        #############################################################################


    fi



    ########################
    # Check VCF for variants
    ########################

    log_message "INFO: Checking for variants ..."        
    

    if ! dx cat "${DX_PROJECT_CONTEXT_ID}:${vcf_hash}" 2> /dev/null | zgrep -q . 2> /dev/null ; then

        log_message "ERROR: Failed to read VCF - Failed"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! dx cat "${DX_PROJECT_CONTEXT_ID}:${vcf_hash}" 2> /dev/null | zgrep . | awk '/^#/{next;}{print;exit}' | grep -q .  2> /dev/null; then
 
        log_message "INFO: No variants in this VCF block ..."

        # In this case, fill 'NA' instead of expected output files (bgen,pvar,psam,bed,sites,index,var_scores,var_counts,gt_counts)
        results_array+=("${chr}" "${blk}" "${vcf_hash}" "NA" "NA" "NA" "NA" "NA" "NA" "NA" "NA" "NA" "NA")
        

        #####################################################################################################
        if ! results_hash=$(echo "${results_array[@]}" |\
                dx upload - \
                    -p --path "logs/${vcf_name%.vcf.gz}.qc.outputs.txt" \
                    --tag "wgs_qc_log" \
                    --property "$(printf 'chromosome=%s' "$chr")" \
                    --property "$(printf 'block=%s' "$blk")" \
                    --wait --brief); then

            log_message "ERROR: Failed to upload final output list - Failed"
            log_message "FAILED: $vcf_hash"
            return 1

        elif ! dx-jobutil-add-output qc_output_files "${results_hash}" --class=array:file ; then

            log_message "ERROR: Failed to add final output list to applet's record of final outputs - Failed"
            log_message "FAILED: $vcf_hash"
            return 1

        elif ! dx cat "${results_hash}" | grep -q . 2> /dev/null ; then

            log_message "ERROR: Failed to recall final output list after upload - Failed"
            log_message "FAILED: $vcf_hash"
            return 1

        else
            # Done.
            log_message "INFO: Successfully recorded outcome - Finished"
            log_message "EMPTY: $vcf_hash"
            return 0
        fi
        #####################################################################################################
        
    fi


    #####################
    # Return the VCF hash
    #####################    

    log_message "INFO: Confirmed there are variant record(s) - Validated"
    log_message "VALID: $vcf_hash"
    echo $vcf_hash
    return 0

}