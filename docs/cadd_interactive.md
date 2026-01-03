# Annotating VCFs with CADD scores interactively

## Preparing CADD resources for offline annotation

### Obtaining the required annotation resources


Create a directory in the target project

On the GUI, use 'Add' to create directories. 

In CLI:

```bash
dx mkdir -p "project-GzKk3XjJZz4ZgXzP2v1029qB:/Resources/cadd_v1_7_data"
```

Use URL Fetcher (`url_fetcher`) to download the prescored variants and annotation resources [listed here](https://cadd.gs.washington.edu/download). 


Submit five jobs to download these to the project directory. It will take a while to finish downloading the largest file (>300GB)

Use DX client from CLI or URL Fetcher GUI.

In the GUI, provide the links and checksum hashes.

In CLI:

- Annotations (340GB)


```bash
dx run app-url_fetcher \
-iurl="https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/GRCh38_v1.7.tar.gz" \
-ichecksum="205d3e702df3565efb424e2ca80c9d25" \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/Resources/cadd_v1_7_data/" \
--instance-type mem1_hdd1_v2_x4 \
--priority high \
--brief \
-y
```


- SNVs (80GB)

```bash
dx run app-url_fetcher \
-iurl="https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/whole_genome_SNVs.tsv.gz" \
-ichecksum="88577a55f1cd519d44e0f415ba248eb9" \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/Resources/cadd_v1_7_data/" \
--instance-type mem1_hdd1_v2_x2 \
--brief \
-y
```

- SNVs (index file)


```bash
dx run app-url_fetcher \
-iurl="https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/whole_genome_SNVs.tsv.gz.tbi" \
-ichecksum="347df8fac17ea374c4598f4f44c7ce8b" \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/Resources/cadd_v1_7_data/" \
--instance-type mem1_hdd1_v2_x2 \
--brief \
-y
```

- Indels (1.2GB)


```bash
dx run app-url_fetcher \
-iurl="https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/gnomad.genomes.r4.0.indel.tsv.gz" \
-ichecksum="4b9c685c96d396af4d001c2f7dd9d8f9" \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/Resources/cadd_v1_7_data/" \
--instance-type mem1_hdd1_v2_x2 \
--brief \
-y
```

- Indels (index file)


```bash
dx run app-url_fetcher \
-iurl="https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/gnomad.genomes.r4.0.indel.tsv.gz.tbi" \
-ichecksum="85f3d2daa9202c5915c0ce0f1c749a66" \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/Resources/cadd_v1_7_data/" \
--instance-type mem1_hdd1_v2_x2 \
--brief \
-y
```



### Set up and test CADD

Start a VM with cloud workstation or ttyd. Choose large storage > 500 GB


```bash
dx run app-cloud_workstation \
--priority high \
--instance-type mem1_hdd1_v2_x8 \
--ssh \
--brief \
-imax_session_length="3h" \
-y
```

Load docker image

```bash
docker run -it --name CADD-1_7-staging visze/cadd-scripts-v1_7:0.1.1 /bin/bash
```

```bash
docker run -it --name CADD-1_7-stage debian:bookworm-slim /bin/bash
```

You will be root.



Install tabix, bcftools, and parallel


```bash
apt update; apt install -y tabix bcftools parallel git
```



Download conda installation script


```bash
wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
```

Install conda


```bash
chmod +x ./Miniforge3-Linux-x86_64.sh
```


```bash
./Miniforge3-Linux-x86_64.sh -u -b
```




Clone CADD scripts


```bash
git clone https://github.com/kircherlab/CADD-scripts.git
```


```bash
mv CADD-scripts /opt/CADD
```


To use the SIF image created above, we will edit the config file of snakemake to point to the local file `${CADD}/src/sif/CADD_v1_7.sif` rather than an online docker repository


```bash
sed -i -e 's/containerized: "docker:.*"/containerized: "${CADD}\/src\/sif\/CADD_v1_7.sif"/' /opt/CADD/Snakefile
```


Edit the wrapper script 'CADD.sh' to remove dependency on path. This will make two changes (1) replace relative path with `/opt/CADD/` (2) add an argument to bind the CADD directory when using apptainer (signularity) to run CADD.


```bash
sed -i -e 's/export CADD=.*/export CADD="\/opt\/CADD"/' -e 's/--bind ${TMP_FOLDER}/--bind ${TMP_FOLDER} --bind ${CADD}/' /opt/CADD/CADD.sh
```

Copy the wrapper to the destination `/opt/conda/bin/`


```bash
cp /opt/CADD/CADD.sh /opt/conda/bin/run_cadd
```



This will make CADD available from PATH by default


```bash
run_cadd --help
```

Now move to installing other dependencies


Install snakemake


```bash
conda install -c conda-forge -c bioconda 'snakemake=8'
```

Install singularity

```bash
conda install -c conda-forge -c bioconda 'apptainer'
```


```bash
exit
```

Save the updated docker image 


```bash
docker commit CADD-1_7-staging cadd-v1_7
```

Remove the staging image

```bash
docker rm CADD-1_7-staging
```


Test

```bash
docker run \
--pull=never \
--platform linux/amd64 \
--volume /home/dnanexsus/sif/CADD_v1_7.sif:/opt/CADD/src/sif/CADD.sif \
cadd-v1_7 \
run_cadd //opt/CADD/test/input.vcf.gz
```



```bash
dx download "project-GzKk3XjJZz4ZgXzP2v1029qB:/Resources/cadd_v1_7_data/containers/CADD_v1_7.sif"
```





To run the test file that comes with it:

```bash
run_cadd /opt/CADD/test/input.vcf.gz
```

The result will be here

```bash
zcat ./test/input.tsv.gz
```













Download singularity source


```bash
wget https://github.com/apptainer/apptainer/releases/download/v1.4.1/apptainer_1.4.1_amd64.deb
```


Install singularity


```bash
apt install -y ./apptainer_1.4.1_amd64.deb
```

Download CADD's docker image and convert it to singularity image. This will take about half an hour; redirect the stderr and stdout to a log file while working in the background.


```bash
apptainer build CADD_v1_7.sif docker://visze/cadd-scripts-v1_7:0.1.1 >> sif_build.log 2>&1  &
```

Later on this will be available for download

```bash
dx download "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/containers/CADD_v1_7.sif"
```

Once done, upload to the project directory for future use


```bash
dx upload -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/containers/" CADD_v1_7.sif
```



```bash
dx download -o ./data/prescored/GRCh38_v1.7/no_anno/ \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/whole_genome_SNVs.tsv.gz" \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/whole_genome_SNVs.tsv.gz.tbi" \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/gnomad.genomes.r4.0.indel.tsv.gz" \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/gnomad.genomes.r4.0.indel.tsv.gz.tbi" 
```


4. 
If everything is set up correctly, cadd should be accessible from the command line.









Download the prescored variants locally

`./data/prescored/GRCh38_v1.7/no_anno/`


```bash
dx download  \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/whole_genome_SNVs.tsv.gz" \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/whole_genome_SNVs.tsv.gz.tbi" \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/gnomad.genomes.r4.0.indel.tsv.gz" \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/gnomad.genomes.r4.0.indel.tsv.gz.tbi" 
```






```bash
cp -r ./CADD-scripts/Snakefile ./CADD-scripts/config CADD-scripts/envs CADD-scripts/schemas CADD-scripts/src ~/
```
















```bash
mkdir cadd_docker && cd cadd_docker

```
















```bash
cat > Dockerfile <EOL
FROM ubuntu:24.04

# Install base tools
RUN apt-get update && apt-get install -y \\
    build-essential \\
    wget \\
    curl \\
    python3 \\
    python3-pip \\
    tabix \\
    bcftools \\
    parallel \\
    && apt-get clean


# Conda
COPY Miniforge3-Linux-x86_64.sh /tmp/pacakges/Miniforge3-Linux-x86_64.sh
RUN /bin/bash /tmp/pacakges/Miniforge3-Linux-x86_64.sh -u -b -p /usr/local/

# Snakemake
RUN conda config --set channel_priority strict
RUN conda install -p /usr/local/ -y -c conda-forge -c bioconda 'snakemake=8'


# Singularity
COPY apptainer_1.4.1_amd64.deb /tmp/pacakges/apptainer_1.4.1_amd64.deb
RUN apt install -y /tmp/pacakges/apptainer_1.4.1_amd64.deb

# CADD
COPY CADD-scripts /opt/cadd
COPY CADD-scripts/CADD.sh /usr/local/bin/



# Clean up
RUN rm -rf /tmp/packages/ && \\
    apt-get clean && \\
    rm -rf /var/lib/apt/lists/*


# Set default command
CMD ["/bin/bash"]
EOL
```


```bash
docker build -f ./Dockerfile -t cadd-scripts .
```



1. Start a VM with `Cloud Workstation` or `ttyd`. 



```bash
dx run \
--priority high \
--instance-type mem1_ssd2_v2_x8 \
--ssh app-cloud_workstation \
--brief \
-y
```


2. Clone the scripts


```bash
git clone https://github.com/kircherlab/CADD-scripts.git
```


2. Download CADD singularity image (8GB)


```bash
dx download -o ./sif/ \
"$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/CADD_v1_7.sif" 
```

3. Download pre-scored variants (83GB)




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
awk -F"\t" 'BEGIN{t=0;f=0;s=0}NR1{t+=$4}NR>1{if($7==0) ++s ; else ++f}END{print "Pass/Fail: " s"/"f ; printf "Avergage time: %.2fmin\n", t/(NR-1)/60 }' >> "${HOME}/out/cadd_log/${DX_JOB_ID}.cadd.log"


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


```
