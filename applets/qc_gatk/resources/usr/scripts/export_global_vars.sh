# Function to export global env variables

export_global_vars() {

# Going forward, CAPs will indicate variables not specific to a function.

# Applet

export DX_APPLET_ID="$(cat /home/dnanexus/dnanexus-job.json | jq -r .executable )"
export DX_EXECUTABLE_NAME="$(cat /home/dnanexus/dnanexus-job.json | jq -r .executableName )"
export DX_CPUS="$(cat /home/dnanexus/dnanexus-job.json | jq -r .instanceType | sed 's/mem.*x//')"
export DX_VER="$(cat /home/dnanexus/dnanexus-job.json | jq -r .instanceType | sed -e 's/_.*$//' -e 's/^mem//')"
export DX_MEM=$(( ( 2 ** DX_VER ) * DX_CPUS ))
export DX_OUTPUT_DIR="$(cat /home/dnanexus/dnanexus-job.json | jq -r .folder )"


echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Instance: mem $DX_VER - ram $DX_MEM gb - cores $DX_CPUS cpus" >&2

 # Input

export VCF_LIST_HASH="$(cat /home/dnanexus/job_input.json  | jq -r '.ukb23374_vcf_list.["$dnanexus_link"]' )"
export VCF_LIST_NAME=$(dx describe --json "${DX_PROJECT_CONTEXT_ID}:${VCF_LIST_HASH}" | jq -r .name )
export VCF_LIST_DIR=$(dx describe --json "${DX_PROJECT_CONTEXT_ID}:${VCF_LIST_HASH}" | jq -r .folder )

echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Input list: $VCF_LIST_NAME - output $DX_OUTPUT_DIR" >&2



export JOB_MEM="$(cat /home/dnanexus/job_input.json  | jq -r '.mem_per_vcf' )"
export N_JOBS=$(( DX_MEM / JOB_MEM ))
export JOB_CPUS=$(( DX_CPUS / N_JOBS ))

echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Job allocations: $N_JOBS jobs - $JOB_MEM gb - $JOB_CPUS cpus" >&2

# # Make sure the requested ram is between 1 - $DX_MEM
# if [[ $JOB_MEM -eq 0 ]] || [[ $JOB_MEM -gt $DX_MEM ]];then
#     export JOB_MEM=$DX_MEM
# fi

# # Detemine if possible to run several VCFs at once with at least one CPU per job
# if [[ $DX_MEM -gt $JOB_MEM ]] && [[ $DX_CPUS -gt  ]]; then
    
#     export N_JOBS=$(( $DX_MEM/$JOB_MEM ))
#     export JOB_CPUS=$(( $DX_CPUS/$N_JOBS ))

# elif [[ $DX_MEM -gt $JOB_MEM ]] && [[ $(( $DX_MEM/$JOB_MEM )) -gt $DX_CPUS ]]; then

#     export N_JOBS=$(( $DX_CPUS - 1 ))
#     export JOB_CPUS=1

# else

#     export N_JOBS=1
#     export JOB_CPUS=1

# fi




# OUTPUTS
export RUNTIME_DIR="/home/dnanexus/RUNTIME"
export VAL_LOG_FILE="${DX_JOB_ID}.validation.log"
export QC_LOG_FILE="${DX_JOB_ID}.qc.log"


# BCFtools, bgzip, and tabix binaries are pre-packaged in this applet under /usr/bin which is already in $PATH. 
# This will export the path to some required libraries to run bcftools or its plugins
export LD_LIBRARY_PATH=/usr/lib
export BCFTOOLS_PLUGINS=/usr/lib

# Global cleanup tracking
export -a GLOBAL_TEMP_DIRS
export -a GLOBAL_TEMP_FILES

}


# Function to log execution context on STDOUT (log file)
validate_execution_context() {

    if [[ -z $DX_JOB_ID ]] || [[ -z $DX_PROJECT_CONTEXT_ID ]] || [[ -z $DX_APPLET_ID ]] || [[ -z $DX_EXECUTABLE_NAME ]] || [[ -z $DX_OUTPUT_DIR ]]; then

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to parse the exceuction context" >&2
        return 1

    elif [[ -z $N_JOBS ]] || [[ -z $JOB_MEM ]] || [[ -z $JOB_CPUS ]]; then
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to parse job allocations" >&2
        return 1

    elif [[ -z $VCF_LIST_DIR ]] || [[ -z $VCF_LIST_NAME ]] || [[ -z $VCF_LIST_HASH ]]; then
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to parse input VCF list" >&2
        return 1

    else
 
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Successfully validated exceuction context" >&2

    fi

}
