# Preparing input sites-only VCFs from plink pvar files

This is an example of a script that will split pvar files from DRAGEN QC'ed data. 


## Splitting files into smaller chunks



Start an interactive session. It takes ~2 hours to split all chr on a machine with 16 cores.


```bash

dx run \
--priority high \
--instance-type mem1_ssd1_v2_x16 \
--ssh app-cloud_workstation

```


Create a working directory and install required apps


```bash
mkdir $HOME/scatter_logs

cd  $HOME/scatter_logs

sudo apt install tabix bcftools parallel
```


Either clone the repo from github and source the function called scatter_pvar.sh or define it on the command line.




```bash
git clone https://github.com/mahmoudkoko/UKB_WGS_VEP.git

source UKB_WGS_VEP/resources/usr/scripts/scatter_pvar.sh

```



```bash
scatter_pvar() {
local CHR="$1"
local IDX=()

if ! mkdir -p vep/chr$CHR; then

echo "Failed to create working dir" >&2

elif ! dx cat "$DX_PROJECT_CONTEXT_ID:/Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${CHR}_b0_v1.pvar" |\
    tr ' ' '\t' |\
    awk 'BEGIN{print "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"}!/^#/{var_id=$3;gsub(".+:chr","chr",var_id);split(var_id, var_info, ":");print var_info[1],var_info[2],var_id,var_info[3],var_info[4],".",".","."}' OFS="\t" |\
    bgzip > "vep/chr$CHR/chr${CHR}.vcf.gz"; then

echo "Failed to convert pvar to vcf" >&2

elif ! bcftools index "vep/chr$CHR/chr${CHR}.vcf.gz"; then

echo "Failed to convert pvar to vcf" >&2

elif ! bcftools +scatter --prefix "ukb24308_c${CHR}_b" --threads 2 -Oz -o "vep/chr$CHR/" -n500000 "vep/chr$CHR/chr${CHR}.vcf.gz"; then

echo "Failed to split vcf" >&2

elif ! rm "vep/chr$CHR/chr${CHR}.vcf.gz" "vep/chr$CHR/chr${CHR}.vcf.gz.csi"; then

echo "Failed to remove tmp vcf" >&2

elif ! rename.ul ".vcf" ".qc.sites.vcf" vep/chr$CHR/ukb24308_c${CHR}_b* ; then

echo "Failed to rename tmp vcf" >&2

elif ! mapfile -t IDX < <(dx upload --no-progress --brief --recursive "vep/chr$CHR/" -p --path "$DX_PROJECT_CONTEXT_ID:/WGS/chr${CHR}/vep_input/") ; then

echo "Failed to upload split vcfs" >&2

elif ! rm -rf "vep/chr$CHR/"; then

echo "Failed to remove tmp split vcfs" >&2

else

echo "Finished splitting chr $CHR" >&2

printf "%s\n" "${IDX[@]}"

fi
}
```


Export the function and use it with parallel

```bash
export -f scatter_pvar


(echo {1..11} "X" {22..12} "Y" |\
awk '{for(i=1;i<=12;++i){ print $i; print $(i+12)}}' |\
parallel \
        --jobs 12 \
        --results "./" \
        --joblog "./parallel.log" \
        scatter_pvar {} ) && echo "Done splitting pvar files" || echo "Failed splitting pvar files" &

```


This will take a while (~1:30hr), hense running in the background. You can detach the session and exit or do something else (e.g. prep resources).


```bash
# detach
tmux detach

# it is safe to exit and ssh back again.


# if coming back again, you might need to find this session 

tmux attach -t 1
```


Once done, inspect the log file to make sure there are no errors.

```bash
cat parallel.log
```


Count the files. There should be around 28k files

```bash
# count 
(echo {1..22} "X" "Y" |\
tr ' ' '\n' |\
xargs -I% -P1 wc -l "1/%/stdout" )|\
tee >(awk '{f += $1;next}END{print f}')
```


Create lists of file IDs for processing with VEP.


````bash
chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

chr=${chr_list[$c]}

dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/WGS/chr${chr}/logs/ukb24308_c${chr}_all_vep_input_file_ids.txt" 1/$chr/stdout

done
```


Take note the upload path used here (see next section on batch submissions).

Delete log files and tmp directory.

```bash
cd .. && rm -rf scatter_logs
```



## Creating batch submission files

This section shows how you can create batch submission files that contain 100 chunks each. These can be used with `dx run --batch-tsv` as [explained here](https://documentation.dnanexus.com/user/running-apps-and-workflows/running-batch-jobs#batching-multiple-inputs).



```bash
mkdir vcf_batches && cd vcf_batches
```

Split file IDs created in the previous section into batches of 100 IDs and upload these lists

```bash
chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

N=${chr_list[$c]}

# Read the list of IDs and shuffle it, then split it into smaller batches of 100 files

dx cat "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}/logs/ukb24308_c${N}_all_vep_input_file_ids.txt" |\
shuf |\
split -l100 -d --additional-suffix="_vep_input_file_ids.txt" - ukb24308_c${N}_part

# Upload these smaller files

dx upload ukb24308_c${N}_part* \
-p \
--path "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}/logs/" \
--no-progress \
--brief >> ukb24308_c${N}_all_vep_input_lists.txt

# Delete the files

rm ukb24308_c${N}_part*

done

```

Create batch submission files for each chromosome


```bash
chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

N=${chr_list[$c]}

# Generate batch inputs

dx generate_batch_inputs \
    --path "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}/logs/" \
    -i vep_vcfs="ukb24308_c${N}_part(.*)_vep_input_file_ids.txt" \
    -o ukb24308_c${N}_vep_vcf_lists_for_batch_submission


# There is no need for the numerical suffix since no chr has more than 500 batches

rename.ul ".0000.tsv" ".tsv" ./ukb24308_c${N}_vep_vcf_lists_for_batch_submission.0000.tsv

# Upload the batch submission file

dx upload ukb24308_c${N}_vep_vcf_lists_for_batch_submission.tsv \
--path "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}/logs/" \
-p \
--no-progress \
--brief 

# Delete it after upload

rm ukb24308_c${N}_vep_vcf_lists_for_batch_submission.tsv


done


cd ..

rm -rf vcf_batches/
```




If not using this workstation for something else, terminate it.

```bash
dx terminate $DX_JOB_ID
```