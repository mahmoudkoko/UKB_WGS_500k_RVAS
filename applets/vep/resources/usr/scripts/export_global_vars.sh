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
export N_JOBS=$(( DX_CPUS * 80 / 100 ))
export BCFTOOLS_VERSION=$(bcftools --version 2>/dev/null | head -n1 || echo "Not available")

export RUNTIME_DIR="/home/dnanexus/RUNTIME"
export RUNTIME_LOG="${DX_JOB_ID}.vep.log"
export VAL_LOG="validation.log"
export PAR_LOG="parallel.log"
export VEP_HOME="$RUNTIME_DIR/VEP"


# Input files and vep data
export VCF_LIST_HASH="$(cat /home/dnanexus/job_input.json  | jq -r '.vep_vcfs.["$dnanexus_link"]' )"
export VCF_LIST_NAME=$(dx describe --json "${DX_PROJECT_CONTEXT_ID}:${VCF_LIST_HASH}" | jq -r .name )
export VCF_LIST_DIR=$(dx describe --json "${DX_PROJECT_CONTEXT_ID}:${VCF_LIST_HASH}" | jq -r .folder )


# VEP data
export VEP_VER="$(cat /home/dnanexus/job_input.json  | jq -r '.vep_ver' )"
export VEP_DOCKER=$(dx describe --multi --json "$DX_PROJECT_CONTEXT_ID:/Resources/vep_${VEP_VER}_docker/vep_${VEP_VER}_docker_amd64.tar.gz" | jq -r .[0].id || echo "")
export VEP_PLUGINS=$(dx describe --multi --json "$DX_PROJECT_CONTEXT_ID:/Resources/vep_${VEP_VER}_docker/vep_${VEP_VER}_plugins.tar.gz" | jq -r .[0].id || echo "")
export VEP_BUFFER="$(cat /home/dnanexus/job_input.json  | jq -r '.vep_buffer' )"
export VEP_FORKS="$(cat /home/dnanexus/job_input.json  | jq -r '.vep_forks' )"
export VEP_TIMEOUT="$(cat /home/dnanexus/job_input.json  | jq -r '.vep_timeout' )"
export VEP_CHR="$(cat /home/dnanexus/job_input.json  | jq -r '.vep_chr' )"
export VEP_DATA="$DX_PROJECT_CONTEXT_ID:/Resources/vep_${VEP_VER}_data/chr${VEP_CHR}/"



if [[ -z $DX_JOB_ID ]] || [[ -z $DX_PROJECT_CONTEXT_ID ]] || [[ -z $DX_APPLET_ID ]] || [[ -z $DX_EXECUTABLE_NAME ]] || [[ -z $DX_OUTPUT_DIR ]] || [[ -z $N_JOBS ]]; then

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to parse job exceuction context" >&2
    return 1

elif [[ -z $VEP_VER ]] || [[ -z $VEP_DOCKER ]] || [[ -z $VEP_PLUGINS ]] || [[ -z $VEP_CHR ]] || [[ -z $VEP_DATA ]] || [[ ! "$VEP_BUFFER" =~ ^[1-9][0-9]*$ ]] || [[ ! "$VEP_FORKS" =~ ^[1-9][0-9]*$ ]]  || [[ ! "$VEP_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
        
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Failed to parse VEP exceuction context" >&2
    return 1

elif ! [[ $VCF_LIST_NAME =~ ^ukb && $VCF_LIST_NAME =~ _c${VEP_CHR}_ ]] ; then
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: VCF input list name is malformed or does not match VEP chromosome" >&2
    return 1

else

    # Print logs
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: VCF list: $VCF_LIST_NAME" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: VEP: version $VEP_VER - chromosome: $VEP_CHR" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Instance: mem $DX_VER - ram $DX_MEM gb - cores $DX_CPUS cpus" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: Parallel annotation runs: upto $N_JOBS" >&2

fi


# Global cleanup tracking
export -a GLOBAL_TEMP_DIRS
export -a GLOBAL_TEMP_FILES


}