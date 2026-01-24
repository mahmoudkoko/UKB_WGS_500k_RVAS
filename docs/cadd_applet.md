# Annotating indels with CADD 1.7

## Input files

Start a VM with CWS or TTYD

```bash
dx run app-cloud_workstation \
--instance-type mem1_ssd1_v2_x2 \
--priority high \
--ssh \
--brief
```

Install bcftools

```bash
sudo apt-get install bcftools
```


```bash
# set to contibutor
dx-su-contrib
```

Download and filter the variants for indels; split into chunks of 5k variants


```bash
mkdir cadd_test

for N in "Y"; do

dx cat "Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${N}_b0_v1.pvar" |\
awk -F' ' 'BEGIN{print "##fileformat=VCFv4.2"}NR==1{gsub(" ","\t")}NR>1{for(c = 6; c<=NF; ++c) $c = "."}{print }' OFS='\t' |\
bcftools view -V snps --write-index -Oz -o cadd_test/chr${N}.vcf.gz 


bcftools +scatter "cadd_test/chr${N}.vcf.gz" -Ob -o cadd_test/ -n5000 --prefix "chr${N}.indels."

rm cadd_test/chr${N}.vcf.gz*

done

```

Upload the VCFs

```bash
dx upload --no-progress --recursive cadd_test --path "/Temp/"
```

We will use 'Generate batch inputs' to pull the file IDs 

```bash
dx generate_batch_inputs \
--path "Temp/cadd_test" \
-o "cadd_test/cadd_bcfs" \
-i cadd_input="chrY.indels.(.*).bcf$"
```

We will reformat this to squach all lines in one batch

```bash
(head -n1 cadd_test/cadd_bcfs.0000.tsv;
cat cadd_test/cadd_bcfs.0000.tsv | \
tail -n+2 | \
awk -F'\t' -v OFS="\t" '{gsub(/[\r\n]/,"",$3)}
NR==1{bcfs=$2;ids=$3;next}
{bcfs=bcfs","$2;ids=ids","$3}
END{print "chrY","["bcfs"]","["ids"]"}') > cadd_test/cadd_test_batch.tsv
```


Run the applet

```bash
dx run Applets/CADD \
--batch-tsv cadd_test/cadd_test_batch.tsv \
--destination "/Temp/cadd_test/" \
--priority high \
--brief \
-y
```

This will take a while. Contiue with the remaining chromosomes


```bash
mkdir cadd_input

for N in {22..1}; do
# If adding chrX as well, note that it contains PAR contigs which needs special handling (e.g., replace with X and sort before saving as vcf/bcf). 

dx cat "Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${N}_b0_v1.pvar" |\
awk -F' ' 'BEGIN{print "##fileformat=VCFv4.2"}NR==1{gsub(" ","\t")}NR>1{for(c = 6; c<=NF; ++c) $c = "."}{print }' OFS='\t' |\
bcftools view -V snps --write-index -Oz -o chr${N}.vcf.gz &> /dev/null


bcftools +scatter "chr${N}.vcf.gz" -Ob -o cadd_input/ -n5000 --prefix "chr${N}.indels."

rm chr${N}.vcf.gz*

done &
```

This will take a while. Once done, upload the VCFs

```bash
dx upload --no-progress --brief --recursive cadd_input --path "/Temp/" &> uploads.log &
```

This also takes a while (several hours). Consider exiting the terminal and connecting back later on. Make sure the time out is long enough (e.g., `dx-set-timeout 24h`).


Once all files are uploaded, generate batch input tables

```bash
mkdir cadd_batch_files

echo -e "batch ID\tcadd_input\tcadd_input ID" > cadd_batch_input.tsv

# add '|X' to regexp to get chrX as well
dx find data --json --class file --state closed --path "/Temp/cadd_input" \
--name "^chr[1-9]|1[0-9]|2[0-2]\.indels\..*\.bcfs$" --name-mode regexp |\
jq -r '
    [range(0; length; 500) as $i | .[$i:$i+500]] | 
    to_entries[] | 
    "\(.key + 1)\t[" + ([.value[].describe.name] | join(",")) + "]\t[" + ([.value[].id] | join(",")) + "]"
  ' >> cadd_batch_input.tsv

# There are about 80 batches (jobs)
wc -l cadd_batch_input.tsv

# This allows 144GB/25 = 5GB of mem per job. The mem requirement isn't predictable but the applet will retry files that failed.

dx run Applets/CADD \
--batch-tsv cadd_batch_input.tsv \
--input cadd_jobs=25 \
--instance-type mem1_ssd1_v2_x72 \
--destination "Scratch/cadd_indels/" \
--priority high \
--brief \
-y
```
