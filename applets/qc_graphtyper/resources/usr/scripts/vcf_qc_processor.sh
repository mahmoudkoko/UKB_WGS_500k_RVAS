#!/bin/bash


set -euo pipefail  # Exit on error, undefined vars, pipe failures
set -x  # Uncomment for debugging




##################
# Configurations
##################

PROJECT_ID="$project_id"
VCF_LIST="${project_id}:${ukb23374_vcf_list}"
OUTPUT_DIR="$qc_output_dir"
N_JOBS="$parallel_qc_jobs"




#####
# ENV
#####


validate_dependencies() {
    local deps=("bcftools" "plink2" "dx" "parallel")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "ERROR: Required tool '$dep' not found" >&2
            exit 3
        fi
    done

	if [[ -d /usr/lib ]]; then
	    export BCFTOOLS_PLUGINS=/usr/lib
	    export LD_LIBRARY_PATH=/usr/lib:$LD_LIBRARY_PATH

	else
	    echo "ERROR: BCFtools plugins directory not found" >&2
	    exit 3
	fi

}


#############
# QC function
#############

process_graphtyper_vcf_block() {

	# This function will use one input parameter $1; it should be a file hash that refers to a GraphTyper VCF block (field 23374).

	# It do the following:
	# 1. Download the input VCF file.
	# 2. Apply a set of predefined genotype filters using bcftools and create a temporary bcf file annotated with custom variant-level QC metrics.
	# 3. Create a PGEN (Plink2) file (output 1), pvar file (output 2) and psam file (output 3).
	# 4. Query per-sample variant counts using plink2 (output 4).
	# 5. Create a sites-only vcf file from pvar using awk (output 5).
	# 6. Query variant quality scores from this vcf (output 6).
	# 7. Keep a list of output files (output 7) and a log of the progress (output 8).
	# 8. Upload all these output files to the target project sub-directory (one of the inputs to this applet).

	# test file

	# Read input
	local query_input=$1

	# Try to treat as file ID first, fall back to path
	if [[ "$1" =~ ^file- ]]; then
	    vcf_hash="$1"
	else
	    # Try to resolve as path
	    vcf_hash=$(dx describe "$1" 2>/dev/null | grep "^ID" | cut -d' ' -f2) || {
	        >&2 echo "ERROR: Cannot resolve $1 to file ID. Skipping."
	        return 2
	    }
	fi

	# if [[ "${query_input: 0:5}" == "file-" ]]; then

	# 	# this looks like a file name
	# 	# Use 'dx describe' to pull the hash description, then get the file name from the file description using json query (replaced here with grep; not sure it is installed by default.
	
	# 	local vcf_hash=$1

	# elif [[ "${query_input}" =~ "Bulk/GATK and GraphTyper WGS/GraphTyper population level WGS variants" ]] && [[ "${query_input}" =~ "vcf.gz" ]]; then

	# 	# this looks like a file path
	# 	# Use 'dx describe' to pull the hash, then get the file name from the file description using json query (replaced here with grep; not sure it is installed by default.

	# 	local vcf_path=$1
	# 	local vcf_hash=$(dx describe $vcf_path | grep "^ID" | tr -s ' ' | cut -d' ' -f2)

	# else
	# 		>&2 echo "ERROR: $query_input does not match expected input (VCF file path or file ID). Skipping"
	# 		return 2

	# fi



	# Pull the VCF name and make extra sure this is field 23374, then check for previous outputs

	local vcf_name=$(dx describe $vcf_hash | grep "^Name" | tr -s ' ' | cut -d' ' -f2)

	if [[ "${vcf_name: 0:10}" != "ukb23374_c" ]] || [[ "${vcf_name: -10}" != "_v1.vcf.gz" ]]; then

		# Print a warning that this file isn't a GraphTyper WGS vcf file and exit with error if
		>&2 echo "ERROR: $vcf_name does not match expected pattern (ukb23374_cx_bx_v1.vcf.gz). Skipping"
		return 2
	
	elif dx find data --name "${vcf_name%.vcf.gz}.qc_outputs.txt" --folder "${OUTPUT_DIR}/logs/" --brief | grep -q . ;then

	# If the 'outputs list' is present, then the previous run was successful since it is the last file to be uploaded
	 	>&2 echo "ERROR: Found a list of outputs for block $blk of chromosome $chr in the project directory. Skipping."
		return 2

	else
		# Continue otherwise

		# Extract the chromosome and block from the file name
		local chr=$(echo $vcf_name | cut -f2 -d'_' | tr -d 'c')
		local blk=$(echo $vcf_name | cut -f3 -d'_' | tr -d 'b')

		# Create a local directory using the unique hash (remove the prefix "file-")
		local vcf_dir=${vcf_hash#file-}
		mkdir "$vcf_dir"

		# Creat a prefix for output files in this directory
		local file_name_prefix=${vcf_dir}/${vcf_name%".vcf.gz"}

		# Echo a log message to STDERR
		>&2 echo "[$(date '+%Y-%m-%d %H:%M:%S')]: Downloading block $blk of chromosome $chr"

		# dx download -f "${PROJECT_ID}:${vcf_hash}" --output "$vcf_dir/" --no-progress

		# # PROBLEM: Many operations don't check for success
		# dx download -f "${PROJECT_ID}:${vcf_hash}" --output "$vcf_dir/" --no-progress

		# BETTER:
		if ! dx download -f "${PROJECT_ID}:${vcf_hash}" --output "$vcf_dir/" --no-progress; then
		     >&2 echo "ERROR: Failed to download $vcf_hash ; Skipping"
		    return 2
		fi



		if bcftools view -H "${file_name_prefix}.vcf.gz" | head -n 1 | grep -q . ; then

			>&2 echo "[$(date '+%Y-%m-%d %H:%M:%S')]: Applying genotype filters ..."

		else

		 	>&2 echo "[$(date '+%Y-%m-%d %H:%M:%S')]: No variants in this VCF. Skipping."
		 	rm -rf "$vcf_dir"
		 	return 1
		fi

	fi


	# decompress and convert to a binary stream
	bcftools view --no-version -Ou --threads 2 "${file_name_prefix}.vcf.gz" |\
	# keep the required info and format tags and remove the rest
	bcftools annotate --no-version -Ou -x ID,^INFO/MQ,^INFO/AAScore,^INFO/QD,^INFO/QDalt,^FORMAT/GT,^FORMAT/AD,^FORMAT/DP,^FORMAT/GQ,^FORMAT/PL |\
	# split multi-allelic sites and tag the resulting records; use the sum of non-ALT alleles as the reference AD (i.e. keep allele sum)
	bcftools norm --no-version -Ou -m-any --keep-sum AD |\
	# remove any sites that failed this splitting process (just to be safe)
	bcftools view --no-version -Ou  -m2 -M2 |\
	# unphase and sort alleles (1/0 to 0/1) (extra safety)
	bcftools +setGT --no-version -Ou -- -n u -t a |\
	# Set to missing: half-missing (extra safety)
	bcftools +setGT --no-version -Ou -- -n . -t ./x |\
	# Filtering on Allele Depth: require informative reads >= 75% total depth
	bcftools +setGT --no-version -Ou -- -n . -t q -i ' GT="alt" & ( sSUM(FMT/AD) / FMT/DP ) < 0.75 ' |\
	# calculate the variant allele fraction
	bcftools +fill-tags --no-version -Ou -- -t 'VAF' |\
	# Set to missing: REF where VAF > 0.3 or less than 5 reference reads
	bcftools +setGT --no-version -Ou -- -n . -t q -i ' GT="0/0" & (FMT/AD[:0] < 5 | FMT/VAF > 0.3 )' |\
	# Set to missing: HOM where VAF < 0.7 or less than 5 alt reads
	bcftools +setGT --no-version -Ou -- -n . -t q -i ' GT="1/1" & (FMT/AD[:1] < 5 | FMT/VAF < 0.7 )' |\
	# calculate binomial p-value from VAF
	bcftools +fill-tags --no-version -Ou -- -t 'FMT/pAB:1=binom(FMT/AD)' |\
	# Set to missing: HET where VAF < 0.1 or > 0.9, or p value < 1e-5 (approx 10/50 reads, 30/100 reads), or less than 3 supporting reads per allele
	bcftools +setGT --no-version -Ou -- -n . -t q -i ' GT="0/1" & (FMT/AD[:0] < 3 | FMT/AD[:1] < 3 | FMT/VAF < 0.1 | FMT/VAF > 0.9 | FMT/pAB < 0.00001)' |\
	# Estimate GQ from PL (useful if GQ is recalibrated like with Deep Variant or when the site is split)
	bcftools +fill-tags --no-version -Ou -- -t 'FMT/plGQ:1=int(sMEDIAN(FMT/PL)-sMIN(FMT/PL))' |\
	# Set to missing: require GQ 20 from any of these estimates
	bcftools +setGT --no-version -Ou -- -n . -t q -i ' GQ < 20 & plGQ < 20 ' |\
	# Set to missing: ref calls where PL0 is not the smallest value
	bcftools +setGT --no-version -Ou -- -n . -t q -i ' GT="0/0" & ( (PL[:0] >= PL[:1]) | (PL[:0] >= PL[:2]) ) ' |\
	# Set to missing: het calls where PL1 is not the smallest value
	bcftools +setGT --no-version -Ou -- -n . -t q -i ' GT="0/1" & ( (PL[:1] >= PL[:0]) | (PL[:1] >= PL[:2]) ) ' |\
	# Set to missing: hom calls where PL2 is not the smallest value
	bcftools +setGT --no-version -Ou -- -n . -t q -i ' GT="1/1" & ( (PL[:2] >= PL[:0]) | (PL[:2] >= PL[:1]) ) ' |\
	# Re-calculate default bcftools info tags after QC
	bcftools +fill-tags --no-version -Ou -- -t 'NS,AC,AN,AC_Het,AC_Hom,AC_Hemi,ExcHet' |\
	# convert phred-sclaed genotype likelihoods to genotype likelihoods then annotate quality by depth (see gnomad qc)
	bcftools +tag2tag --no-version -Ou -- --PL-to-GL --replace |\
	bcftools +fill-tags --no-version -Ou -- -t 'INFO/QAD= ( 0 - ( ( SUM(FMT/GL) - SUM(FMT/GL[:0]) ) / ( SUM(FMT/AD) - SUM(FMT/AD[:0]) ) ) )' |\
	# annotate summary stats: average depth & GQ per site, phred scaled % variants with GQ<40 or DP<10 split by genotype, % heterozygous variants with 0.4 < VAF < .6
	bcftools +fill-tags --no-version -Ou -- -t 'INFO/LEN_REF:1=STRLEN(REF),INFO/LEN_ALT:1=STRLEN(ALT),INFO/DP_AVG=MEAN(FMT/DP),INFO/GQ_AVG=MEAN(FMT/GQ),INFO/DP10_REF=( COUNT(GT="0/0" & FMT/AD[:0] < 10 ) / COUNT(GT="0/0") ),INFO/DP10_HOM=( COUNT(GT="1/1" & FMT/AD[:1] < 10 ) / COUNT(GT="1/1") ),INFO/DP10_HET=( COUNT(GT="0/1" & SUM(FMT/AD) < 10 ) / COUNT(GT="0/1") ),INFO/GQ40_REF=( COUNT(GT="0/0" & FMT/GQ < 40 & FMT/plGQ < 40 ) /  COUNT(GT="0/0") ),INFO/GQ40_HOM=( COUNT(GT="1/1" & FMT/GQ < 40 & FMT/plGQ < 40 ) /  COUNT(GT="1/1") ),INFO/GQ40_HET=( COUNT(GT="0/1" & FMT/GQ < 40 & FMT/plGQ < 40 ) /  COUNT(GT="0/1") ),INFO/VAF40_HET=( COUNT(GT="0/1" & (VAF < 40 | VAF > 60) ) / COUNT(GT="0/1") )'  |\
	# remove all FORMAT tags apart from GT
	bcftools annotate --no-version -Ou -x FORMAT/AD,FORMAT/DP,FORMAT/GQ,FORMAT/GL,FORMAT/plGQ,FORMAT/VAF,FORMAT/pAB |\
	# save and index
	bcftools view --no-version -Ob -i 'AC>0' -l 2 -o "${file_name_prefix}.bcf" --write-index=csi


	# Delete the input file to save space	
	rm "${file_name_prefix}.vcf.gz"

	# Read the first record after QC; Continue if there are variants after QC; Return if no variants

	if bcftools view -H "${file_name_prefix}.bcf" | head -n 1 | grep -q . ; then

		>&2 echo "[$(date '+%Y-%m-%d %H:%M:%S')]: Converting BCF to Plink2 files ..."

	else

		>&2 echo "[$(date '+%Y-%m-%d %H:%M:%S')]: No variants remaining after QC. Skipping."
		rm -rf "$vcf_dir"
		return 1

	fi

	# Convert BCF to Plink2 PGEN/PVAR/PSAM files
	plink2  --make-pgen 'vzs' \
		--bcf "${file_name_prefix}.bcf" \
		--vcf-half-call m  \
		--threads 2 \
		--memory 3000 \
		--out "${file_name_prefix}.qc"

	# Delete the bcf file and index
	rm "${file_name_prefix}.bcf" "${file_name_prefix}.bcf.csi"

	# compress the psam file

	gzip "${file_name_prefix}.qc.psam"

	# Create a sites-only VCF from 'pvar' file and edit the pvar file to remove the FILTER column and INFO fields
	>&2 echo "[$(date '+%Y-%m-%d %H:%M:%S')]: Creating a sites-only vcf ..."

	# First rename the pvar file
	mv "${file_name_prefix}.qc.pvar.zst" "${file_name_prefix}.qc.pvar.zst.bk"

	# Then create a compressed VCF header by adding a fileformat TAG and bgzipping the header
	zstdcat "${file_name_prefix}.qc.pvar.zst.bk" |\
	awk -F"\t" 'BEGIN{print "##fileformat=VCFv4.2"}!/^#/{exit}1' OFS="\t" |\
	bgzip > "${file_name_prefix}.qc.sites.vcf.gz"

	# Now append the variants to this header and create custom IDs (chr:block:var_idx)
	zstdcat "${file_name_prefix}.qc.pvar.zst.bk" |\
	awk '!/^#/'  |\
	awk -F'\t' -v blk="${blk}" -v bed_file="${file_name_prefix}.qc.bed" 'NR==1{ start_position=$2 }{$3=$1":"blk":"NR; print "chr"$0}END{ end_position=$2; print "chr"$1,start_position,end_position,"b"blk,NR > bed_file }' OFS="\t" |\
	bgzip >> "${file_name_prefix}.qc.sites.vcf.gz"

	# At the end, index the vcf file
	bcftools index "${file_name_prefix}.qc.sites.vcf.gz"


	# Create a new compressed pvar file without info fields
	zcat "${file_name_prefix}.qc.sites.vcf.gz" |\
	awk -F"\t" '/^##fileformat/ || /^##FILTER/ || /^##INFO/{next;}/^##/{print}/^#CHROM/{$7=$8;NF=7;print}!/^#/{$1=gsub("^chr","",$1);$6=".";$7=".";NF=7;print}' OFS="\t" |\
	zstd --no-progress -o "${file_name_prefix}.qc.pvar.zst"




	# Collect Sample QC metrics (variant counts) using BCFtools from the sites-only VCF
	>&2 echo "[$(date '+%Y-%m-%d %H:%M:%S')]: Collecting variant-level QC metrics (variant quality scores) ..."

	bcftools query -f '%ID %TYPE %LEN_REF %LEN_ALT %NS %AN %AC %AC_Het %AC_Hom %AC_Hemi %FILTER %QUAL %MQ %AAScore %QD %QDalt %QAD %ExcHet %DP_AVG %GQ_AVG %DP10_REF %DP10_HOM %DP10_HET %GQ40_REF %GQ40_HOM %GQ40_HET %VAF40_HET' "${file_name_prefix}.qc.sites.vcf.gz" |\
	tr ' ' '\t' |\
	gzip > "${file_name_prefix}.qc.quality_scores.tsv.gz"


	# Collect Sample QC metrics (variant counts)
	>&2 echo "[$(date '+%Y-%m-%d %H:%M:%S')]: Collecting Sample QC metrics (variant counts per sample) ..."

	plink2 --pfile "${file_name_prefix}.qc" 'vzs' \
		--sample-counts 'zs' 'cols=homref,homalt,homaltsnp,het,ts,tv,single,missing' \
		--threads 2 \
		--memory 3000 \
		--out "${file_name_prefix}.qc"


	# Reformat this file to 'gzip' remove the header (makes concatenation easier)
	zstdcat "${file_name_prefix}.qc.scount.zst" |\
	awk '!/^#/' |\
	gzip > "${file_name_prefix}.qc.sample_stats.tsv.gz"


	# Now all files are ready; organize them in separate dirs to upload them and delete unnecessary files

	>&2 echo "[$(date '+%Y-%m-%d %H:%M:%S')]: Uploading outputs to destination directory ..."

	mkdir "${vcf_dir}/pfiles" "${vcf_dir}/stats" "${vcf_dir}/sites" "${vcf_dir}/logs"

	mv "${file_name_prefix}.qc.pgen" "${file_name_prefix}.qc.psam.gz" "${file_name_prefix}.qc.pvar.zst" "${vcf_dir}/pfiles/"

	mv "${file_name_prefix}.qc.bed" "${file_name_prefix}.qc.sites.vcf.gz" "${file_name_prefix}.qc.sites.vcf.gz.csi" "${vcf_dir}/sites/"

	mv "${file_name_prefix}.qc.quality_scores.tsv.gz" "${file_name_prefix}.qc.sample_stats.tsv.gz" "${vcf_dir}/stats/"

	rm "${file_name_prefix}.qc.scount.zst" "${file_name_prefix}.qc.pvar.zst.bk" "${file_name_prefix}.qc.log"


	local dx_upload_ids

	mapfile -t dx_upload_ids < <(dx upload --recursive "$vcf_dir/" --tag "wgs_qc_block"  --path ${OUTPUT_DIR}/ --brief)

    # Add the chr, block and hashes to the output array
    local output_files_array=()
    output_files_array+=("${chr}")
    output_files_array+=("${blk}")
    output_files_array+=("${vcf_hash}")
	output_files_array+=("${dx_upload_ids[@]}")



	# Upload the final output list
    output_files_list_hash=$(echo "${output_files_array[@]}" |\
    	dx upload - \
    		--path "${OUTPUT_DIR}/logs/${vcf_name%.vcf.gz}.qc_outputs.txt" \
        	--tag "wgs_qc_block" \
        	--property "$(printf 'chromosome=%s' "$chr")" \
        	--property "$(printf 'block=%s' "$blk")" \
        	--brief)


    # Delete the working directory
	rm -rf "$vcf_dir"

	>&2 echo "[$(date '+%Y-%m-%d %H:%M:%S')]: Completed."

	# retrun the input file, the output list and the log
	echo "$vcf_name,$output_files_list_hash"

	return 0
}




main_fx(){

	mkdir "./LOG_DIR"

	# Download the input file (a list of VCF hashes; file name: vcf_list_*_of_*.txt")
	local vcf_list_file=$(dx describe $VCF_LIST | grep "^Name" | tr -s ' ' | cut -d' ' -f2)

	dx download "${VCF_LIST}" -o "LOG_DIR/${vcf_list_file}"

	local joblog="LOG_DIR/${vcf_list_file%.input.txt}.log"
	local jobsummary="LOG_DIR/${vcf_list_file%.input.txt}.summary.txt"

	export -f process_graphtyper_vcf_block

	# Run jobs with timeout and a single retry
	parallel \
	  --jobs "$N_JOBS" \
	  --results "$LOG_DIR" \
	  --joblog "$joblog" \
	  --timeout 7200 \
	  --retries 1 \
	  process_graphtyper_vcf_block :::: "LOG_DIR/${vcf_list_file}"


	# Summary
	echo "----- Summary -----"
	echo "Input: $vcf_list_file"

	echo "VCFs: $(awk 'NR>1' $joblog | wc -l)"
	echo "COMPLETED: $(awk -F"\t" 'NR > 1 && $7 == 0' $joblog | wc -l)"
	echo "SKIPPED: $(awk -F"\t" 'NR > 1 && $7 == 1' $joblog | wc -l)"
	echo "FAILED: $(awk -F"\t" 'NR > 1 && $7 > 1' $joblog | wc -l)"

	# Combine all stdout into a single file
	find "./LOG_DIR" -name stderr -exec cat {} + | gzip > "${jobsummary}.gz"

	cat "$joblog" | gzip >> "${jobsummary}.gz"


	dx upload "${jobsummary}.gz" --brief

}




