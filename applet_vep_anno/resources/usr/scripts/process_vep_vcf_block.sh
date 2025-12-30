process_vep_vcf_block() {
#######
# BEGIN
#######


    #########################
    # Function initialization
    #########################
    local vcf_hash=""
    local vcf_name=""
    local vcf_dir=""
    local vcf_size=""
    local ukb=""
    local chr=""
    local blk=""
    local file_name_prefix=""
    local output_tsv_upload_hash=""
    local output_list_upload_hash=""


    force_clean_up() {

        # ensures cleanup if the function is killed or there is an error
        rm -rf "${VEP_HOME}/io/${vcf_name}" "${VEP_HOME}/io/${file_name_prefix}.vep.tsv.gz" 2> /dev/null || true

    }



    ##################
    # Processing input
    ##################

    log_message "INFO: Processing Input: $1"

    # Input hash
    vcf_hash="$1"

    # Description
    vcf_desc=$(dx describe --json --multi "${DX_PROJECT_CONTEXT_ID}:$vcf_hash" | jq .[0] || echo '')

    # Get the vcf name from the description
    vcf_name=$(echo $vcf_desc | jq -r .name || echo '')
    file_name_prefix="${vcf_name%".vcf.gz"}"
    ukb=$(echo "$vcf_name" | cut -f1 -d"." | cut -f1 -d'_' | tr -d 'ukb' || echo '')
    chr=$(echo "$vcf_name" | cut -f1 -d"." | cut -f2 -d'_' | tr -d 'c' || echo '')
    blk=$(echo "$vcf_name" | cut -f1 -d"." | cut -f3 -d'_' | tr -d 'b' || echo '')    


    # Input name validation
    if [[ ! "$vcf_hash" =~ ^file- ]] || [[ ! "$vcf_name" =~ ^ukb ]] || [[ ! "$vcf_name" =~ .vcf.gz$ ]] || [[ ! "$chr" == "$VEP_CHR" ]] || [[ ! "$blk" =~ ^-?[0-9]+$ ]] || [[ ! "$ukb" =~ ^-?[0-9]+$ ]]; then

        log_message "ERROR: Malformed input. Wrong chromosome or file name does not match expected pattern (ukb_cx_bx_.*.vcf.gz)"
        log_message "REJECTED: $vcf_hash"
        return 1

    else

        log_message "INFO: Input VCF: Block: $blk - Chromosome $chr - Source field: $ukb"
    
    fi



    ##############
    # Download VCF
    ##############

    log_message "INFO: Downloading ${vcf_hash} ..."


    # Download and verify
    if ! dx download -f "${DX_PROJECT_CONTEXT_ID}:${vcf_hash}" --output "${VEP_HOME}/io/${vcf_name}" --no-progress 2> /dev/null; then

        log_message "ERROR: Failed to download VCF"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! [[ -f "${VEP_HOME}/io/${vcf_name}" ]]; then

        log_message "ERROR: Failed to locate downloaded VCF $vcf_name"
        log_message "FAILED: $vcf_hash"
        return 1

    else
        
        log_message "INFO: VCF successfully downloaded"
        
        trap force_clean_up ERR SIGTERM SIGINT

    fi



    ################################
    # Annotate if there are variants
    ################################

  

    if bcftools view --no-header "${VEP_HOME}/io/${vcf_name}" 2> /dev/null | grep -q . 2> /dev/null; then
 
        log_message "INFO: Annotating variants..."        


        if ! annotate_vep "${VEP_HOME}/io/${vcf_name}"; then

            log_message "ERROR: Failed to annotate with VEP"
            log_message "FAILED: $vcf_hash"
            return 1

        elif ! output_tsv_upload_hash=$(dx upload "${VEP_HOME}/io/${file_name_prefix}.vep.tsv.gz" --tag "vep_output" -p --path "vep/" --brief); then

            log_message "ERROR: Failed to upload vep output file to destination directory"
            log_message "FAILED: $vcf_hash"
            return 1

        elif ! dx-jobutil-add-output vep_out "${output_tsv_upload_hash}" --class=array:file ; then

            log_message "ERROR: Failed to add vep output to applet's record of final outputs"
            log_message "FAILED: $vcf_hash"
            return 1

        elif ! rm "${VEP_HOME}/io/${vcf_name}" "${VEP_HOME}/io/${file_name_prefix}.vep.tsv.gz"; then

            log_message "ERROR: Failed to remove vep input or output file after upload"
            log_message "FAILED: $vcf_hash"
            return 1

        else

            log_message "INFO: Successfully annotated this vcf and uploaded vep output file"

        fi



    else

        log_message "INFO: No variants in this VCF block ..."


        if ! rm "${VEP_HOME}/io/${vcf_name}"; then

            log_message "ERROR: Failed to remove vep input or output file after upload"
            log_message "FAILED: $vcf_hash"
            return 1

        else

            output_tsv_upload_hash="NA"

        fi


    fi






    ###########################
    # Uploading list of outputs
    ###########################
    

    if ! output_list_upload_hash=$(echo "${ukb} ${chr} ${blk} ${vcf_hash} ${output_tsv_upload_hash}" |\
            dx upload - \
                -p --path "logs/${file_name_prefix}.vep.outputs.txt" \
                --tag "vep_output" \
                --property "$(printf 'ukb=%s' "$ukb")" \
                --property "$(printf 'chromosome=%s' "$chr")" \
                --property "$(printf 'block=%s' "$blk")" \
                --brief 2> /dev/null); then

        log_message "ERROR: Failed to upload output list"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! dx-jobutil-add-output vep_log "${output_list_upload_hash}" --class=array:file ; then

        log_message "ERROR: Failed to add outputs log to applet's record of final logs"
        log_message "FAILED: $vcf_hash"
        return 1

    else

        log_message "INFO: Successfully recorded outcome for $vcf_name"
        log_message "DONE: $vcf_hash"
        return 0

    fi



#####
# END
#####    
}