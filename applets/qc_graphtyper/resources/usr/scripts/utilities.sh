###################
# Utility functions
###################


# Function to print STDERR message with timestamp
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}


# Function to safely add directories to cleanup list
track_temp_dirs() {
    local dir="$1"
    GLOBAL_TEMP_DIRS+=("$dir")
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Tracking temp directory: $dir" >&2
}


clean_temp_dirs() {
    local exit_code=$?
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Starting global cleanup ..." >&2
    
    # Kill any remaining parallel jobs
    pkill -P $$ 2>/dev/null || true
    

    # print all error logs to screen if non-zero
    if [[ $exit_code -gt 0 ]] ; then

        if [[ -f "${RUNTIME_DIR}/LOG/${VAL_LOG_FILE}" ]]; then cat "${RUNTIME_DIR}/LOG/${VAL_LOG_FILE}"; fi

        if [[ -f "${RUNTIME_DIR}/LOG/${QC_LOG_FILE}" ]]; then cat "${RUNTIME_DIR}/LOG/${QC_LOG_FILE}"; fi

    fi
    


    # Clean up any temporary directories
    for dir in "${GLOBAL_TEMP_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir" 2>/dev/null || true
        fi
    done
    
    
    # Log final status
    if [[ $exit_code -eq 0 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Global cleanup completed successfully" >&2
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Global cleanup completed after error (exit code: $exit_code)" >&2
    fi
    
    exit $exit_code
}