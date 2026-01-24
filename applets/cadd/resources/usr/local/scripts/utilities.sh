# Function to print STDERR message with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Function to read and validate input parameters from job_input.json
get_input_param() {

# Read inputs and set up environment
CADD_DATA_PROJECT=$(cat ${HOME}/job_input.json  | jq -r '.cadd_dir_project' || echo "null" )
CADD_DATA_DIR=$(cat ${HOME}/job_input.json  | jq -r '.cadd_dir_path' || echo "null" )
CADD_JOBS=$(cat ${HOME}/job_input.json  | jq -r '.cadd_jobs' || echo "null" )
CADD_TIMEOUT=$(cat ${HOME}/job_input.json  | jq -r '.cadd_timeout' || echo "null" )

# Read input VCFs from job input

# Expected formats: 
# cadd_input=('{"$dnanexus_link": "file-J1gJGKjJZz4kYvZYbkGZ0F84"}' '{"$dnanexus_link": "file-J1gJGG8JZz4kbvGgYx7y7FBX"}')
# cadd_input_name=("sample1.vcf.gz" "sample2.vcf.gz")
# cadd_input_prefix=("sample1" "sample2")

CADD_VCF_IDS=()
CADD_VCF_NAMES=()
CADD_VCF_PREFIXES=()

# Each element is a JSON string that needs to be parsed to extract the file ID
local item
local file_id
for item in "${cadd_input[@]}"; do file_id=$(jq -r '."$dnanexus_link"' <<< "$item"); CADD_VCF_IDS+=("$file_id"); done
CADD_VCF_NAMES=("${cadd_input_name[@]}")
CADD_VCF_PREFIXES=("${cadd_input_prefix[@]}")


# Set CADD working directory
CADD_WD="${HOME}/CADD"


# Validate CADD data project
if [[ "$CADD_DATA_PROJECT" == "null" || -z "$CADD_DATA_PROJECT" ]]; then
	log_message "WARNING: CADD data project not specified. Using current project $DX_PROJECT_CONTEXT_ID"
	CADD_DATA_PROJECT="$DX_PROJECT_CONTEXT_ID"
fi

# Validate CADD data directory
if [[ "$CADD_DATA_DIR" == "null" || -z "$CADD_DATA_DIR" ]]; then
	log_message "WARNING: CADD data directory not specified. Using default /Resources/cadd_v1_7_data"
	CADD_DATA_DIR="/Resources/cadd_v1_7_data"
fi

# Validate CADD_JOBS
if [[ "$CADD_JOBS" == "null" || -z "$CADD_JOBS" ]] || ! [[ "$CADD_JOBS" =~ ^[0-9]+$ ]] || [[ "$CADD_JOBS" -le 0 ]]; then
	log_message "WARNING: Number of CADD parallel jobs not specified or invalid. Auto-calculated from available memory"
	CADD_JOBS=$(($(free -g | awk '/^Mem:/{print $2}') / 8))
	CADD_JOBS=$((CADD_JOBS > 0 ? CADD_JOBS : 1))
fi

# Validate CADD_TIMEOUT
if [[ "$CADD_TIMEOUT" == "null" || -z "$CADD_TIMEOUT" ]] || ! [[ "$CADD_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$CADD_TIMEOUT" -le 0 ]]; then
	log_message "WARNING: CADD timeout not specified or invalid. Using default 3600 seconds"
	CADD_TIMEOUT=3600
fi

# Validate CADD data directory in DNAnexus
if ! dx ls --brief "$CADD_DATA_PROJECT:$CADD_DATA_DIR" &> /dev/null; then
	log_message "ERROR: CADD data directory $CADD_DATA_DIR not found in project $CADD_DATA_PROJECT"
	exit 1
fi

# Validate input VCFs
if [[ ${#CADD_VCF_IDS[@]} -eq 0 ]]; then
    log_message "ERROR: No input VCFs provided for CADD scoring"
    exit 1
fi

# Validate matching lengths of input arrays
if [[ "${#CADD_VCF_NAMES[@]}" -ne "${#CADD_VCF_IDS[@]}" ]]; then
    log_message "ERROR: Mismatch between CADD_VCF_IDS and CADD_VCF_NAMES array lengths"
    exit 1
fi

# Validate matching lengths of input arrays
if [[ "${#CADD_VCF_PREFIXES[@]}" -ne "${#CADD_VCF_IDS[@]}" ]]; then
    log_message "ERROR: Mismatch between CADD_VCF_PREFIXES and CADD_VCF_IDS array lengths"
    exit 1
else

    # Export scalar variables to global env (these work across subshells)
    export CADD_DATA_PROJECT
    export CADD_DATA_DIR
    export CADD_JOBS
    export CADD_TIMEOUT
    export CADD_WD

    # Arrays cannot be exported across runuser/subshells - serialize to files instead
    mkdir -p "${CADD_WD}"
    chown dnanexus:dnanexus "${CADD_WD}"
    printf '%s\n' "${CADD_VCF_IDS[@]}" > "${CADD_WD}/.vcf_ids"
    printf '%s\n' "${CADD_VCF_NAMES[@]}" > "${CADD_WD}/.vcf_names"
    printf '%s\n' "${CADD_VCF_PREFIXES[@]}" > "${CADD_WD}/.vcf_prefixes"

    # Log validated parameters
    log_message "INFO: CADD LOCAL DIR = $CADD_WD"
    log_message "INFO: CADD DATA DIR = $CADD_DATA_PROJECT:$CADD_DATA_DIR"
    log_message "INFO: CADD JOBS = $CADD_JOBS"
    log_message "INFO: CADD TIMEOUT = $CADD_TIMEOUT"
    log_message "INFO: Input VCF files to process:"
    printf "%-40s %s\n" "FILE NAME" "FILE ID" >&2
    printf "%-40s %s\n" "----------------------------------------" "------------------------" >&2
    for i in "${!CADD_VCF_IDS[@]}"; do
        printf "%-40s %s\n" "${CADD_VCF_NAMES[$i]}" "${CADD_VCF_IDS[$i]}" >&2
    done

fi

}


# Helper function to process a single VCF file. Streams from DNAnexus, processes, and compresses for CADD
process_vcf_file() {
    local vcf_file_id=""
    local vcf_file_name=""
    local vcf_file_prefix=""
    local cadd_vcf_dir=""
    local vcf_file_extension=""
    local mode
    local cadd_vcf_name=""
    local output_path=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file_id)
                vcf_file_id="$2"
                shift 2
                ;;
            --file_name)
                vcf_file_name="$2"
                shift 2
                ;;
            --file_prefix)
                vcf_file_prefix="$2"
                shift 2
                ;;
            --output_dir)
                cadd_vcf_dir="$2"
                shift 2
                ;;
            *)
                log_message "ERROR: Unknown argument: $1"
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$vcf_file_id" ]]; then
        log_message "ERROR: --file_id is required"
        return 1
    fi
    if [[ -z "$vcf_file_name" ]]; then
        log_message "ERROR: --file_name is required"
        return 1
    fi
    if [[ -z "$vcf_file_prefix" ]]; then
        log_message "ERROR: --file_prefix is required"
        return 1
    fi
    if [[ -z "$cadd_vcf_dir" ]]; then
        log_message "ERROR: --output_dir is required"
        return 1
    fi

    # Remove the prefix from filename to isolate the extension part
    vcf_file_extension="${vcf_file_name#$vcf_file_prefix}"

    # Determine file type/mode based on extension
    case "$vcf_file_extension" in
        .vcf.gz|.vcf.bgz|.tsv.gz|.tsv.bgz|.pvar.gz|.pvar.bgz|.txt.gz|.txt.bgz)
            mode="gz"
            ;;
        .vcf.zst|.vcf.zstd|.tsv.zst|.tsv.zstd|.pvar.zst|.pvar.zstd|.txt.zst|.txt.zstd)
            mode="zst"
            ;;
        .vcf|.tsv|.pvar|.txt)
            mode="vcf"
            ;;
        .bcf|.bcf.gz|.bcf.bgz)
            mode="bcf"
            ;;
        *)
            log_message "WARNING: Unknown file type for $vcf_file_name, defaulting to vcf/bcf"
            mode="bcf"
            ;;
    esac

    # Define CADD VCF output name
    cadd_vcf_name="${vcf_file_prefix}.cadd.vcf.gz"
    output_path="${cadd_vcf_dir}/${cadd_vcf_name}"

    # Helper function to process stream: normalize chromosomes, extract first 5 columns, compress
    process_and_compress() {
        awk 'BEGIN{OFS="\t"; print "##fileformat=VCFv4.2"; print "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"} \
             !/^#/{gsub(/^chrM/,"MT",$1); gsub(/^chr/,"",$1); print $1,$2,$3,$4,$5,".",".","." }' | \
            bcftools view -Oz --write-index -o "$output_path"
    }

    # Stream from DNAnexus based on file type and process
    case "$mode" in
        gz)
            dx cat "$vcf_file_id" | gzip -dc | process_and_compress
            ;;
        zst)
            dx cat "$vcf_file_id" | zstd -dc | process_and_compress
            ;;
        vcf)
            dx cat "$vcf_file_id" | process_and_compress
            ;;
        bcf)
            dx cat "$vcf_file_id" | bcftools view | process_and_compress
            ;;
        *)
            log_message "ERROR: Invalid mode: $mode"
            return 1
            ;;
    esac

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_message "INFO: Successfully processed: ${cadd_vcf_name}"
        return 0
    else
        log_message "ERROR: Failed to process: ${cadd_vcf_name}"
        return $exit_code
    fi
}

# Function to prepare CADD input VCFs in parallel
prepare_cadd_vcfs() {
    # Usage: prepare_cadd_vcfs [--output_dir <dir>] [--dx_jobs <N>]
    # Arguments:
    #   --output_dir: Output directory for processed VCFs (default: ${HOME}/CADD/input_vcfs)
    #   --dx_jobs: Maximum number of parallel dx cat jobs (default: auto-detected based on CPU cores)

    # Check that input VCF directory exists
    if [[ ! -d "${CADD_WD}/input_vcfs" ]]; then
        log_message "ERROR: CADD input VCF directory ${CADD_WD}/input_vcfs does not exist"
        exit 1
    fi

    # Declare all local variables
    local cadd_vcf_dir
    local max_jobs
    local n_cores
    local input_ids=()
    local input_names=()
    local input_prefixes=()
    local input_count
    local vcf_file_idx
    local vcf_file_id
    local cadd_vcf_name
    local output_path

    # Set default parameters
    cadd_vcf_dir="${CADD_WD}/input_vcfs"
    max_jobs=0


    # Parse arguments and update variables if provided
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output_dir)
                cadd_vcf_dir="$2"
                shift 2
                ;;
            --dx_jobs)
                max_jobs="$2"
                shift 2
                ;;
            *)
                log_message "ERROR: Unknown argument: $1"
                log_message "Usage: prepare_cadd_vcfs [--output_dir <dir>] [--max_jobs <N>]"
                return 1
                ;;
        esac
    done

    # Determine number of parallel jobs based on available cores (only if not explicitly set)
    if [[ $max_jobs -eq 0 ]]; then
        n_cores=$(nproc 2>/dev/null || echo 1)
        if [[ $n_cores -gt 11 ]]; then
            max_jobs=10
        elif [[ $n_cores -gt 2 ]]; then
            max_jobs=$((n_cores - 1))
        else
            max_jobs=1
        fi
    fi




    # Read arrays from serialized files (arrays can't be exported across runuser)
    if [[ -f "${CADD_WD}/.vcf_ids" ]]; then
        mapfile -t input_ids < "${CADD_WD}/.vcf_ids"
    fi
    if [[ -f "${CADD_WD}/.vcf_names" ]]; then
        mapfile -t input_names < "${CADD_WD}/.vcf_names"
    fi
    if [[ -f "${CADD_WD}/.vcf_prefixes" ]]; then
        mapfile -t input_prefixes < "${CADD_WD}/.vcf_prefixes"
    fi

    input_count=${#input_ids[@]}

    # Validate that we have input files and all arrays match
    if [[ $input_count -eq 0 ]]; then
        log_message "ERROR: No input VCFs provided"
        return 1
    elif [[ ${#input_names[@]} -ne $input_count ]]; then
        log_message "ERROR: Mismatch between input_ids (${input_count}) and input_names (${#input_names[@]})"
        return 1
    elif [[ ${#input_prefixes[@]} -ne $input_count ]]; then
        log_message "ERROR: Mismatch between input_ids (${input_count}) and input_prefixes (${#input_prefixes[@]})"
        return 1
    fi


    log_message "INFO: Processing $input_count VCF files in parallel (max streaming jobs: $max_jobs)"
    log_message "INFO: Output directory: $cadd_vcf_dir"

    # Export variables and functions for subshells
    export cadd_vcf_dir
    export -f process_vcf_file
    export -f log_message

    # Create temporary files to store array data for parallel processing
    local tmp_ids="${cadd_vcf_dir}/.tmp_ids_$$"
    local tmp_names="${cadd_vcf_dir}/.tmp_names_$$"
    local tmp_prefixes="${cadd_vcf_dir}/.tmp_prefixes_$$"

    printf '%s\n' "${input_ids[@]}" > "$tmp_ids"
    printf '%s\n' "${input_names[@]}" > "$tmp_names"
    printf '%s\n' "${input_prefixes[@]}" > "$tmp_prefixes"

    # Process VCFs in parallel using xargs with line-by-line matching
    log_message "INFO: VCF processing started ..."

    # Process files in parallel using paste to combine the three files line-by-line
    paste "$tmp_ids" "$tmp_names" "$tmp_prefixes" | \
        xargs -P "$max_jobs" -I {} bash -c '
            read -r file_id file_name file_prefix <<< "{}"
            process_vcf_file \
                --file_id "$file_id" \
                --file_name "$file_name" \
                --file_prefix "$file_prefix" \
                --output_dir "$cadd_vcf_dir"
        '

    # Clean up temporary files
    rm -f "$tmp_ids" "$tmp_names" "$tmp_prefixes"
    


    # Build and output array of processed file paths
    # Check that each processed file exists before echoing its path

    for (( vcf_file_idx = 0; vcf_file_idx < input_count; ++vcf_file_idx )); do
        cadd_vcf_name="${input_prefixes[$vcf_file_idx]}.cadd.vcf.gz"
        output_path="${cadd_vcf_dir}/${cadd_vcf_name}"

        # Return the path only if the file exists
        if [[ -f "$output_path" ]]; then
            echo "$cadd_vcf_name"
        else
            log_message "WARNING: Processed file not found: $output_path"
        fi
    done
}

# Downloads a single file from DNAnexus while preserving directory structure
dx_download_file() {
    # Usage: dx_download_file --dx_file_id <id> --dx_directory_path <path> --local_directory <dir> [--strip_prefix <prefix>]
    #
    # Arguments:
    #   --dx_file_id: DNAnexus file ID to download (e.g., "file-xxx") [required]
    #   --dx_directory_path: Remote file's directory path in DNAnexus [required]
    #                        Supports formats: "/path", "/path/", "project-id:/path", "project-id:path"
    #   --local_directory: Local base directory for downloads [required]
    #   --strip_prefix: Optional prefix to remove from dx_directory_path before constructing local path
    #                   Example: if dx_directory_path="/data/cadd/annotations" and strip_prefix="/data/cadd"
    #                   then local path will be "${local_directory}/annotations"
    #
    # The function downloads the file and preserves the directory structure from dx_directory_path

    # Declare all local variables
    local dx_file_id=""
    local dx_directory_path=""
    local local_directory=""
    local strip_prefix=""
    local dx_path_clean=""
    local local_file_path=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dx_file_id)
                dx_file_id="$2"
                shift 2
                ;;
            --dx_directory_path)
                dx_directory_path="$2"
                shift 2
                ;;
            --local_directory)
                local_directory="$2"
                shift 2
                ;;
            --strip_prefix)
                strip_prefix="$2"
                shift 2
                ;;
            *)
                log_message "ERROR: Unknown argument: $1"
                log_message "Usage: dx_download_file --dx_file_id <id> --dx_directory_path <path> --local_directory <dir> [--strip_prefix <prefix>]"
                return 1
                ;;
        esac
    done

    # Validate all required arguments
    if [[ -z "$dx_file_id" ]]; then
        log_message "ERROR: --dx_file_id is required"
        return 1
    elif [[ -z "$dx_directory_path" ]]; then
        log_message "ERROR: --dx_directory_path is required"
        return 1
    elif [[ -z "$local_directory" ]]; then
        log_message "ERROR: --local_directory is required"
        return 1
    fi

    # Clean the dx_directory_path:
    # 1. Strip "project-id:" or "project-name:" prefix if present
    # 2. Ensure it starts with "/"
    # 3. Remove trailing "/" if present
    # 4. Strip custom prefix (default: empty, which removes nothing)
    dx_path_clean="$dx_directory_path"

    # Remove project prefix (handles "project-xxx:/path" or "project-xxx:path")
    if [[ "$dx_path_clean" =~ ^[^:]+:(.*)$ ]]; then
        dx_path_clean="${BASH_REMATCH[1]}"
    fi

    # Ensure leading slash
    if [[ ! "$dx_path_clean" =~ ^/ ]]; then
        dx_path_clean="/$dx_path_clean"
    fi

    # Remove trailing slash
    dx_path_clean="${dx_path_clean%/}"

    # Normalize strip_prefix: ensure leading slash, remove trailing slash
    local prefix_normalized="$strip_prefix"
    if [[ -n "$prefix_normalized" ]]; then
        if [[ ! "$prefix_normalized" =~ ^/ ]]; then
            prefix_normalized="/$prefix_normalized"
        fi
        prefix_normalized="${prefix_normalized%/}"
    fi

    # Strip the prefix (if empty, this removes nothing)
    dx_path_clean="${dx_path_clean#$prefix_normalized}"

    # Ensure resulting path has leading slash if not empty
    if [[ -n "$dx_path_clean" && ! "$dx_path_clean" =~ ^/ ]]; then
        dx_path_clean="/$dx_path_clean"
    fi

    # Construct local folder path by appending cleaned dx path to local directory
    local_file_path="${local_directory}${dx_path_clean}"

    # Ensure directory exists
    mkdir -p "$local_file_path"

    # Download file with optimized flags

    if ! dx download --overwrite --lightweight --no-progress "$dx_file_id" -o "$local_file_path/" > /dev/null 2>&1 ; then
        log_message "ERROR: Failed to download file $dx_file_id"
        return 1
    fi
}

# Function to download files from DNAnexus in parallel
dx_parallel_download() {
    # Usage: dx_parallel_download --dx_project PROJECT-ID --dx_folder /remote/path --target_dir /local/path [--strip_prefix <prefix>]
    # Arguments:
    #   --dx_project: DNAnexus project ID containing the files to download (required).
    #   --dx_folder: Remote folder path in the DNAnexus project (required).
    #                Supports both formats: "/path" or "project-id:/path"
    #   --target_dir: Local directory to download files into (required).
    #   --max_jobs: Maximum number of parallel jobs (default: auto-detected).
    #   --strip_prefix: Optional prefix to strip from remote paths before creating local paths.
    #                   Example: --strip_prefix "/Resources/cadd_v1_7_data"
    #
    # Path Format Handling:
    #   This function automatically strips "project-id:" prefixes when mapping remote paths
    #   to local directories. All of these work correctly:
    #     --dx_folder "/data/files"
    #     --dx_folder "project-xxx:/data/files"
    #     --dx_folder "project-name:/data/files"


    local dx_project=""
    local dx_folder=""
    local target_dir=""
    local strip_prefix=""
    local max_jobs
    local n_cores
    local dx_folder_normalized=""
    local json_data=""
    local total_files=""
    local tmp_file_ids
    local tmp_folders


    # Set default parameters
    max_jobs=0


    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dx_project)
                dx_project="$2"
                shift 2
                ;;
            --dx_folder)
                dx_folder="$2"
                shift 2
                ;;
            --target_dir)
                target_dir="$2"
                shift 2
                ;;
            --strip_prefix)
                strip_prefix="$2"
                shift 2
                ;;
            --max_jobs)
                max_jobs="$2"
                shift 2
                ;;
            *)
                log_message "ERROR: Unknown option: $1"
                log_message "Usage: dx_parallel_download --dx_project PROJECT-ID --dx_folder /remote/path --target_dir /local/path [--strip_prefix <prefix>] [--max_jobs N]"
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$dx_project" || -z "$dx_folder" || -z "$target_dir" ]]; then
        log_message "ERROR: Missing required arguments"
        log_message "Usage: dx_parallel_download --dx_project PROJECT-ID --dx_folder /remote/path --target_dir /local/path [--max_jobs N]"
        return 1
    fi

    # Clean the dx_folder path:
    # 1. Strip "project-id:" or "project-name:" prefix if present
    # 2. Ensure it starts with "/"
    # 3. Remove trailing "/" if present
    dx_folder_normalized="$dx_folder"

    # Remove project prefix (handles "project-xxx:/path" or "project-xxx:path")
    if [[ "$dx_folder_normalized" =~ ^[^:]+:(.*)$ ]]; then
        dx_folder_normalized="${BASH_REMATCH[1]}"
    fi

    # Ensure leading slash
    if [[ ! "$dx_folder_normalized" =~ ^/ ]]; then
        dx_folder_normalized="/$dx_folder_normalized"
    fi

    # Remove trailing slash
    dx_folder_normalized="${dx_folder_normalized%/}"

    # Determine number of parallel jobs based on available cores (only if not explicitly set)
    if [[ $max_jobs -eq 0 ]]; then
        
        n_cores=$(nproc 2>/dev/null || echo 1)
        
        if [[ $n_cores -gt 16 ]]; then
            max_jobs=15
        elif [[ $n_cores -gt 2 ]]; then
            max_jobs=$((n_cores - 1))
        else
            max_jobs=1
        fi
    fi

    # Get all files in JSON format
    log_message "INFO: Fetching CADD data from DNAnexus..."
    # Use normalized path for dx find (without project prefix since we specify it separately)
    json_data=$(dx find data --path "${dx_project}:${dx_folder_normalized}" --class file --json)

    # Validate that we have files to download
    if [[ -z "$json_data" ]] || [[ $(echo "$json_data" | jq 'length') -eq 0 ]]; then
        log_message "ERROR: No files found or failed to retrieve data"
        return 1
    fi

    # Count total files
    total_files=$(echo "$json_data" | jq 'length')
    log_message "INFO: Found $total_files files to download"

    # Download files in parallel using xargs
    log_message "INFO: Starting downloads with $max_jobs parallel jobs..."
    log_message "INFO: Remote folder: $dx_project:$dx_folder"
    log_message "INFO: Target directory: $target_dir"

    # Export variables and functions for use in subshells
    export target_dir
    export strip_prefix
    export -f dx_download_file
    export -f log_message

    # Create temporary files to store file IDs and folders separately

    tmp_file_ids="${target_dir}/dx_file_ids.list"
    tmp_folders="${target_dir}/dx_folders.list"

    echo "$json_data" | jq -r '.[].id' > "$tmp_file_ids"
    echo "$json_data" | jq -r '.[].describe.folder' > "$tmp_folders"

    # Use xargs to download files in parallel using paste to combine IDs and folders
    paste "$tmp_file_ids" "$tmp_folders" | \
        xargs -P "$max_jobs" -I {} bash -c '
            read -r file_id remote_folder <<< "{}"
            dx_download_file --dx_file_id "$file_id" --dx_directory_path "$remote_folder" --local_directory "$target_dir" --strip_prefix "$strip_prefix"
        '

    # Clean up temporary files
    rm -f "$tmp_file_ids" "$tmp_folders"

    log_message "INFO: Files downloaded to: $target_dir"
}


# Wrapper function to deploy CADD locally

deploy_cadd_locally() {
    local input_vcfs_list=()

    if ! mkdir -p "${CADD_WD}/input_vcfs" "${CADD_WD}/parallel_dir"; then
        log_message "ERROR: Failed to create CADD input and parallel directories"
        return 1
    # Prepare CADD input VCFs
    elif ! prepare_cadd_vcfs > "${CADD_WD}/parallel_dir/input_vcfs.txt"; then
        log_message "ERROR: Failed to prepare CADD input VCFs"
        return 1
    # Validate that input VCF file was prepared
    elif ! mapfile -t input_vcfs_list < "${CADD_WD}/parallel_dir/input_vcfs.txt"; then
        log_message "ERROR: Failed to read input VCF filenames into array"
        return 1
    # Validate that input VCFs array has elements
    elif [[ ${#input_vcfs_list[@]} -eq 0 ]]; then
        log_message "ERROR: No input VCF files found for CADD processing"
        return 1
    # Download CADD data directory from DNAnexus
    elif ! dx_parallel_download \
        --dx_project "${CADD_DATA_PROJECT}" \
        --dx_folder "${CADD_DATA_DIR}" \
        --strip_prefix "${CADD_DATA_DIR}" \
        --target_dir "${CADD_WD}"; then
        log_message "ERROR: Failed to download CADD data directory"
        return 1
    # Test run of CADD-scripts from singularity container
    elif ! singularity exec \
        --writable-tmpfs \
        --bind "${CADD_WD}"/annotations:/opt/CADD/data/annotations \
        --bind "${CADD_WD}"/prescored:/opt/CADD/data/prescored \
        --bind "${CADD_WD}"/containers:/opt/CADD/src/sif \
        "${CADD_WD}"/containers/CADD_scripts_v1_7.sif \
        bash -c 'set -e; run_cadd -c2 /opt/CADD/test/input.vcf.gz && test -s /opt/CADD/test/input.tsv.gz'; then
        log_message "ERROR: Test run of CADD-scripts from singularity container failed"
        return 1
    else
        # All steps completed successfully 
        log_message "INFO: CADD setup and test run completed successfully"
    fi
}


run_cadd_on_input_vcfs() {

    singularity exec \
        --writable-tmpfs \
        --bind "${CADD_WD}"/parallel_dir:/opt/CADD/parallel_dir \
        --bind "${CADD_WD}"/input_vcfs:/opt/CADD/input_vcfs \
        --bind "${CADD_WD}"/annotations:/opt/CADD/data/annotations \
        --bind "${CADD_WD}"/prescored:/opt/CADD/data/prescored \
        --bind "${CADD_WD}"/containers:/opt/CADD/src/sif \
        "${CADD_WD}"/containers/CADD_scripts_v1_7.sif \
        parallel \
            --jobs "$CADD_JOBS" \
            --timeout "$CADD_TIMEOUT" \
            --memfree 8G \
            --retries 3 \
            --results /opt/CADD/parallel_dir \
            --joblog /opt/CADD/parallel_dir/parallel.log \
            run_cadd -p -c4 /opt/CADD/input_vcfs/{} \
            :::: /opt/CADD/parallel_dir/input_vcfs.txt

}

collect_cadd_output_files() {

	local input_vcfs_list=() 
	local idx
	local input_file
	local tsv_file
	local scores_file
	local log_file
	local retries
	local retry_num


if [[ ! -f "${CADD_WD}/parallel_dir/parallel.log" ]]; then

	log_message "ERROR: parallel.log file not found"
	return 1

elif ! mapfile -t input_vcfs_list < "${CADD_WD}/parallel_dir/input_vcfs.txt" ; then

	log_message "ERROR: Could not read input list"
	return 1

elif ! mkdir -p "${HOME}/out/cadd_summary_log/" "${HOME}/out/cadd_scores/" "${HOME}/out/cadd_logs/"; then

   log_message "ERROR: Failed to create output directories"
    return 1

fi

# Create summary log

(
	echo "CADD Parallel Jobs Summary"
	echo "=========================="
	echo ""
	awk -F"\t" 'BEGIN {
		printf "%-8s %-40s %-12s %-10s %-10s\n", "Job", "Filename", "Runtime(min)", "Status", "ExitCode"
		printf "%-8s %-40s %-12s %-10s %-10s\n", "--------", "----------------------------------------", "------------", "----------", "----------"
	}
	NR==1 {next}
	{
		# Job number is in column 1
		job_num = $1
		# Extract filename from field 9 (or last field with $NF)
		arg = $9
		# Remove leading/trailing whitespace
		gsub(/^[ \t]+|[ \t]+$/, "", arg)
		# Extract just the filename from the path
		split(arg, path, "/")
		filename = path[length(path)]
		# Calculate runtime in minutes (column 4)
		runtime = $4 / 60
		# Determine pass/fail status (column 7)
		status = ($7 == 0) ? "PASS" : "FAIL"
		# Exit code is in column 7
		exit_code = $7
		# Print formatted table row
		printf "%-8s %-40s %-12.2f %-10s %-10d\n", job_num, filename, runtime, status, exit_code
	}' "${CADD_WD}/parallel_dir/parallel.log"

) >  "${HOME}/out/cadd_summary_log/CADD-${DX_JOB_ID}.log"


# Move TSV files and logs to output directories

# Read input VCF filenames into an array
for ((idx=0; idx < ${#input_vcfs_list[@]}; ++idx)); do
	# Create output subdirectories

	# Get the input filename without path
	input_file="${input_vcfs_list[$idx]}"
	

	# Check for TSV file, and move to destination if present	
	tsv_file="${CADD_WD}/input_vcfs/${input_file%.vcf.gz}.tsv.gz"
	scores_file="${HOME}/out/cadd_scores/${input_file%.vcf.gz}.tsv.gz"

	if [[ -f "$tsv_file" ]]; then
		# Move CADD TSV output to scores directory
		mv "$tsv_file" "$scores_file"
	else
		log_message "WARNING: CADD output TSV file not found: ${tsv_file}"
	fi

	# Concatenate stdout and stderr into a single log file named after the input
	# Parallel results are stored by retry attempt number (1 for first attempt, 2 for retry, etc.)
	# Directory structure: parallel_dir/{retry_num}/_path_with_underscores/stdout

    # Define log file path
	log_file="${HOME}/out/cadd_logs/${input_file%.vcf.gz}.log"
	# find out how many retries did CADD attempt
	retries=$(ls -ld ${CADD_WD}/parallel_dir/[0-9]* 2> /dev/null | grep '^d' | wc -l | awk '{print $1}' || echo 1)

	# Try to find the log in retry directories (1 for first attempt, 2+ for retries)
	for ((retry_num=1;retry_num <= retries; ++retry_num)); do
		if [[ -f "${CADD_WD}/parallel_dir/${retry_num}/${input_file}/stderr" ]]; then
			{
				echo "CADD Log ${retry_num} for ${input_file}"
				echo "================================"
				echo ""
				echo "==== STDOUT ===="
					cat "${CADD_WD}/parallel_dir/${retry_num}/${input_file}/stdout"
				echo ""
				echo "==== STDERR ===="
					cat "${CADD_WD}/parallel_dir/${retry_num}/${input_file}/stderr"
			} >> "$log_file"
		fi
	done

	# Check if there is at least one log file
	if [[ ! -f "$log_file" ]]; then
		echo "WARNING: No parallel output found for ${input_file}" > "$log_file"
		log_message "WARNING: No parallel output found for ${input_file}"
	fi

done


}
