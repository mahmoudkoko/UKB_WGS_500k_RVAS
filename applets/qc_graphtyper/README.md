# UKBiobank WGS QC



## Input and outputs

The applet takes on a single input file that should contain a list of vcf files (full path) or file IDs (hash list).

It validates all records in this file, and if valid, runs pre-defined QC steps on them.

There is one mandatory "outputs list" file per VCF input (`${destination}/logs/${vcf_name_base}.qc.outputs.txt`) and ten optional outputs that will be created if there are variants in the VCF (4 plink files, bed file, indexed sites-only bcf, per-variant quality scores, per-variant genotype counts, and per-sample variant counts).

The "outputs list" file is tagged with the string `wgs_qc_log` and the chromosome/block are used as keys for additional annotations as properties (`key=value`).

The other outputs are tagged as `wgs_qc_output`

- If the destination directory already contains an outputs list (from a previous run), the VCF is skipped and not processed at all (it will not be skipped if the output is in another direcotry so be careful).

- If the VCF is empty, the outputs list acts as a place holder and simply contains NAs instead of hashes (`chromosome block vcf_hash NA NA NA NA NA NA NA NA NA NA`.

- If the VCF contains variants, the outputs list contains ten hashes and is structured as follows `chromosome block vcf_hash plink_log_hash pvar_hash pgen_hash psam_hash bed_hash sites_bcf_hash sites_index_hash sample_stats_hash variant_scores_hash geno_counts_hash`.



## Workflow

### Validation:

First, the applet will loop through the input file lines and attempt to verify them. This part of the workflow will run even on the smallest machine with two cores and 4GB ram.
The logic is as follows:

1. Resolving the file ID or path: At the beginning, the input file will be be verified to ensure that all lines are properly linked to GATK/GraphTyper VCFs. If the file link or path could not be traced to a VCF from field 23374 (GraphTyper), it will be rejected (status: invalid).

2. Checking for previous outputs: Once the file ID is resolved, it will attempt to locate any previous outputs (by looing for `${vcf_name_bas}.qc.outputs.txt` in the outputs directory - but not anywhere else!). If there are previous outputs, it will skip the VCF record (status: skipped).

3. Cheching for variants: Before downloading the whole file, the applet will attempt to read the beggining of the VCF using `dx cat`. If is able to read past the header, it assumes there is at least one variant record; it will carry this VCF forward for QC (status: valid). If the vcf file is empty (file ends right after the header), the applet removes it from the list of VCFs requiring QC (status: empty) and uploads an empty outputs list file to indicate that this file is successfully processed.

4. Failures: If the validation workflow fails at any step for whatever reason, it will be reported as such in the log file (status: failed). The applet will still continue if at least one file is a "valid" vcf but it will exit with error if there are no valid inputs at all (all files are invalid or failed).

5. At the end of this step, the applet will return a "Validation log" file named `${job_id}.validation.log` with summaries and detials of all stdout/stderr logs from this initial validation.


### Quality control:

Next, the applet will loop through validated VCFs returned by the validation workflow. This requires 4-6GB per file (for bcftools). If there is ram is lower than that, the applet will exit and report all files as 'failed' (so technically, it could be used to screen for VCFs that were not processed so far by a failing previous run for example). If the RAM is > 4GB, It will try to run as many files in parallel as the RAM allows. Note that the RAM is guessed from the instance name and not actually tested. 

This part of the workflow will perform predefined set of QC steps using bcftools:

1. Split multi-allelic sites and remove sites with more than 10 alt alleles (complex indels).
2. Set genotypes to missing if they have low GQ (<10), low DP (<8), low allele balance (heterozygous 0.9 < VAF < 0.1, homozygous VAF < 0.7).
3. Calculate AC, AF, average genotype quality and genotype counts (het, hom, ref, missing).
4. Count genotypes that have low to moderate genotype quality (GQ < 40) (this checks for a known issue with WES GQ distribution).


It will convert the outputs to plink2 files, create indexed sites-only bcf, and collect per-variant and per-sample statistics.

Note that the psam file is compressed with `gz` to conserve space.

Per-sample variant counts are calculated from these plink files:
1:sample id
2:hom-ref
3:hom-alt
4:hom-alt-snp
5:het
6:ts
7:tv
8:singletons
9:missing

Per-variant quality scores are queried from the sites-only vcfs:
1:id
2:type
3:NS
4:AC
5:AF
6:filter
7:qual
8:AAscore
9:QD
10:QD_alt
11:GQ_mean


Genotype counts are queried from sites-only vcfs
1:ID
2:ref after qc
3:het after qc
4:hom after qc
5:missing after qc
6:ref GQ < 40
7:het GQ < 40
8:hom GQ < 40



At the end of the QC step, it will generate a second "QC log" file named `${job_id}.qc.log` with summaries, lists of successful/failed files and detailed stdout/stderr logs for debugging.



## Building the applet


On your local machine, clone the applet locally and enter the directory.


```bash
git clone https://github.com/mahmoudkoko/UKB_WGS_QC.git
cd UKB_WGS_QC
```


Log-in to UKRAP using an *admin* token or password


```bash
dx login --token "string*goes*here"
```

Once verified, create a folder for applets to keep things organized.


```bash
dx mkdir 'Applets'
```

Build the applet using `dx build` and capture the applet ID. Option `-f` overwrites any previous builds with the same name, and `--brief` suppresses verpose output


```bash
qc_applet_id=$(dx build -f ./ -d "Applets/" --brief | jq -r .id)
```

DX may warn that the applet name does not match the folder name but that's not an issue.


## Testing the applet


Create a set of test input files to test the applet and upload them to a folder of your choice. The file must end with `.txt`. In this example, four empty files and a small file with ~20 vars are used. The folder is `Scratch/batches`. 


```bash

build_test_files_array=("file-GFBvpVjJYv1Z5ZfP9V2qQzgZ" "file-GFBv61jJYv1xGB0BJJ5KJkYY" "file-GFBv9fQJYv1gJpz59J27jyFZ" "file-GFBv9fQJYv1Vg4399GqzkbvY" "file-GFBv9f8JYv1Q5VqQG557k11Z")

build_test_files_list=$(printf "%s\n" ${build_test_files_array[@]} | dx upload - --parents --path "/Scratch/batches/build_test_vcf_list.txt" --brief)

```



You can confirm that the file is uploaded and contains four VCF files by reading it

```bash
dx cat "$build_test_files_list"
```


Submit a test job on high priority and a small machine. Normally you should allow at least 4GB ram (the minumum required per file) but four out of five test files are empty and will not require any processing. This example uses the smallest instance.

```bash
dx run ${qc_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:Scratch" \
--instance-type mem1_ssd1_v2_x2 \
--input ukb23374_vcf_list="${build_test_files_list}" \
--name "WGS QC applet: build test" \
--priority high \
--brief \
--watch \
-y
```


You should be able to see plink files in your destination folder:

```bash
dx ls Scratch/
dx ls Scratch/pfiles
dx ls Scratch/sites
dx ls Scratch/stats
dx ls Scratch/logs
```

The applet is now ready for batch submissions. Inspect the log files on the platform to see how they are structured.


## Scaling


The average file size is ~11GB and the run time is ~1 hour. Each file on average utilizes ~4GB of RAM and 1 core.

This can be tested with ~15 files from chr21 (b1001-1015). 

```bash
(seq -w 1 15 |\
xargs -I{} dx describe  "Bulk/GATK and GraphTyper WGS/GraphTyper population level WGS variants, pVCF format [500k release]/chr21/ukb23374_c21_b10{}_v1.vcf.gz"
 )|\
 grep -i size | tr -s ' ' | cut -f2 -d' '
 ```


Upload a test list of 15 files:


```bash
# upload a list of 18 files
chr21_test_files_list=$( (seq -w 1 15 |\
    xargs -I{} echo "Bulk/GATK and GraphTyper WGS/GraphTyper population level WGS variants, pVCF format [500k release]/chr21/ukb23374_c21_b10{}_v1.vcf.gz" )|\
    dx upload - --parents --path "/WGS/chr21/batches/chr21_test_vcf_list.txt" --brief)


# sumbit
dx run ${qc_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:WGS/chr21" \
--instance-type mem2_ssd1_v2_x16  \
--input ukb23374_vcf_list="${chr21_test_files_list}" \
--name "WGS QC: chr21 test" \
--priority high \
--brief \
--yes
```




Upload a test list of 15 files:


```bash
# upload a list of 18 files
chr21_test_files_list=$( (seq -w 16 20 |\
    xargs -I{} echo "Bulk/GATK and GraphTyper WGS/GraphTyper population level WGS variants, pVCF format [500k release]/chr21/ukb23374_c21_b10{}_v1.vcf.gz" )|\
    dx upload - --parents --path "/WGS/chr21/batches/chr21_test_vcf_list.txt" --brief)


# sumbit
dx run ${qc_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:WGS/chr21" \
--instance-type mem2_ssd1_v2_x8  \
--input mem_per_vcf=7 \
--input ukb23374_vcf_list="${chr21_test_files_list}" \
--name "WGS QC: chr21 test" \
--priority high \
--brief \
--yes
```



The average size is ~11GB. EC2 stance type `m5d` (`mem2_ssd1_v2_x`) offers 4 GB per core and is the best choice if running *high priority* jobs; the pricing is as follows:

Instance | RAM GB | Cost per hour (spot) | VCFs | Cost chr21/hr (~2,400 files) | Cost WGS/hr (~152k files)
---|---|---|---|---|----
mem1_ssd1_v2_x36 | 72 | £1 | 18 | ~£135 | £8.5k
mem1_ssd1_v2_x72 | 144 | £2 | 35 | ~£135 | £8.5k
mem2_ssd1_v2_x32 | 128 | £1 | 30 | ~£80 | ~£5k
mem2_ssd1_v2_x64 | 256 | £2 | 60 | ~£80 | ~£5k
mem2_ssd1_v2_x96 | 384 | £3 | 90 | ~£80 | ~£5k
mem3_ssd1_v2_x48 | 384 | £2 | 45 | ~£100 | ~£6.5
mem3_ssd1_v2_x64 | 512 | £2.6 | 60 | ~£100 | ~£6.5
mem3_ssd1_v2_x96 | 768 | £4 | 90 | ~£100 | ~£6.5


The number of runs required to process all files is:

Instance | Files per run | Runs chr21 (~2,400 files) | Runs WGS (~152k files)
---|---|---|---
mem1_ssd1_v2_x72 | 35 | 69 | 4353
mem2_ssd1_v2_x96 | 90 | 27 | 1690
mem3_ssd1_v2_x96 | 90 | 27 | 1690

With a maximum of 100 concurrent jobs and 2hrs per run (allowing scheduling overhead), the processing time is as follows

Instance | Files per 100 runs | Time chr21 (~2,400 files) | Time WGS (~152k files)
---|---|---|---
mem1_ssd1_v2_x72 | 3500 | 2hr | 4d
mem2_ssd1_v2_x96 | 9000 | 2hr | 2d
mem3_ssd1_v2_x96 | 9000 | 2hr | 2d






