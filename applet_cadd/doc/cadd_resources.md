# Preparing CADD annotations


Resources were downloaded using URL Fetcher. 


The annotations were saved to "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/" with default name `GRCh38_v1.7.tar.gz`

The precalculated scores were saved to "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/"



This block shows how they can be split up for faster downloads

```bash
dx run \
--priority high \
--instance-type mem1_ssd2_v2_x8 \
--ssh app-cloud_workstation
```


Add upload agent

```bash
curl -O https://dnanexus-sdk.s3.amazonaws.com/dnanexus-upload-agent-1.5.33-linux.tar.gz

tar -xzvf dnanexus-upload-agent-1.5.33-linux.tar.gz

sudo mv dnanexus-upload-agent-1.5.33-linux/ua /usr/local/bin/

rm -rf dnanexus-upload-agent-1.5.33-linux.tar.gz dnanexus-upload-agent-1.5.33-linux
```



It takes an hour to download all files

```bash
dx cat "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/GRCh38_v1.7.tar.gz" |\
gunzip |\
tar -xvf - 2>&1 >> GRCh38_files.txt &
```


Create a list of files


```bash
awk -F"/" '{if($0 ~ "/$" || ( $0 ~ "vep" && ( $(NF-1) ~ "GL" || $(NF-1) ~ "KI" || $(NF-1) ~ "LRG")) ); else print }' GRCh38_files.txt > GRCh38_v1.7/CADD_GRCh38_v1_7_files_list.txt


dx upload --brief GRCh38_v1.7/CADD_GRCh38_v1_7_files_list.txt --path "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/GRCh38_v1.7/"
```



Create a list of folders and upload all

```bash
mapfile -t cadd_dirs < <(cat GRCh38_v1.7/CADD_GRCh38_v1_7_files_list.txt |\
awk -F"/" '{NF=NF-1;print}' OFS="/" |\
sort |\
uniq)


for ((f=0;f<${#cadd_dirs[@]};++f)); do

	ls ./"${cadd_dirs[$f]}"/*

	ua --do-not-compress --read-threads 4  --upload-threads 4 --project "$DX_PROJECT_CONTEXT_ID" --folder "/Resources/cadd_v1_7_data/${cadd_dirs[$f]}" ./"${cadd_dirs[$f]}"/*

done &
```




If not doing anything else, end session


```bash
terminate $DX_JOB_ID
```
