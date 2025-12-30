stage_vep() {


    #########
    # Cleanup
    #########

    # cleanup_vep_staging_dir() {
    #     local exit_code=$?

    #     if [[ exit_code -eq 0 ]] ; then

    #         echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Deleting temp dir" >&2
    #         rm -rf "$VEP_HOME/tmp" 2>/dev/null || true

    #     else
    #         echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Deleting vep staging directories" >&2
    #         rm -rf $VEP_HOME/cache $VEP_HOME/fasta $VEP_HOME/plugins $VEP_HOME/io $VEP_HOME/tmp 2>/dev/null || true

    #     fi
        

    #     return $exit_code
    # }
    
    # trap cleanup_vep_staging_dir RETURN
 
    ##########
    # Download
    ##########

    if ! mkdir -p $VEP_HOME/cache $VEP_HOME/fasta $VEP_HOME/plugins $VEP_HOME/io $VEP_HOME/tmp; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to create input directories" >&2
        return 1

    elif ! dx download --no-progress ${VEP_DOCKER} -o $VEP_HOME/tmp/docker.tar.gz; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to download docker tar file" >&2
        return 1

    elif ! dx download --no-progress "$VEP_PLUGINS" -o $VEP_HOME/tmp/plugins.tar.gz; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to download plugins tar file" >&2
        return 1

    elif ! dx download --no-progress --recursive "$VEP_DATA" -o $VEP_HOME/tmp/ ; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to download cache directory and files" >&2
        return 1

    else

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Downloaded input data" >&2

    fi


################################
# Prep vep cache and annotations
################################

    # Cache
    if ! tar -xf $VEP_HOME/tmp/chr${VEP_CHR}/vep_cache_chr${VEP_CHR}.tar -C $VEP_HOME/cache; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to decompress cache tar file" >&2
            return 1

    elif ! rm $VEP_HOME/tmp/chr${VEP_CHR}/vep_cache_chr${VEP_CHR}.tar; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to delete cache tar file" >&2
            return 1

    elif ! tar -xf $VEP_HOME/tmp/chr${VEP_CHR}/vep_fasta_chr${VEP_CHR}.tar -C $VEP_HOME/fasta; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to decompress fasta tar file" >&2
            return 1

    elif ! rm $VEP_HOME/tmp/chr${VEP_CHR}/vep_fasta_chr${VEP_CHR}.tar; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to delete fasta tar file" >&2
            return 1

    elif ! tar -xzf $VEP_HOME/tmp/plugins.tar.gz -C $VEP_HOME/tmp/; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to decompress plugins tar" >&2
            return 1

    elif ! mv $VEP_HOME/tmp/vep_plugins/* $VEP_HOME/plugins/; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to delete plugins tar" >&2
            return 1

    elif ! mv $VEP_HOME/tmp/chr${VEP_CHR}/* $VEP_HOME/plugins/; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to move plugins to target directory" >&2
            return 1

    elif ! rename.ul "_chr${VEP_CHR}." "." $VEP_HOME/fasta/* $VEP_HOME/plugins/* ;then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to rename plugins and cache files" >&2
            return 1

    elif ! chmod -R --silent a+rwx $VEP_HOME/cache/homo_sapiens $VEP_HOME/io/ ; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to make target directory writable" >&2
            return 1

    elif ! docker load -q < $VEP_HOME/tmp/docker.tar.gz >&2 ; then

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to load docker image" >&2
            return 1

    else

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Loaded vep and its cache. Annotating a test file" >&2

    fi


    ##########
    # Test VEP
    ##########



    if ! echo -e "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n${VEP_CHR}\t1\t.\tN\tA\t.\t.\t." |\
        bgzip > "$VEP_HOME/io/test.vcf.gz"; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to create a test vcf file" >&2
        return 1


    elif ! [[ -f "$VEP_HOME/io/test.vcf.gz" ]]; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to locate test vcf file" >&2
        return 1


    elif ! annotate_vep "$VEP_HOME/io/test.vcf.gz" >&2; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to run vep on a test vcf file" >&2
        return 1

    elif [[ ! -f "$VEP_HOME/io/test.vep.tsv.gz" ]]; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to find test output file" >&2
        return 1

    elif ! mv "$VEP_HOME/io/test.vcf.gz" "$VEP_HOME/io/test.vep.tsv.gz" "$VEP_HOME/tmp/"; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to move test files to temp directory" >&2
        return 1

    elif ! rm -rf "$VEP_HOME/tmp/"; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: failed to remove temp directory" >&2
        return 1

    else

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Finished loading and testing vep docker" >&2

    fi

}