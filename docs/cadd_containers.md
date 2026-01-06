
## Singularity 






```bash

```

If not doing anything else, end session


```bash
dx terminate $DX_JOB_ID
```




wrapper main script (e.g., applet)


add validation script


modify validation to indel script to filter indels and strip chr prefix

add download all inputs

add script to stage cadd

add line read all input files from a given folder using find

add line to remove all inputs once done


docker bind IO directory as /opt/cadd/io
docker bind tmp directory as /tmp
docker bind annotations, containers, prescored as /opt/cadd/data/*


parralel use all files in IO as input to cadd and run nproc






```bash
# check
find "${HOME}/out/cadd_scores/" -name *.tsv.gz -exec ls {} +
```

The log files should also be uplodaded as a single record

```bash
echo "==== Summary ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

cat "${HOME}/parallel_dir/parallel.log"  |\
awk -F"\t" 'BEGIN{t=0;f=0;s=0}NR1{t+=$4}NR>1{if($7==0) ++s ; else ++f}END{print "Pass/Fail: " s"/"f ; printf "Avergage time: %.2fmin\n", t/(NR-1)/60 }' >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"


echo "==== Parallel ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

cat "${HOME}/parallel_dir/parallel.log" >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

echo "==== Logs ==== " >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

find "${HOME}/parallel_dir/" -name std* -exec cat {} + >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"

```






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


```
