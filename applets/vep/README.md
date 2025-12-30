# UKBiobank VEP annotation



## Input and outputs

The applet takes on a chromosome name, a list of bgzipped input files in vcf format and uses a docker image to annotate a pre-defined list of VEP annotations.

It accepts the following inputs:

1. VCF list (`vep_vcfs`): File ID of a text file containing a list of VCFs to annotate (File IDs or file names with full path).
2. Chromosome (`vep_chr`): used to determine which chromosome-level files (cache, annotations, etc) to download.
3. Buffer (`vep_buffer`): VEP buffer size (argument passed to VEP). 
4. Forks (`vep_forks`): VEP forks (argument passed to VEP). 
5. Timeout (`vep_timeout`): max time (seconds) allowed before each annotation job (file) is killed. Prevents 
6. Version (`vep_version`): Version to use. Currently 114.

The outputs are:

1. Log file: named `${DESTINATION}/logs/job-xxx.vep.log`.
2. Output lists: named `${DESTINATION}/logs/${vcf_name_prefix}.vep.outputs.txt`.
3. Output tsv: named `${DESTINATION}/logs/${vcf_name_prefix}.vep.outputs.tsv.gz`.



## Preparing VEP docker, cache and databases

Prepare a docker image with VEP, and upload the cache and pre-calculated scores (e.g, for SNVs).

[This documentation](resources/usr/doc/vep_resources.md) shows how you can prepare the required VEP docker image and other resources.


## Preparing input VCFs

Prepare a list of VCF file IDs. Each VCF should ideally be sites-only and reasonably sized to avoid downloading large files and excessive mem usage.


[This documentation](resources/usr/doc/vep_input.md) shows how to create VCF chunks of 50k variants.

Otherwise, prepare your own lists. Input files should match the chromosome name given as input (i.e., vcf name should have the general form `ukb*_c*_*.vcf.gz`). These files should be a reasonably sized (e.g., less than 100k variants, ideally 50k) to have balanced run times. 



## Interactive testing

See [this documentation](resources/usr/doc/vep_interactive.md) to see how this applet can be tested interactively.



## Building and testing


### Cloning and building in target project


If not already done, clone the applet locally and enter the directory.


```bash
git clone https://github.com/mahmoudkoko/UKB_WGS_VEP.git
cd UKB_WGS_VEP
```


Log-in to UKRAP using an *admin* token or password


```bash
dx login --token "string*goes*here"
```

Once verified, create a folder for applets to keep things organized.


```bash
dx mkdir -p 'Applets'
```

Build the applet using `dx build` and capture the applet ID. Option `-f` overwrites any previous builds with the same name, and `--brief` suppresses verpose output


```bash
vep_applet_id=$(dx build -f ./ -d "Applets/" --brief | jq -r .id)
```

DX may warn that the applet name does not match the folder name but that's not an issue.



### Test submissions


Loop through all chromosomes and run test jobs to make sure all databases and input files are correctly structured


First, create an array of chromosome names.

This helps control the chromosome names if including sex chr or using prefix
 

With sex chr

```bash
chr_list=( $(echo {1..22} "X" "Y") )
```

Autosomes only


```bash
chr_list=( $(echo {1..22} ) )
```


Note that indexing logic is shell dependent; in bash, it starts at 0

The loop will look like this:

```bash
vep_test_list_file_ids=()

for (( c=0;c<${#chr_list[@]};++c )); do

N="${chr_list[$c]}"

IDX=$( echo "file-id"  )

vep_test_list_file_ids+=( "$IDX" )

echo "chr${N}" "${vep_test_list_file_ids[$c]}"

done

```



Create test file lists and upload them


```bash
vep_test_list_file_ids=()

for (( c=0;c<${#chr_list[@]};++c )); do

N="${chr_list[$c]}"


IDX=$(dx cat "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}/logs/ukb24308_c${N}_all_vep_input_file_ids.txt" |\
awk '{++f[$1];next}END{for(i in f) print i}' |\
head -n10 |\
dx upload --brief --no-progress --path "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}/logs/ukb24308_c${N}_test_vep_input_file_ids.txt" -
)

vep_test_list_file_ids+=( "$IDX" )

echo "chr${N}" "${vep_test_list_file_ids[$c]}"

done
```



Submit jobs


```zsh
vep_test_list_job_ids=()

for (( c=0;c<${#chr_list[@]};++c )); do

N="${chr_list[$c]}"

IDX=$(dx run ${vep_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}" \
--input vep_chr=${N} \
--input vep_vcfs="${vep_test_list_file_ids[$c]}" \
--name "VEP test submission: chr${N}" \
--instance-type mem1_ssd1_v2_x16 \
--priority high \
--brief \
-y)

vep_test_list_job_ids+=( "$IDX" )


echo "chr${N}:" $(dx describe --json "${vep_test_list_job_ids[$c]}" | jq -r '.state')

done



```


To keep a local copy of the job ids

```bash
for (( c=0;c<${#chr_list[@]};++c )); do

echo "${chr_list[$c]}" "${vep_test_list_file_ids[$c]}" "${vep_test_list_job_ids[$c]}" >> test_job_ids.txt

done

```

To monitor status later on


```bash

for (( c=0;c<${#chr_list[@]};++c )); do

echo "${chr_list[$c]}" $(dx describe --json "${vep_test_list_job_ids[$c]}" | jq -r '.state')

done


```


These jobs take ~20 min to run and cost ~£3-5 (high priority).


Once all are done, pull the log files and look at the success rate




To get all logs



```bash
for (( c=0;c<${#chr_list[@]};++c )); do

dx cat "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${chr_list[$c]}/logs/${vep_test_list_job_ids[$c]}.vep.log" >> test_job_logs.txt

done
```



To pull a list of successfully annotated VCFs


```bash
awk '{if ($0 ~ "=== Successfully annotated VCFs ===" || $0 ~ "=== Skipped VCFs ===") skip="no"; else if($0 ~ "===" ) skip="yes"}{if(skip == "no" && $0 !~ "===" && $0 != "") print}' test_job_logs.txt > test_job_successful.txt
```

To get failed inputs


```bash
awk '{if ($0 ~ "=== Failed VCFs ===" || $0 ~ "=== Skipped VCFs ===" || $0 ~ "=== Invalid inputs ===") skip="no"; else if($0 ~ "===" ) skip="yes"}{if(skip == "no" && $0 !~ "===" && $0 != "") print}' test_job_logs.txt > test_job_failed.txt
```


Use an interactive session to explore the files.





## Batch submissions


To process all WGS data, use batch submissions.


```bash
mkdir batch_submission

printf "batch_submission/\n" >> .gitignore
```

### Initial submission

Assuming you have created batch submission files [as shown here](resources/usr/doc/vep_resources.md), download it locally.


```bash
for (( c=0;c<${#chr_list[@]};++c )); do

N="${chr_list[$c]}"

dx cat "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}/logs/ukb24308_c${N}_vep_vcf_lists_for_batch_submission.tsv" |\
sed -e "s/^/c${N}-/1" -e 's/project.*file-/file-/' > batch_submission/c${N}_batches.tsv

done
```



Submit


NOTE: The applet is designed to run each job only once (zero retries). Adjust json input if you want retries.



```bash
chr_list=( $(echo {1..22} ) )

for (( c=0;c<${#chr_list[@]};++c )); do


N="${chr_list[$c]}"

dx run ${vep_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}" \
--input vep_chr=${N} \
--input vep_buffer=25000 \
--input vep_timeout=3000 \
--batch-tsv batch_submission/c${N}_batches.tsv \
--name "VEP batch submissions: chr${N}" \
--instance-type mem1_ssd1_v2_x36 \
--priority normal \
--brief \
-y |\
tr ',' '\n' > batch_submission/c${N}_batch_job_ids.txt


# This allows 3 min between submissions so span them over an hour.

sleep 180

done
```


Inspect the logs and see if any files failed. 

A few files should be skipped if you had already run the tests above.

Wait for ~15min and see the progress; you will see core and mem usage.




```bash
dx ls "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr21/vep/"
dx ls "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr21/vep/"
```


Cost is ~100 on low priority and ~300 on high priority.


### Monitoring


To get the state of submitted jobs:

```bash
echo -e "JOBID\tSTATE" > batch_submission/batch_jobs_status.txt

dx find jobs --applet ${vep_applet_id} --state "done" --json --origin-jobs --include-restarted -n 500 |jq -r '.[].id' |\
awk 'OFS="\t"{print $1,"DONE"}' >> batch_submission/batch_jobs_status.txt

dx find jobs --applet ${vep_applet_id} --state "running" --json --origin-jobs --include-restarted -n 500 |jq -r '.[].id' |\
awk 'OFS="\t"{print $1,"RUNNING"}' >> batch_submission/batch_jobs_status.txt

dx find jobs --applet ${vep_applet_id} --state "failed" --json --origin-jobs --include-restarted -n 500 |jq -r '.[].id' |\
awk 'OFS="\t"{print $1,"FAILED"}' >> batch_submission/batch_jobs_status.txt
```

Merge the tables

```bash
awk 'BEGIN{print "CHROM\tJOBID"}FNR==1 {f=FILENAME;gsub("_batch_job_ids.txt","",f);gsub("batch_submission/c","chr",f)}OFS="\t"{print f,$0}' batch_submission/*_batch_job_ids.txt |\
awk 'NR==FNR{s[$1]=$2;next}OFS="\t"{if($2 in s) print $0,s[$2]; else print $0,"NA"}' batch_submission/batch_jobs_status.txt - > batch_submission/batch_jobs_status.tsv
```


To summarize


```bash
awk 'NR>1{++S[$3];next}END{for(s in S) print s,S[s] }' batch_submission/batch_jobs_status.tsv
```


### Resubmitting failed batch jobs

There are two types of failures: batch job failures (unresponsive machine due to low priority or out of memory), and annotation job failures within each batch (a single VCF fails).

The system will report the first type, whereas the second type is shown in the log file.


Failing jobs should be resubmitted, perhabs with higher priority or higher memory (or lower buffer size).


The submission system is designed to avoid running the same job twice. Simply submit all jobs again and it will only run the failed ones


Instead, to have a clearer view of what jobs failed (e.g., to spot systematic errors), collect the ids of failing files and submit them again. 

If any of these batches becomes successful meanwhile (e.g., was running), the system will not submit the job again.

So even if we submit batch jobs more than once, there are no duplicates.

The applet itself is designed to quit if all files were previously annotated or if there is an ongoing run with the same input.


```bash
xargs -I {} dx describe --json {} < <(grep "FAILED" batch_submission/batch_jobs_status.tsv | cut -f2 ) |\
jq -r '.runInput.vep_vcfs."$dnanexus_link"' > batch_submission/batch_jobs_failed.txt
```




Create submission files


```bash
for ((N=1;N<=22;++N)); do
	
	grep -h -e "batch" -f batch_submission/batch_jobs_failed.txt batch_submission/c${N}_batches.tsv |\
	awk -v chr=${N} 'BEGIN{out_file="batch_submission/c"chr"_resubmit.tsv"}NR==1{header=$0;next}NR==2{print header > out_file}NR>1{print > out_file}'

done
```


Submit


```bash
chr_list=( $(echo {1..22} ) )

for (( c=0;c<${#chr_list[@]};++c )); do


N="${chr_list[$c]}"

if ls batch_submission/c${N}_resubmit.tsv &>/dev/null ; then

dx run ${vep_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}" \
--input vep_chr=${N} \
--input vep_buffer=5000 \
--input vep_timeout=9000 \
--batch-tsv batch_submission/c${N}_batches.tsv \
--name "VEP batch submissions: chr${N}" \
--tag "Retry" \
--instance-type mem1_ssd1_v2_x36 \
--priority high \
--brief \
-y |\
tr ',' '\n' >> batch_submission/c${N}_batch_job_ids.txt

fi

done
	
```

In case a single job keeps failing, it might be reasonable to change the options.





### Failing files



```bash
mkdir retry_submission

printf "retry_submission/\n" >> .gitignore
```



```bash


> retry_submission/input_files.txt

> retry_submission/annotated_files.txt

chr_list=( $(echo {1..22} ) )

for (( c=0;c<${#chr_list[@]};++c )); do


N="${chr_list[$c]}"

dx ls "WGS/chr${N}/vep_input/" >> retry_submission/input_files.txt

dx ls "WGS/chr${N}/vep/" >> retry_submission/annotated_files.txt

done
```



Explore

```bash
awk 'NR==FNR{gsub(".qc.sites.vep.tsv.gz","",$1);++vep[$1];next}{block=$1;gsub(".qc.sites.vcf.gz","",block)}{if(block in vep) ; else print block,$0}' OFS="\t" retry_submission/annotated_files.txt retry_submission/input_files.txt
```

Depending on how many files are there, decide on a stragety to group these files (e.g., one job for each file or one job for each chromosome).

Here are two examples:


To work with chr-level lists of VCFs that need to be annotated, grouped by chr, print the full file path with something like:

```bash
awk 'NR==FNR{gsub(".qc.sites.vep.tsv.gz","",$1);++vep[$1];next}{block=$1;gsub(".qc.sites.vcf.gz","",block)}{if(block in vep) ; else print block,$0}' OFS="\t" retry_submission/annotated_files.txt retry_submission/input_files.txt |\
awk '{split($1,block,"_");c=block[2];chr=block[2];gsub("c","chr",chr);path="/WGS/"chr"/vep_input/"$2;list_name="retry_submission/ukb24308_"c"_retry_vep_input_file_ids.txt";print path > list_name }'
```


Upload these lists


```bash
retry_file_ids=()

chr_list=( $(echo {1..22} ) )

for (( c=0;c<${#chr_list[@]};++c )); do


N="${chr_list[$c]}"

if ls retry_submission/ukb24308_c${N}_retry_vep_input_file_ids.txt &>/dev/null; then

retry_file_ids+=( $(dx upload --path "/WGS/chr${N}/logs/" --brief retry_submission/ukb24308_c${N}_retry_vep_input_file_ids.txt) )

fi


done
```


Submit new jobs with smaller buffer and longer timeout


Chr-level files:


```bash
vep_retry_list_job_ids=()


i=0


for (( c=0;c<${#chr_list[@]};++c )); do

N="${chr_list[$c]}"

if ls retry_submission/ukb24308_c${N}_retry_vep_input_file_ids.txt &>/dev/null; then

fid=${retry_file_ids[$i]}

echo "chr${N}:" $(dx describe --json "${fid}" | jq -r '.name')

IDX=$(dx run ${vep_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}" \
--input vep_chr=${N} \
--input vep_vcfs="${fid}" \
--input vep_buffer=1000 \
--input vep_timeout=10000 \
--name "VEP test submission: chr${N}" \
--instance-type mem1_ssd1_v2_x8 \
--tag "retry_failed" \
--priority high \
--brief \
-y)

vep_retry_list_job_ids+=( "$IDX" )



i=$(( i+1 ))


fi


done



```



I had 8 files that kept failing even with a time-out of two hours. I submitted them individually:


One submission file per vcf block:

```bash
awk 'NR==FNR{gsub(".qc.sites.vep.tsv.gz","",$1);++vep[$1];next}{block=$1;gsub(".qc.sites.vcf.gz","",block)}{if(block in vep) ; else print block,$0}' OFS="\t" retry_submission/annotated_files.txt retry_submission/input_files.txt |\
awk '{split($1,block,"_");c=block[2];chr=block[2];gsub("c","chr",chr);path="/WGS/"chr"/vep_input/"$2;list_name="retry_submission/"$1"_vep_input_file.txt";print path > list_name }'
```


Upload


```bash
retry_file_chrs=()
retry_file_ids=()

for vep_file in $(ls retry_submission/ukb24308_*_vep_input_file.txt); do

chr_number=$( echo ${vep_file} | sed -e 's/retry_submission\/ukb24308_c//1' -e 's/_b.*txt//')

retry_file_chrs+=( $chr_number )


retry_file_ids+=( $( dx upload --path "/WGS/chr${chr_number}/logs/" --brief ${vep_file} ) )


done

```



Jobs with large memory (32GB), large buffer (50k) and longer timeout (6hrs):



```bash
vep_retry_list_job_ids=()


for (( c=0;c<${#retry_file_ids[@]};++c )); do

file_id=${retry_file_ids[$c]}

chr_number="${retry_file_chrs[$c]}"

vep_job_id=$(dx run ${vep_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}" \
--input vep_chr=${chr_number} \
--input vep_vcfs="${file_id}" \
--input vep_buffer=50000 \
--input vep_timeout=$(( 6 * 60 * 60 )) \
--name "VEP test submission: chr${chr_number}" \
--instance-type mem1_ssd1_v2_x16 \
--tag "retry_block" \
--priority high \
--brief \
-y)


vep_retry_list_job_ids+=( "$vep_job_id" )

echo "$vep_job_id" "-->" "chr${chr_number}:" $(dx describe --json "${file_id}" | jq -r '.name')


done
```





## Processing time and cost



The strategy outlined here is to split chromosome files into smaller chunks of 50k variants, then process these in batches of 100 files.

[This documentation shows how to create these batches](resources/usr/doc/vep_input.md).

When split into 50k variants, WGS will be ~28k files.

The run time per batch (100 files x 50k variants) should be comparable across chromosomes since the VCF chunk size is constant.

It takes a bit longer to pull down the cache and resources for chr1 but difference is just a couple of minutes. 

Within batches of 100 files, the run time varies across files depending on the compexity of the underlying region; some variants take longer (e.g., coding). 

These longer annotation jobs are likely to fail due to excessive memory usage or if they exceed the runtime allowed by the applet (`vep_timeout` currently set to 30 min).


In general, the average runtime is around 10-15 mins per 50k variants.

The total runtime for 100 files depends on the machine size and the number of rounds needed.

In most scenarios, the runtime per batch of 100 files scales almost lineary with cores.

The applet will use `$(( $(nproc) * 8 /10 ))` to estimate the number of files to process in parallel.

On the default machine `mem1_ssd1_v2_x36`, the average was ~1 hour.

In addition to parallel processing of a 100 files within a single job, it is possible to submit up to 100 jobs in parallel.

This reduces the required time to annotate WGS to a few hours if jobs get scheduled immediately.

Low priority jobs get interrupted have considerable scheduling overhead (could take days to run 280 jobs).


The cost will depend on the priority and runtime.

The total cost (~280 batches, 100 files each, 50k variants per file) on high priority `mem1_ssd1_v2_x36` machines was £270. 

If opting for the larger machines with shorter runs (< 1hour), it is possible to run low priority jobs.

In practice, this was difficult and most jobs were terminated. The scheduling takes long too.





### TBD:

Missing resources for chromosome X.


