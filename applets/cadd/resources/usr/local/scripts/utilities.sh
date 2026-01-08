#!/bin/bash

dx_stream() {

	# This function streams and decompresses files from DNAnexus based on file type.
	# Usage:
	#   dx_stream --file_id <file_id> [--file_name <file_name>] [--mode <mode>]
	# Arguments:
	#   --file_id: The DNAnexus file ID to stream (required).
	#   --file_name: The name of the file (optional, used to infer mode if not provided).
	#   --mode: The mode/type of the file (optional, inferred from file_name if not provided).
	# Supported modes:
	#   gz   - gzip compressed files (.gz, .bgz)
	#   zst  - zstd compressed files (.zst, .zstd)
	#   vcf  - uncompressed VCF files (.vcf)
	#   pvar - uncompressed pvar files (.pvar)
	#   bcf  - BCF files (.bcf)
	# Example:
	#   dx_stream --file_id "file-xxxx" --file_name "data.vcf.gz"



    local file_id=""
    local file_name=""
    local mode=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file_id)
                file_id="$2"
                shift 2
                ;;
            --file_name)
                file_name="$2"
                shift 2
                ;;
            --mode)
                mode="$2"
                shift 2
                ;;
            *)
                echo "Error: Unknown argument: $1" >&2
                return 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$file_id" ]]; then
        echo "Error: --file_id is required" >&2
        return 1
    fi
    
    # Determine mode from filename if not provided
    if [[ -z "$mode" ]]; then
        if [[ -z "$file_name" ]]; then
            echo "Error: Either --mode or --file_name must be provided" >&2
            return 1
        fi
        
        case "$file_name" in
            *.gz|*.bgz)
                mode="gz"
                ;;
            *.zst|*.zstd)
                mode="zst"
                ;;
            *.vcf)
                mode="vcf"
                ;;
            *.pvar)
                mode="pvar"
                ;;
            *.bcf)
                mode="bcf"
                ;;
            *)
                echo "Error: Cannot determine file type from filename: $file_name" >&2
                echo "Supported extensions: .gz, .bgz, .zst, .zstd, .vcf, .pvar, .bcf" >&2
                return 1
                ;;
        esac
    fi
    
    # Stream and decompress based on mode
    case "$mode" in
        gz)
            dx cat "$file_id" | gzip -dc
            ;;
        zst)
            dx cat "$file_id" | zstd -dc
            ;;
        vcf|pvar)
            dx cat "$file_id"
            ;;
        bcf)
            dx cat "$file_id" | bcftools view
            ;;
        *)
            echo "Error: Invalid mode: $mode" >&2
            echo "Valid modes: gz, zst, vcf, pvar, bcf" >&2
            return 1
            ;;
    esac
}


mapfile -t cadd_files_list < <(dx cat "${DX_PROJECT_CONTEXT_ID}:${CADD_DATA_DIR_REMOTE}/CADD_v1_7_resources_list.txt" | sort | uniq | shuf)


download_cadd_resource() {
    local resource_name="$1"
    local local_path="$2"
    local remote_path="${CADD_DATA_DIR_REMOTE}/${resource_name}"
     dx find data --path "Resources/cadd_v1_7_data/" --class file --json
    echo "Downloading CADD resource: $resource_name to $local_path"
    dx download "${DX_PROJECT_CONTEXT_ID}:${remote_path}" -o "$local_path"
}
