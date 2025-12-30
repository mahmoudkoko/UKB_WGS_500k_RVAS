process_graphtyper_vcf_block() {
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
    local chr=""
    local blk=""
    local file_name_prefix=""
    local free_disk_size=""
    local vcf_disk_size=""
    local var_qc_fields=()
    local output_dir_upload_hash=()
    local output_list_upload_hash=""




    # Function-specific cleanup
    cleanup_vcf_processing_dir() {
        local exit_code=$?
        
        log_message "INFO: Cleaning up vcf working directory"
        

        # Always clean up the working directory at the end
        if [[ -n "${vcf_dir:-}" && -d "$vcf_dir" ]]; then
            rm -rf "$vcf_dir" 2>/dev/null || true
        fi
        

        return $exit_code
    }
    
    # Set up function-specific cleanup trap; it will be invoked to delete the local files whenever the function returns
    trap cleanup_vcf_processing_dir EXIT INT TERM RETURN
    

    # Check disk space

    check_disk_space() {

        local req_disk_space=$1

        while true; do


        free_disk_size=$(df -BM . | awk 'NR==2 {gsub(/M/,"",$4);print $4}' || echo 0 )

        # Break if there is space
        [[ $free_disk_size -gt $req_disk_space ]] && break

        # Wait for 5min if there is no space
        log_message "INFO: ${free_disk_size}/${req_disk_space}MB. Waiting for more space to free up ..." && sleep 300

    done

    log_message "INFO: Available disk space is ~$(( free_disk_size / 1024))GB. Proceeding ..." 
    return

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
    
    # Chr and block
    chr=$(echo "$vcf_name" | cut -f2 -d'_' | tr -d 'c' || echo '')
    blk=$(echo "$vcf_name" | cut -f3 -d'_' | tr -d 'b' || echo '')    


    # Input name validation
    if [[ ! "$vcf_hash" =~ ^file- ]] || [[ ! "$vcf_name" =~ ^ukb23374_c ]] || [[ ! "$vcf_name" =~ _v1.vcf.gz$ ]] || [[ ! "$chr" =~ ^([1-9]|1[0-9]|2[0-2]|X|x)$ ]] || [[ ! "$blk" =~ ^-?[0-9]+$ ]]; then

        log_message "ERROR: Malformed input or file name does not match expected pattern (ukb23374_cx_bx_v1.vcf.gz)"
        log_message "FAILED: $vcf_hash"
        return 1

    else

        log_message "INFO: Mapped to GraphTyper/GATK block $blk of chromosome $chr"
    
    fi


    # VCF dir
    vcf_dir="${vcf_hash#file-}"

    # Initiate workspace directories
    mkdir -p "$vcf_dir" "$vcf_dir/tmp" "$vcf_dir/pfiles" "$vcf_dir/sites" "$vcf_dir/stats"



    # Extract name prefix
    file_name_prefix="${vcf_name%".vcf.gz"}"


    ##############
    # Download VCF
    ##############

    log_message "INFO: Downloading ${vcf_hash} ..."

    # Monitor disk size and continue if there is enough space

    # VCF size in MB
    vcf_size=$(( $(echo $vcf_desc | jq -r .size ) / 1024 / 1024 ))
    
    # Check if there is enough space do download
    vcf_disk_size=$(( vcf_size * 12/10 ))

    log_message "INFO: File size is ~$(( vcf_size / 1024 ))GB ..."

    check_disk_space "$vcf_disk_size"

    # Download and verify
    if ! dx download -f "${DX_PROJECT_CONTEXT_ID}:${vcf_hash}" --output "${vcf_dir}/tmp/${vcf_name}" --no-progress 2> /dev/null; then

        log_message "ERROR: Failed to download VCF"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! [[ -f "${vcf_dir}/tmp/${vcf_name}" ]]; then

        log_message "ERROR: Failed to locate downloaded VCF $vcf_name"
        log_message "FAILED: $vcf_hash"
        return 1

    else
        
        log_message "INFO: VCF successfully downloaded"

    fi


    ###########################
    # Split multi-allelic sites
    ###########################
    
    log_message "INFO: Splitting multi-allelic sites ..."

    check_disk_space "$vcf_disk_size"


    if ! bcf_filter_gt "${vcf_dir}/tmp/${file_name_prefix}.vcf.gz" "${vcf_dir}/tmp/${file_name_prefix}.qc.bcf"; then

        log_message "ERROR: Failed to split multi-allelic sites"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! rm "${vcf_dir}/tmp/${file_name_prefix}.vcf.gz";then

        log_message "ERROR: Failed to delete VCF after creating split BCF"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! [[ -f "${vcf_dir}/tmp/${file_name_prefix}.qc.bcf" ]]; then

        log_message "ERROR: Failed to locate bcf after splitting"
        log_message "FAILED: $vcf_hash"
        return 1

    else
        log_message "INFO: BCF splitting completed"

    fi



    ############################
    # Confirm there are variants
    ############################

    

    if bcftools view --no-header "${vcf_dir}/tmp/${file_name_prefix}.qc.bcf" 2> /dev/null | grep -q . 2> /dev/null; then
 
        log_message "INFO: Confirmed variants remain after splitting multi-allelic sites ..."        

    else
        log_message "INFO: No variants in this VCF block after removing complex multi-allelic sites with > 10 ALT"

        # In this case, fill 'NA' instead of expected output files (plink_pgen,plink_pvar,plink_psam,plink_log,sites_bed,sites_bcf,sites_index,var_scores,var_counts,geno_counts)
        
        #####################################################################################################

        if output_list_upload_hash=$(echo "${chr}" "${blk}" "${vcf_hash}" "NA" "NA" "NA" "NA" "NA" "NA" "NA" "NA" "NA" "NA" |\
                dx upload - \
                    -p --path "logs/${file_name_prefix}.qc.outputs.txt" \
                    --tag "wgs_qc_log" \
                    --property "$(printf 'chromosome=%s' "$chr")" \
                    --property "$(printf 'block=%s' "$blk")" \
                    --brief 2> /dev/null); then

            log_message "INFO: Successfully uploaded empty output list"

        else

            log_message "ERROR: Failed to upload empty output list"
            log_message "FAILED: $vcf_hash"
            return 1

        fi


        #####################################################################################################


        if dx-jobutil-add-output qc_output_files "${output_list_upload_hash}" --class=array:file ; then

            log_message "INFO: Successfully added empty outputs list to applet's record of final outputs"

        else

            log_message "ERROR: Failed to add empty outputs list to applet's record of final outputs"
            log_message "FAILED: $vcf_hash"
            return 1

        fi

        #####################################################################################################
        # DONE
        log_message "INFO: Successfully recorded outcome for $vcf_name"
        log_message "EMPTY: $vcf_hash"
        return 0

    fi



    # ###################
    # # Apply genotype QC
    # ###################
    
    # log_message "INFO: Applying genotype QC ..."


    # if ! bcf_filter_gt "${vcf_dir}/tmp/${file_name_prefix}.split.bcf" "${vcf_dir}/tmp/${file_name_prefix}.qc.bcf"; then

    #     log_message "ERROR: Failed to apply genotype QC"
    #     log_message "FAILED: $vcf_hash"
    #     return 1

    # elif ! rm "${vcf_dir}/tmp/${file_name_prefix}.split.bcf" "${vcf_dir}/tmp/${file_name_prefix}.split.bcf.csi";then

    #     log_message "ERROR: Failed to delete temp BCF after genotype QC"
    #     log_message "FAILED: $vcf_hash"
    #     return 1

    # elif ! [[ -f "${vcf_dir}/tmp/${file_name_prefix}.qc.bcf" ]]; then

    #     log_message "ERROR: Failed to locate bcf after QC"
    #     log_message "FAILED: $vcf_hash"
    #     return 1

    # else
    #     log_message "INFO: BCF QC completed"

    # fi

    #####################
    # BCF > Plink2 pfiles
    #####################
        

    log_message "INFO: Converting BCF file to plink2 files ..."

    if ! plink2 --make-pgen 'vzs' \
        --bcf "${vcf_dir}/tmp/${file_name_prefix}.qc.bcf" \
        --vcf-half-call m \
        --threads $JOB_CPUS \
        --memory $(( JOB_MEM * 1000 )) \
        --out "${vcf_dir}/pfiles/${file_name_prefix}.qc"; then

        log_message "ERROR: Plink2 conversion failed"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! rm "${vcf_dir}/tmp/${file_name_prefix}.qc.bcf" "${vcf_dir}/tmp/${file_name_prefix}.qc.bcf.csi"; then

        log_message "ERROR: Failed to delete temporary BCF file"
        log_message "FAILED: $vcf_hash"
        return 1

    else

        log_message "INFO: Plink2 conversion completed"

    fi


    ####################
    # Generate sites BCF
    ####################


    log_message "INFO: Started processing variant records"
    
    if ! zstdcat "${vcf_dir}/pfiles/${file_name_prefix}.qc.pvar.zst" |\
        awk -F"\t" 'BEGIN{print "##fileformat=VCFv4.2"}!/^#/{exit}1' OFS="\t" |\
        bgzip > "${vcf_dir}/tmp/${file_name_prefix}.qc.sites.vcf.gz"; then

        log_message "ERROR: Failed to generate header for sites-only VCF"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! zstdcat "${vcf_dir}/pfiles/${file_name_prefix}.qc.pvar.zst" |\
        awk '!/^#/' |\
        awk -F'\t' -v blk="${blk}" -v bed_file="${vcf_dir}/sites/${file_name_prefix}.qc.bed" \
        'NR==1{ start_position=$2 }{$3=$1":"blk":"NR; print "chr"$0}END{ end_position=$2; print "chr"$1,start_position,end_position,"b"blk,NR > bed_file }' OFS="\t" |\
        bgzip >> "${vcf_dir}/tmp/${file_name_prefix}.qc.sites.vcf.gz"; then

        log_message "ERROR: Failed to add records to sites-only VCF"
        log_message "FAILED: $vcf_hash"
        return 1    
    
    elif ! bcftools view --no-version -Ob --threads 2 --write-index=csi -o "${vcf_dir}/sites/${file_name_prefix}.qc.sites.bcf" "${vcf_dir}/tmp/${file_name_prefix}.qc.sites.vcf.gz"; then

        log_message "ERROR: Failed to generate indexed sites-only BCF"
        log_message "FAILED: $vcf_hash"
        return 1

    else

        log_message "INFO: Generated sites-only BCF"

    fi


    ######################
    # Updating variant IDs
    ######################


    log_message "INFO: Updating variant IDs in plink2 pvar"


    if ! zcat "${vcf_dir}/tmp/${file_name_prefix}.qc.sites.vcf.gz" |\
        awk -F"\t" '/^##fileformat/ || /^##FILTER/ || /^##INFO/{next;}/^##/{print}/^#CHROM/{$7=$8;NF=7;print}!/^#/{gsub("^chr","");$6=".";$7=".";NF=7;print}' OFS="\t" |\
        zstd --no-progress --stdout > "${vcf_dir}/pfiles/${file_name_prefix}.qc.pvar.zst" ; then

        log_message "ERROR: Failed to update variant IDs in pvar file"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! rm "${vcf_dir}/tmp/${file_name_prefix}.qc.sites.vcf.gz";then

        log_message "ERROR: Failed to delete temporary sites-only VCF file"
        log_message "FAILED: $vcf_hash"
        return 1

    else

        log_message "INFO: Variant processing completed"

    fi



    ###################
    # Per-sample counts
    ###################

    log_message "INFO: Collecting per-sample variant counts ..."

    if ! plink2 --pfile "${vcf_dir}/pfiles/${file_name_prefix}.qc" 'vzs' \
        --sample-counts 'zs' 'cols=homref,homalt,homaltsnp,het,ts,tv,single,missing' \
        --threads $JOB_CPUS \
        --memory $(( JOB_MEM * 1000 )) \
        --out "${vcf_dir}/tmp/${file_name_prefix}.qc"; then

        log_message "ERROR: Failed to collect sample metrics"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! zstdcat "${vcf_dir}/tmp/${file_name_prefix}.qc.scount.zst" |\
        awk '!/^#/' |\
        tr ' ' '\t' |\
        gzip > "${vcf_dir}/stats/${file_name_prefix}.qc.sample_stats.tsv.gz"; then

        log_message "ERROR: Failed to reformat sample counts file"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! gzip "${vcf_dir}/pfiles/${file_name_prefix}.qc.psam"; then

        log_message "ERROR: Failed to compress plink2 sample file"
        log_message "FAILED: $vcf_hash"
        return 1

    elif ! rm -rf "${vcf_dir}/tmp/${file_name_prefix}.qc.log" "${vcf_dir}/tmp/${file_name_prefix}.qc.scount.zst" ; then

        log_message "ERROR: Failed to delete temporary stat files"
        log_message "FAILED: $vcf_hash"
        return 1

    else

        log_message "INFO: Per-sample stats completed"

    fi


    ######################
    # Collect variant info
    ######################


    # Variant info & quality:
    var_qc_fields=("%ID" "%TYPE" "%NS" "%AC" "%AF" "%FILTER" "%QUAL" "%AAScore" "%QD" "%QDalt" "%GQ_AVG")

    # Genotype counts
    var_qc_fields+=("%ID" "%NS_REF" "%NS_HET" "%NS_HOM" "%NS_MIS" "%GQ40_REF" "%GQ40_HET" "%GQ40_HOM")
    
    # Concatenate all
    var_qc_fields="${var_qc_fields[@]}\n"

    
    # Query
    if bcftools query -f "${var_qc_fields}" "${vcf_dir}/sites/${file_name_prefix}.qc.sites.bcf" |\
        tr ' ' '\t' |\
        gzip > "${vcf_dir}/tmp/${file_name_prefix}.qc.query.tsv.gz"; then

        log_message "INFO: Collected variant info"

    else

        log_message "ERROR: Failed to query variant info from sites-only BCF"
        log_message "FAILED: $vcf_hash"
        return 1

    fi
    


    # Cut quality scores
    if zcat "${vcf_dir}/tmp/${file_name_prefix}.qc.query.tsv.gz" |\
        cut -f1-11 |\
        gzip > "${vcf_dir}/stats/${file_name_prefix}.qc.quality_scores.tsv.gz"; then


        log_message "INFO: Collected variant scores"

    else

        log_message "ERROR: Failed to collect variant quality scores from sites-only BCF"
        log_message "FAILED: $vcf_hash"
        return 1

    fi
    


    # Cut genotype counts
    if zcat "${vcf_dir}/tmp/${file_name_prefix}.qc.query.tsv.gz" |\
        cut -f12-19 |\
        gzip > "${vcf_dir}/stats/${file_name_prefix}.qc.geno_counts.tsv.gz"; then


        log_message "INFO: Collected genotype counts"

    else

        log_message "ERROR: Failed to collect genotype counts from sites-only BCF"
        log_message "FAILED: $vcf_hash"
        return 1

    fi
    

    # Delete tmp
    if rm -rf "${vcf_dir}/tmp/"; then

        log_message "INFO: Deleted temp variant info file and temp directory"

    else

        log_message "ERROR: Failed to remove temp variant info file"
        log_message "FAILED: $vcf_hash"
        return 1

    fi



    #######################
    # Uploading new outputs
    #######################
    
    log_message "INFO: Uploading outputs to destination directory ..."

    if mapfile -t output_dir_upload_hash < <(dx upload --recursive "$vcf_dir/" --tag "wgs_qc_output" -p --brief); then

        log_message "INFO: Successfully uploaded ${#output_dir_upload_hash[@]} outputs"

    else

        log_message "ERROR: Failed to upload qc output files to destination directory"
        log_message "FAILED: $vcf_hash"
        return 1

    fi




    if output_list_upload_hash=$(echo "${chr}" "${blk}" "${vcf_hash}" "${output_dir_upload_hash[@]}" |\
            dx upload - \
                -p --path "logs/${file_name_prefix}.qc.outputs.txt" \
                --tag "wgs_qc_log" \
                --property "$(printf 'chromosome=%s' "$chr")" \
                --property "$(printf 'block=%s' "$blk")" \
                --brief 2> /dev/null); then

        log_message "INFO: Successfully uploaded final output list"

    else

        log_message "ERROR: Failed to upload final output list"
        log_message "FAILED: $vcf_hash"
        return 1

    fi




    ####################
    # Commit new outputs
    ####################
    

    if printf "%s\n" "${output_dir_upload_hash[@]}" | xargs -P1 -I{} dx-jobutil-add-output qc_output_files "{}" --class=array:file ; then

        log_message "INFO: Successfully added qc outputs to applet's record of final outputs"

    else

        log_message "ERROR: Failed to add qc outputs to applet's record of final outputs"
        log_message "FAILED: $vcf_hash"
        return 1

    fi




    if dx-jobutil-add-output qc_output_files "${output_list_upload_hash}" --class=array:file ; then

        log_message "INFO: Successfully added outputs list to applet's record of final outputs"

    else

        log_message "ERROR: Failed to add final outputs list to applet's record of final outputs"
        log_message "FAILED: $vcf_hash"
        return 1

    fi


#####
# END
#####

    log_message "INFO: Successfully uploaded outputs for $vcf_name"
    log_message "DONE: $vcf_hash"
    return 0
    
}