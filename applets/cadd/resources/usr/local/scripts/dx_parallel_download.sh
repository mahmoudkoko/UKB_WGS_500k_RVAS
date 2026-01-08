#!/bin/bash

# Function to download files from DNAnexus in parallel
# Usage: dx_parallel_download --dx_project PROJECT-ID --dx_folder /remote/path --target_dir /local/path
dx_parallel_download() {
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
            *)
                echo "Unknown option: $1"
                echo "Usage: dx_parallel_download --dx_project PROJECT-ID --dx_folder /remote/path --target_dir /local/path"
                return 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$dx_project" || -z "$dx_folder" || -z "$target_dir" ]]; then
        echo "Error: Missing required arguments"
        echo "Usage: dx_parallel_download --dx_project PROJECT-ID --dx_folder /remote/path --target_dir /local/path"
        return 1
    fi

    # Determine number of parallel jobs based on available cores
    local n_cores=$(nproc 2>/dev/null || echo 1)
    if [[ $n_cores -gt 6 ]]; then
        max_jobs=5
    elif [[ $n_cores -gt 1 ]]; then
        max_jobs=$((n_cores - 1))
    else
        max_jobs=1
    fi

    echo "Starting parallel download..."
    echo "Project: $dx_project"
    echo "Remote folder: $dx_folder"
    echo "Target directory: $target_dir"
    echo "Parallel jobs: $max_jobs"
    echo ""

    # Get all files in JSON format
    echo "Fetching file list from DNAnexus..."
    local json_data=$(dx find data --path "${dx_project}:${dx_folder}" --class file --json)

    if [[ -z "$json_data" ]]; then
        echo "Error: No files found or failed to retrieve data"
        return 1
    fi

    # Count total files
    local total_files=$(echo "$json_data" | jq 'length')
    echo "Found $total_files files to download"
    echo ""

    # Extract file IDs and folders, then create directory structure
    echo "Creating local directory structure..."
    echo "$json_data" | jq -r '.[] | .describe.folder' | sort -u | while read -r remote_folder; do
        # Replace the dx_folder prefix with target_dir
        local local_folder="${target_dir}${remote_folder#$dx_folder}"
        mkdir -p "$local_folder"
    done

    echo "Directory structure created"
    echo ""

    # Download files in parallel using xargs
    echo "Starting downloads with $max_jobs parallel jobs..."

    # Export variables so they're available in subshells
    export dx_folder
    export target_dir

    # Create a helper function for downloading a single file
    download_file() {
        local file_id="$1"
        local remote_folder="$2"
        local local_folder="${target_dir}${remote_folder#$dx_folder}"

        dx download "$file_id" -o "$local_folder/" 2>&1 | sed "s/^/[$file_id] /"
    }
    export -f download_file

    # Use xargs to download files in parallel
    echo "$json_data" | jq -r '.[] | "\(.id)\t\(.describe.folder)"' | \
        xargs -P "$max_jobs" -I {} bash -c 'IFS=$"\t" read -r file_id remote_folder <<< "{}"; download_file "$file_id" "$remote_folder"'

    echo ""
    echo "All downloads completed!"
    echo "Files downloaded to: $target_dir"
}

# If script is executed directly (not sourced), run the function with arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    dx_parallel_download "$@"
fi
