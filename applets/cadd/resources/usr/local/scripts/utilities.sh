#!/bin/bash

# Function to print STDERR message with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}


# Helper function to process a single VCF file
# Streams from DNAnexus, processes, and compresses for CADD
process_vcf_file() {
    local vcf_file_id=""
    local vcf_file_name=""
    local vcf_file_prefix=""
    local cadd_vcf_dir=""

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
    if [[ -z "$vcf_file_id" || -z "$vcf_file_name" || -z "$vcf_file_prefix" || -z "$cadd_vcf_dir" ]]; then
        log_message "ERROR: --file_id, --file_name, --file_prefix, and --output_dir are required"
        return 1
    fi

    # Remove the prefix from filename to isolate the extension part
    local vcf_file_extension="${vcf_file_name#$vcf_file_prefix}"

    # Determine file type/mode based on extension
    local mode
    case "$vcf_file_extension" in
        .vcf.gz|.vcf.bgz|.tsv.gz|.tsv.bgz)
            mode="gz"
            ;;
        .vcf.zst|.vcf.zstd|.tsv.zst|.tsv.zstd)
            mode="zst"
            ;;
        .vcf|.tsv)
            mode="vcf"
            ;;
        .bcf)
            mode="bcf"
            ;;
        *)
            log_message "INFO: Unknown file type for $vcf_file_name, defaulting to bcf"
            mode="bcf"
            ;;
    esac

    # Define CADD VCF output name
    local cadd_vcf_name="${vcf_file_prefix}.cadd${vcf_file_extension}"
    local output_path="${cadd_vcf_dir}/${cadd_vcf_name}"

    # Stream from DNAnexus based on file type
    local stream_cmd
    case "$mode" in
        gz)
            stream_cmd="dx cat \"$vcf_file_id\" | gzip -dc"
            ;;
        zst)
            stream_cmd="dx cat \"$vcf_file_id\" | zstd -dc"
            ;;
        vcf)
            stream_cmd="dx cat \"$vcf_file_id\""
            ;;
        bcf)
            stream_cmd="dx cat \"$vcf_file_id\" | bcftools view"
            ;;
        *)
            log_message "ERROR: Invalid mode: $mode"
            return 1
            ;;
    esac

    # Stream, process, and compress VCF
    eval "$stream_cmd" | \
        awk -F'\t' '/^#/{gsub(/^chrM/,"MT",$1); gsub(/^chr/,"",$1); NF=5; print} /^[^#]/{print}' OFS="\t" | \
        gzip > "$output_path"

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_message "INFO: ✓ Processed: ${cadd_vcf_name}"
        return 0
    else
        log_message "ERROR: ✗ Failed: ${cadd_vcf_name}"
        return $exit_code
    fi
}

# Function to prepare CADD input VCFs in parallel
prepare_cadd_vcfs() {
    # Usage: prepare_cadd_vcfs [--output_dir <dir>] [--max_jobs <N>]
    # Arguments:
    #   --output_dir: Output directory for processed VCFs (default: ${HOME}/input_vcfs)
    #   --max_jobs: Maximum number of parallel jobs (default: auto-detected based on CPU cores)

    local cadd_vcf_dir="${HOME}/input_vcfs"
    local max_jobs=5

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output_dir)
                cadd_vcf_dir="$2"
                shift 2
                ;;
            --max_jobs)
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

    # Create target directory
    mkdir -p "$cadd_vcf_dir"

    local vcf_count=${#input_vcfs[@]}

    if [[ $vcf_count -eq 0 ]]; then
        log_message "ERROR: No input VCFs provided"
        return 1
    fi

    # Determine number of parallel jobs based on available cores (only if not explicitly set)
    if [[ $max_jobs -eq 5 ]]; then
        local n_cores=$(nproc 2>/dev/null || echo 1)
        if [[ $n_cores -gt 6 ]]; then
            max_jobs=5
        elif [[ $n_cores -gt 1 ]]; then
            max_jobs=$((n_cores - 1))
        else
            max_jobs=1
        fi
    fi

    log_message "INFO: Processing $vcf_count VCF files in parallel (max jobs: $max_jobs)"
    log_message "INFO: Output directory: $cadd_vcf_dir"
    echo ""

    # Export variables and functions for subshells
    export cadd_vcf_dir
    export -f process_vcf_file
    export -f log_message

    # Build tab-separated data for all VCFs
    local vcf_data=()
    for (( vcf_file_idx = 0; vcf_file_idx < vcf_count; ++vcf_file_idx )); do
        # Get file ID from input array (automatically set by platform)
        local vcf_file_id=$(echo "${input_vcfs[$vcf_file_idx]}" | jq -r ."$dnanexus_link")

        # Get file name and prefix from platform arrays
        local vcf_file_name="${input_vcfs_name[$vcf_file_idx]}"
        local vcf_file_prefix="${input_vcfs_prefix[$vcf_file_idx]}"

        # Store as tab-separated values
        vcf_data+=("${vcf_file_id}\t${vcf_file_name}\t${vcf_file_prefix}")
    done

    # Process VCFs in parallel using xargs
    printf '%s\n' "${vcf_data[@]}" | \
        xargs -P "$max_jobs" -I {} bash -c 'IFS=$"\t" read -r file_id file_name file_prefix <<< "{}"; process_vcf_file --file_id "$file_id" --file_name "$file_name" --file_prefix "$file_prefix" --output_dir "$cadd_vcf_dir"'

    echo ""
    log_message "INFO: All VCF processing completed!"
    log_message "INFO: Output directory: $cadd_vcf_dir"
    echo ""

    # Build and output array of processed file paths
    for (( vcf_file_idx = 0; vcf_file_idx < vcf_count; ++vcf_file_idx )); do
        local vcf_file_name="${input_vcfs_name[$vcf_file_idx]}"
        local vcf_file_prefix="${input_vcfs_prefix[$vcf_file_idx]}"
        local vcf_file_extension="${vcf_file_name#$vcf_file_prefix}"
        local cadd_vcf_name="${vcf_file_prefix}.cadd${vcf_file_extension}"
        echo "${cadd_vcf_dir}/${cadd_vcf_name}"
    done
}

# Downloads a single file from DNAnexus while preserving directory structure
dx_download_file() {
    # Usage: dx_download_file --file_id <id> --target_dir <dir> [--dx_folder <folder>] [--remote_folder <folder>]
    # Arguments:
    #   --file_id: DNAnexus file ID to download (required)
    #   --target_dir: Local target directory (required)
    #   --dx_folder: Base remote folder path (optional, used for path mapping)
    #                Supports formats: "/path" or "project-id:/path"
    #   --remote_folder: Specific remote folder for this file (optional, used with dx_folder)
    #                    Supports formats: "/path" or "project-id:/path"
    #
    # Path Format Handling:
    #   Automatically strips "project-id:" or "project-name:" prefixes from paths before mapping.
    #   Examples of equivalent inputs:
    #     --dx_folder "/data" --remote_folder "/data/subdir"
    #     --dx_folder "project-xxx:/data" --remote_folder "/data/subdir"
    #     --dx_folder "/data" --remote_folder "project-xxx:/data/subdir"
    #     --dx_folder "project-xxx:/data" --remote_folder "project-yyy:/data/subdir"
    #   All map to: target_dir/subdir

    local file_id=""
    local target_dir=""
    local dx_folder=""
    local remote_folder=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file_id)
                file_id="$2"
                shift 2
                ;;
            --target_dir)
                target_dir="$2"
                shift 2
                ;;
            --dx_folder)
                dx_folder="$2"
                shift 2
                ;;
            --remote_folder)
                remote_folder="$2"
                shift 2
                ;;
            *)
                log_message "ERROR: Unknown argument: $1"
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$file_id" || -z "$target_dir" ]]; then
        log_message "ERROR: --file_id and --target_dir are required"
        return 1
    fi

    # Strip project prefix from paths if present (handles "project-id:/path" format)
    # This ensures clean path mapping regardless of input format
    local dx_folder_clean="$dx_folder"
    local remote_folder_clean="$remote_folder"

    if [[ "$dx_folder" =~ ^[^:]+:(.*)$ ]]; then
        dx_folder_clean="${BASH_REMATCH[1]}"
    fi

    if [[ "$remote_folder" =~ ^[^:]+:(.*)$ ]]; then
        remote_folder_clean="${BASH_REMATCH[1]}"
    fi

    # Determine local folder based on path mapping
    local local_folder="$target_dir"
    if [[ -n "$dx_folder_clean" && -n "$remote_folder_clean" ]]; then
        # Strip the base folder from remote folder to get relative path
        local relative_path="${remote_folder_clean#$dx_folder_clean}"
        # Remove leading slash from relative path if present
        relative_path="${relative_path#/}"
        # Construct final local folder path
        if [[ -n "$relative_path" ]]; then
            local_folder="${target_dir}/${relative_path}"
        else
            local_folder="$target_dir"
        fi
    fi

    # Ensure directory exists
    mkdir -p "$local_folder"

    # Download file with optimized flags
    local result
    result=$(dx download --overwrite --lightweight --no-progress --brief "$file_id" -o "$local_folder/" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_message "INFO: ✓ Downloaded: $result"
        return 0
    else
        log_message "ERROR: ✗ Failed [$file_id]: $result"
        return $exit_code
    fi
}




# Function to download files from DNAnexus in parallel
dx_parallel_download() {
    # Usage: dx_parallel_download --dx_project PROJECT-ID --dx_folder /remote/path --target_dir /local/path
    # Arguments:
    #   --dx_project: DNAnexus project ID containing the files to download (required).
    #   --dx_folder: Remote folder path in the DNAnexus project (required).
    #                Supports both formats: "/path" or "project-id:/path"
    #   --target_dir: Local directory to download files into (required).
    #   --max_jobs: Maximum number of parallel jobs (default: 5).
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
    local max_jobs=5

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
            --max_jobs)
                max_jobs="$2"
                shift 2
                ;;
            *)
                log_message "ERROR: Unknown option: $1"
                log_message "Usage: dx_parallel_download --dx_project PROJECT-ID --dx_folder /remote/path --target_dir /local/path [--max_jobs N]"
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

    # Normalize dx_folder by stripping any project prefix (e.g., "project-xxx:/path" -> "/path")
    # This ensures consistent path handling throughout the function
    local dx_folder_for_find="$dx_folder"  # Keep original for dx find command
    local dx_folder_normalized="$dx_folder"

    if [[ "$dx_folder" =~ ^[^:]+:(.*)$ ]]; then
        dx_folder_normalized="${BASH_REMATCH[1]}"
    fi

    # Determine number of parallel jobs based on available cores (only if not explicitly set)
    if [[ $max_jobs -eq 5 ]]; then
        local n_cores=$(nproc 2>/dev/null || echo 1)
        if [[ $n_cores -gt 6 ]]; then
            max_jobs=5
        elif [[ $n_cores -gt 1 ]]; then
            max_jobs=$((n_cores - 1))
        else
            max_jobs=1
        fi
    fi

    log_message "INFO: Starting parallel download"
    log_message "INFO: Project: $dx_project"
    log_message "INFO: Remote folder: $dx_folder"
    log_message "INFO: Target directory: $target_dir"
    log_message "INFO: Parallel jobs: $max_jobs"
    echo ""

    # Get all files in JSON format
    log_message "INFO: Fetching file list from DNAnexus..."
    # Use normalized path for dx find (without project prefix since we specify it separately)
    local json_data=$(dx find data --path "${dx_project}:${dx_folder_normalized}" --class file --json)

    if [[ -z "$json_data" ]]; then
        log_message "ERROR: No files found or failed to retrieve data"
        return 1
    fi

    # Count total files
    local total_files=$(echo "$json_data" | jq 'length')
    log_message "INFO: Found $total_files files to download"
    echo ""

    # Download files in parallel using xargs
    log_message "INFO: Starting downloads with $max_jobs parallel jobs..."

    # Export normalized path and variables for use in subshells
    # The normalized path ensures consistent path mapping without project prefixes
    export dx_folder_normalized
    export target_dir
    export -f log_message

    # Use xargs to download files in parallel
    echo "$json_data" | jq -r '.[] | "\(.id)\t\(.describe.folder)"' | \
        xargs -P "$max_jobs" -I {} bash -c 'IFS=$"\t" read -r file_id remote_folder <<< "{}"; dx_download_file --file_id "$file_id" --target_dir "$target_dir" --dx_folder "$dx_folder_normalized" --remote_folder "$remote_folder"'

    echo ""
    log_message "INFO: All downloads completed!"
    log_message "INFO: Files downloaded to: $target_dir"
}