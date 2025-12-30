# Annotating indels with CADD scores














- Pre-scored SNVs and indels (83GB)


```bash
dx download -o ./data/prescored/GRCh38_v1.7/no_anno/ \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/whole_genome_SNVs.tsv.gz" \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/whole_genome_SNVs.tsv.gz.tbi" \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/gnomad.genomes.r4.0.indel.tsv.gz" \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/gnomad.genomes.r4.0.indel.tsv.gz.tbi" 
```



- CADD docker image which we created earlier (8GB)


```bash
dx download -o ./sif/ \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/CADD_v1_7.sif" 
```



If everything is set up correctly, cadd should be accessible from the command line.


To run the test file that comes with it:

```bash
./CADD.sh ./test/input.vcf.gz
```

The result will be here
```bash
zcat ./test/input.tsv.gz
```



Using `dx-download-all-inputs`, VCFs passed to the applet as inputs will be downloaded under `${HOME}/in/` .
The path to these files will be saved in an array called `input_vcfs_path` 


Simulate 25 input files:


```bash
# initiate empty array
input_vcfs_path=()

for ((v=0;v<=24;++v)); do
	# Create a dir
	mkdir -p ${HOME}/in/input_vcfs/${v}

	# Copy the VCF in this dir
	cp ./test/input.vcf.gz ${HOME}/in/input_vcfs/${v}/

	# Update the input variable
	input_vcfs_path[${v}]="${HOME}/in/input_vcfs/${v}/input.vcf.gz"
done

# check
printf "%s\n" ${input_vcfs_path[@]}
```



Run all 25 files in parallel

```bash
sudo apt install parallel


mkdir ${HOME}/parallel_dir/

N_JOBS=5

parallel \
        --jobs "$N_JOBS" \
        --results "${HOME}/parallel_dir" \
        --joblog "${HOME}/parallel_dir/parallel.log" \
        --timeout 300 \
        ./CADD.sh ::: "${input_vcfs_path[@]}" &
```

Average processing time

```bash
cat ~/parallel_dir/parallel.log  |\
awk 'NR>1{t+=$4;next}END{printf "%.2fmin\n", t/(NR-1)/60 }'
```

(Quite slow ...)


The outputs include a log file and several vep output files. 


Right now, the output is in the same input dir and needs to be relocated after deleting the input files.


```bash
mkdir -p ${HOME}/out/cadd_log/ ${HOME}/out/cadd_scores/

for ((v=0;v<${#input_vcfs_path[@]};++v)); do

	rm ${input_vcfs_path[$v]}

	mv "${HOME}/in/input_vcfs/${v}" "${HOME}/out/cadd_scores/${v}"

done
```



```bash
# check
find "${HOME}/out/cadd_scores/" -name *.tsv.gz -exec ls {} +
```

The log files should also be uplodaded as a single record

```bash
echo "==== Summary ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

cat "${HOME}/parallel_dir/parallel.log"  |\
awk -F"\t" 'BEGIN{t=0;f=0;s=0}NR>1{t+=$4}NR>1{if($7==0) ++s ; else ++f}END{print "Pass/Fail: " s"/"f ; printf "Avergage time: %.2fmin\n", t/(NR-1)/60 }' >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"


echo "==== Parallel ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

cat "${HOME}/parallel_dir/parallel.log" >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

echo "==== Logs ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

find "${HOME}/parallel_dir/" -name std* -exec cat {} + >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

```


The outputs are ready for upload with `dx-upload-all-outputs`




###








Upload it to the project directory


```bash
dx upload CADD_v1_7.sif -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_docker/"
```



### CADD scripts docker image





### Test CADD


Download precalulated CADD scores for gnomAD indels


```bash
curl -O https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/gnomad.genomes.r4.0.indel.tsv.gz.tbi
curl -O https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/gnomad.genomes.r4.0.indel.tsv.gz
```

Move these files to their target location

```bash
mv gnomad.genomes.r4.0.indel.tsv.gz gnomad.genomes.r4.0.indel.tsv.gz.tbi CADD-scripts/data/prescored/GRCh38_v1.7/no_anno/
```


Download the annotation data (path may vary depending on where you saved the file)

```bash
dx download "$DX_PROJECT_CONTEXT_ID:/Resources/tmp_files/CADD_v1.7.tar.gz"
```



Once all are ready, move these files to their target location

```bash
mv GRCh38_v1.7 CADD-scripts/data/annotations/
```




Test CADD







Save the folder as file. There is no point in using a compression filter. See top files here:


```bash
find CADD-scripts/ -type f -exec du -h {} \; |  sort -rh | head -n20
```


Compress with 7z to leverage multi-threading


```bash
7z a -mx=0 -ms=off -mmt=$(nproc) CADD_v1_7_data.7z CADD-scripts/

7z a -mx=1 -mmt=10 CADD_v1_7_data2.7z CADD-scripts/ &

```

Upload


```bash
dx upload CADD_v1_7_data.7z -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_docker/"
```



## Prepare docker image with conda and snakemake


```bash

# save image
docker save cadd-scripts-v1_7 | gzip > vep_114_docker_amd64.tar.gz

# Upload to RAP
dx upload --brief -p --path $DX_PROJECT_CONTEXT_ID:/Resources/vep_114_docker/vep_114_docker_amd64.tar.gz vep_114_docker_amd64.tar.gz


```




```bash
cd ..

tar -cf - cadd_indels/ |\
zstd -T4 -o CADD_indels_annotation_data.tar.zst
```


Create a file list for parallel downloads

```bash

	echo "Downloading docker image"

	dx download --no-progress -o ./envs/ \\
	"\$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/CADD_v1_7.sif" 


	echo "Downloading precalculated gnomAD indels scores"

	dx download --no-progress -o ./data/prescored/GRCh38_v1.7/no_anno/ \\
	"\$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/gnomad.genomes.r4.0.indel.tsv.gz" \\
	"\$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/gnomad.genomes.r4.0.indel.tsv.gz.tbi" 


	# echo "Downloading precalculated WGS SNVs scores"

	# dx download --no-progress -o ./data/prescored/GRCh38_v1.7/no_anno/ \\
	# "\$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/whole_genome_SNVs.tsv.gz" \\
	# "\$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/whole_genome_SNVs.tsv.gz.tbi"


````
