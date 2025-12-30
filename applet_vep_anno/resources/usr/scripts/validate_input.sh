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
    local ukb=""
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
    ukb=$(echo "$vcf_name" | cut -f1 -d '.' | cut -f1 -d'_' | tr -d 'ukb' 2> /dev/null || echo '' )
    chr=$(echo "$vcf_name" | cut -f1 -d '.' | cut -f2 -d'_' | tr -d 'c' 2> /dev/null || echo '' )
    blk=$(echo "$vcf_name" | cut -f1 -d '.' | cut -f3 -d'_' | tr -d 'b' 2> /dev/null || echo '' )
    

    # Input name validation
    if [[ ! "$vcf_hash" =~ ^file- ]] || [[ ! "$vcf_name" =~ ^ukb ]] || [[ ! "$vcf_name" =~ .vcf.gz$ ]] || [[ ! "$chr" == "$VEP_CHR" ]] || [[ ! "$blk" =~ ^[0-9][0-9]*$ ]] || [[ ! "$ukb" =~ ^[0-9][0-9]*$ ]]; then

        log_message "ERROR: Malformed input or file name does not match expected pattern (ukb0000_cx_bx_v1.vcf.gz) - Rejected"

        log_message "REJECTED: file-$vcf_input"
        return 0

    else

        log_message "INFO: Mapped to block $blk of chromosome $chr from field $ukb"
    
    fi



    ##################################
    # Skip if there is previous output
    ##################################

    log_message "INFO: Checking previous outputs ..."        

    results_desc=$(dx describe --json --multi "${DX_PROJECT_CONTEXT_ID}:${DX_OUTPUT_DIR}/logs/${vcf_name%.vcf.gz}.vep.outputs.txt" | jq .[0] 2> /dev/null || echo '')

    if [[ -z ${results_desc} ]] || [[ ${results_desc} == null ]]; then

        log_message "INFO: None found in ${DX_OUTPUT_DIR}/logs ..."        

    else

        results_hash=$(echo $results_desc | jq -r '.id' 2> /dev/null || echo "")

        #############################################################################
        if dx cat "${results_hash}" 2> /dev/null |\
            awk -v ukb=$ukb -v chr=$chr -v blk=$blk -v hash=$vcf_hash '$1 ~ ukb && $2 == chr && $3 == blk && $4 == hash' |\
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

        # In this case, fill 'NA' instead of expected output file
        results_array+=("${ukb}" "${chr}" "${blk}" "${vcf_hash}" "NA")
        

        #####################################################################################################
        if ! results_hash=$(echo "${results_array[@]}" |\
                dx upload - \
                    -p --path "logs/${vcf_name%.vcf.gz}.vep.outputs.txt" \
                    --tag "vep_output" \
                    --property "$(printf 'ukb=%s' "$ukb")" \
                    --property "$(printf 'chromosome=%s' "$chr")" \
                    --property "$(printf 'block=%s' "$blk")" \
                    --wait --brief 2> /dev/null); then

            log_message "ERROR: Could not upload final output list - Failed"
            log_message "FAILED: $vcf_hash"
            return 1

        elif ! dx-jobutil-add-output vep_log "${results_hash}" --class=array:file ; then

            log_message "ERROR: Failed to add final output list to applet's record of final outputs - Failed"
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