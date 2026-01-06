# Annotating VCFs with CADD 1.7 scores interactively
## Preparing CADD resources for offline annotation


CADD 1.7 has four components

1. CADD wrapper scripts available from github
2. CADD enviroment available as a docker image.
3. CADD annotations available for download from CADD website.
4. CADD prescored variants available for download from CADD website.

We will need to prepare those for offline use.


The final directory structure when running CADD is as follows:

```bash
data/annotations/GRCh38_v1.7/
data/prescored/GRCh38_v1.7/incl_anno/
data/prescored/GRCh38_v1.7/no_anno/
```

The annotations are downloaded as a tar file which will have to be untarred in the first directory.

We will need one of the prescored variants(annotated or no annotations).

Although it is not essential, it is easier to save the files on RAP using a similar dir struncture. Otherwise they can be organized when downloaded to the VM.

### Obtaining the required annotation resources

First, create a directory in the target project then download the required annotation files. It will take a while to finish downloading the largest file (>300GB)


- RAP GUI


Go to your project, and in the 'Manage' table use 'Add' to create new directories for CADD. 

Use URL Fetcher tool to download the prescored variants and annotation resources [listed here](https://cadd.gs.washington.edu/download). 

In the UI, provide the links and checksum hashes. Select instances with adequate disk space (largest file is 350GB)


- From CLI

If working on a RAP VM (cloud workstation or ttyd), use dx to create a new directory in the project directory. You need to indicate the project ID 

```bash
dx mkdir -p "${DX_PROJECT_CONTEXT_ID}:/Resources/cadd_v1_7_data"
```

DX client on a Desktop/Laptop/HPC will default to the selected project

```bash
dx mkdir -p "/Resources/cadd_v1_7_data/prescored/GRCh38_v1.7/no_anno"
```


Submit five jobs using `app-url_fetcher` to download the files to this new directory.

If running DX client from a VM (workstation or ttyd), you need the project ID in the destination path. 

If running from a desktop/laptop, remove `$DX_PROJET_CONTEXT_ID` as it will default to your selected project (or define that variable explicity in your local terminal session)

- Annotations (340GB)


```bash
dx run app-url_fetcher \
-iurl="https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/GRCh38_v1.7.tar.gz" \
-ichecksum="205d3e702df3565efb424e2ca80c9d25" \
--destination "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/" \
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
--destination "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/prescored/GRCh38_v1.7/no_anno/" \
--instance-type mem1_hdd1_v2_x2 \
--brief \
-y
```

- SNVs (index file)


```bash
dx run app-url_fetcher \
-iurl="https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/whole_genome_SNVs.tsv.gz.tbi" \
-ichecksum="347df8fac17ea374c4598f4f44c7ce8b" \
--destination "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/prescored/GRCh38_v1.7/no_anno/" \
--instance-type mem1_hdd1_v2_x2 \
--brief \
-y
```

- Indels (1.2GB)


```bash
dx run app-url_fetcher \
-iurl="https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/gnomad.genomes.r4.0.indel.tsv.gz" \
-ichecksum="4b9c685c96d396af4d001c2f7dd9d8f9" \
--destination "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/prescored/GRCh38_v1.7/no_anno/" \
--instance-type mem1_hdd1_v2_x2 \
--brief \
-y
```

- Indels (index file)


```bash
dx run app-url_fetcher \
-iurl="https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/gnomad.genomes.r4.0.indel.tsv.gz.tbi" \
-ichecksum="85f3d2daa9202c5915c0ce0f1c749a66" \
--destination "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/prescored/GRCh38_v1.7/no_anno/" \
--instance-type mem1_hdd1_v2_x2 \
--brief \
-y
```



### Prepare CADD as Singularity images



Start a VM with cloud workstation or ttyd.


```bash
dx run app-cloud_workstation \
--priority high \
--instance-type mem1_ssd1_v2_x2 \
--ssh \
--brief \
-imax_session_length="3h" \
-y
```


First step: we will save the docker image provided along with CADD as a local singularity image

Download singularity source


```bash
wget https://github.com/apptainer/apptainer/releases/download/v1.4.1/apptainer_1.4.1_amd64.deb
```


Install singularity


```bash
sudo apt install -y ./apptainer_1.4.1_amd64.deb
```


Build SIF image. This will take about 30-40 minutes; you could redirect the stderr and stdout to a log file while working in the background and move on to the next bit.


```bash
apptainer build /tmp/CADD_v1_7.sif docker://visze/cadd-scripts-v1_7:0.1.1 >> /tmp/CADD_v1_7.log 2>&1 &
```




Second step: We will set up a docker image that contains CADD scripts and their dependencies.

Load debian docker image in interactive mode (or ubuntu if you prefer)


```bash
docker run -it --name CADD-scripts-staging debian:bookworm /bin/bash
```

You will be root.


Update APT repos 

```bash
apt update
```

Install `wget`,`fuse2fs`, `git`, `tabix`, `bcftools`, and `parallel`


```bash
apt install -y tabix bcftools parallel git wget fuse2fs
```


Clone CADD scripts


```bash
git clone https://github.com/kircherlab/CADD-scripts.git
```

Move them to a permanent location

```bash
mv CADD-scripts /opt/CADD
```


There is a wrapper bash script called `${CADD}/CADD.sh` which is used to run CADD. It will parse your input arguments and use them ro run a Snakemake pipeline saved in `${CADD}/Snakefile`. The pipeline will call conda and signularity to manage CADD dependencies. 

CADD.sh will assume that the required config files are located in the same folder as the script itself, and that you have conda and sigularity installed and accessible from PATH. It will pull a docker image which is called `docker://visze/cadd-scripts-v1_7:0.1.1`.


First, edit the wrapper script `CADD.sh` to remove dependency on PATH and make it portable. This will make two changes (1) replace relative path with `/opt/CADD/` (2) add an argument to bind the CADD directory when using apptainer (signularity) to run CADD.


```bash
sed -i -e 's/export CADD=.*/export CADD="\/opt\/CADD"/' -e 's/--bind ${TMP_FOLDER}/--bind ${TMP_FOLDER} --bind ${CADD}/' /opt/CADD/CADD.sh
```

Copy the wrapper to the destination `/usr/local/bin/`


```bash
cp /opt/CADD/CADD.sh /usr/local/bin/run_cadd
```


This will make CADD available from PATH by default

```bash
run_cadd --help
```

Second, edit the config file to use an SIF image from a local directory rather than pulling a docker image from `docker://`. 


Edit the config file to point to a local file `${CADD}/src/sif/CADD_v1_7.sif`


```bash
sed -i -e 's/containerized: "docker:.*"/containerized: "${CADD}\/src\/sif\/CADD_v1_7.sif"/' /opt/CADD/Snakefile
```


Third, install the dependencies:conda, snakemake and sigularity.


Download miniconda installation script


```bash
wget "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
```

Make it executable

```bash
chmod +x ./Miniforge3-Linux-x86_64.sh
```

Install conda

```bash
./Miniforge3-Linux-x86_64.sh -u -b -p '/opt/miniforge3'
```

Remove the script

```bash
rm ./Miniforge3-Linux-*
```

Install snakemake using conda


```bash
/opt/miniforge3/bin/conda install -y -c conda-forge -c bioconda 'snakemake=8'
```

Install singularity

```bash
/opt/miniforge3/bin/conda install -y -c conda-forge -c bioconda 'apptainer'
```

Add the conda bins to path


```bash
ln -s /opt/miniforge3/bin/* /usr/local/bin/
```

The dependencies should now be in your PATH

```bash
conda --version && snakemake --version && apptainer --version
```

Exit the interactive shell 

```bash
exit
```

Commit the changes and save an updated docker image 


```bash
docker commit CADD-scripts-staging cadd_scripts_v1_7
```


Save the docker image as a singularity image. This will take a while.


```bash
apptainer build /tmp/CADD_scripts_v1_7.sif docker-daemon://cadd_scripts_v1_7:latest >> /tmp/CADD_scripts_v1_7.log 2>&1 &
```


Third step: Test the Singularity images

Once both steps are done, you will have two SIF files `/tmp/CADD_v1_7.sif` (CADD docker environment as provided by the authors; repackaged as singularity image) and `/tmp/CADD_scripts_v1_7.sif` (CADD scripts provided in github repo, repackaged as singularity image).


Now run cadd from the singularity image


```bash
singularity exec \
--writable-tmpfs \
--bind /tmp/:/opt/CADD/src/sif/ \
/tmp/CADD_scripts_v1_7.sif \
run_cadd "/opt/CADD/test/input.vcf.gz"
```


This test will make sure that your 'CADD scripts container' is running and is reading the second singularity container which has the actual CADD annotator.

Note that the annotation will fail because we do not have the required annotation files but it should progress through the loading part.


Now that we have everything running, upload the two images to the project directory for future use


```bash
dx upload -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/containers/" /tmp/CADD_scripts_v1_7.sif /tmp/CADD_v1_7.sif
```


If you want to keep using this VM, note that there are a few running docker containers and loaded images. 


```bash
docker ps -a; docker images
```

Delete all images and containers

```bash
docker rm CADD-scripts-staging
docker rmi cadd_scripts_v1_7 debian:bookworm
```


Shut down this machine

```bash
dx terminate $DX_JOB_ID
```




### Run CADD from Singularity images


Here we will test CADD along with its annotations

Start a VM (either using cloud workstation or ttyd)

Select a large machine; We need 500 GB for the annotations and prescored variants.

With workstation:

```bash
dx run app-cloud_workstation \
--priority high \
--instance-type mem1_hdd1_v2_x8 \
--ssh \
--brief \
-imax_session_length="4h" \
-y
```

1. **Prepare the annotations**

Create a directory for the annotations and singularity images

```bash
mkdir -p ${HOME}/cadd_working_dir/cadd_v1_7_data
```

At the beginning we made sure to save the prescored variants under the same dir structure expected by CADD; our files in RAP are saved in `/Resources/cadd_v1_7_data/prescored/GRCh38_v1.7/no_anno/`.

We will download the folder `prescored` 

```bash
dx download "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/prescored" \
--recursive \
-o "${HOME}/cadd_working_dir/cadd_v1_7_data/" 
```



Now we will download the singularity images


```bash
dx download "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/containers" \
--recursive \
-o "${HOME}/cadd_working_dir/cadd_v1_7_data/" 
```



The third thing we need to download is the annotations. After download, we will need to untar the `tar.gz` file (340GB), which means we need two passes over the file.

Therefore, instead of downloading it, we will stream it with `cat` and pipe the output to `tar` to save some time (i.e., read once).

This will reduce the time needed to ingest the annotations.

Also, we will make sure that the annotations are saved in the correct path expected by CADD.

The tar file contains a folder called `GRCh38` which needs to be under `${CADD}/data/annotations`, where `${CADD}` is the home directory for CADD scripts. 

Create a directory for the annotations.

```bash
mkdir -p ${HOME}/cadd_working_dir/cadd_v1_7_data/annotations/
```


It takes an hour to download all files. We will redirect the file list to a text file and run in the background.


```bash
dx cat "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/GRCh38_v1.7.tar.gz" |\
gunzip |\
tar -xvf - -C ${HOME}/cadd_working_dir/cadd_v1_7_data/annotations/ 2>&1 >> GRCh38_files.txt &
```

There is little practical value in keeping `tar.gz` format since the platform supports directory downloads. Also, having the data stored in the same structure that is required to run CADD makes streamlining the pipeline easier.

To simplify the download process in the future, we will get rid of the tarball. Instead, we will upload the untarred directory back to the platform along with the prescored variants and singularity images. 


DX upload can take in a directory name as an input but it is not parallelized. 

Instead, we will use another tool from DNANexsus called upload agent (`ua`) to upload these files in parallel. The upload agent does not support directory uploads so we will use the list of files we created with `tar -xv` to upload all files indiviually but in parallel.

The upload agent is a precompiled binary. We will download it and move it to PATH.

```bash
curl -O https://dnanexus-sdk.s3.amazonaws.com/dnanexus-upload-agent-1.5.33-linux.tar.gz

tar -xzvf dnanexus-upload-agent-1.5.33-linux.tar.gz

sudo mv dnanexus-upload-agent-1.5.33-linux/ua /usr/local/bin/

rm -rf dnanexus-upload-agent-1.5.33-linux.tar.gz dnanexus-upload-agent-1.5.33-linux

ua --help
```

As noted, the upload agent doesnt support directory uploads.

We will use the list of files to group them by directory, then upload the files in each directory. 

Optionally, we can remove the decoy contigs which are not needed for a standard analysis

This removes any vep files referring to chromosomes other than 1-22,X,Y,MT

```bash
awk -F"/" '{if($0 ~ "/$" || ( $0 ~ "vep" && ( $(NF-1) ~ "GL" || $(NF-1) ~ "KI" || $(NF-1) ~ "LRG")) ); else print }' GRCh38_files.txt > CADD_GRCh38_v1_7_files_list.txt
```


From this list, we create an array of folder names by parsing the paths


```bash
mapfile -t cadd_dirs < <(cat CADD_GRCh38_v1_7_files_list.txt |\
awk -F"/" '{NF=NF-1;print}' OFS="/" |\
sort |\
uniq)
```

We create a target directory in the analysis project

```bash
dx mkdir $DX_PROJECT_CONTEXT_ID:Resources/cadd_v1_7_data/annotations 
```

This bit loops over the local directories and uploads all the files inside each directory in parallel to a target directory with the same name

```bash
for ((f=0;f<${#cadd_dirs[@]};++f)); do

	echo "Uploading the following files in:"
	ls "${HOME}/cadd_working_dir/cadd_v1_7_data/annotations/${cadd_dirs[$f]}"

	ua \
	--do-not-compress \
	--read-threads 4  \
	--upload-threads 4 \
	--project "$DX_PROJECT_CONTEXT_ID" \
	--folder "/Resources/cadd_v1_7_data/annotations/${cadd_dirs[$f]}" \
	"${HOME}/cadd_working_dir/cadd_v1_7_data/data/annotations/${cadd_dirs[$f]}"/*

done && echo 'Finished upload' &
```

Again, this takes a while but hopefully faster than the download step.

This allows for downloading these files in the future with one pass (not needed now since we have the files locally already).

```bash
dx download "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/annotations" \
--recursive \
-o "${HOME}/cadd_dir/cadd_v1_7_data/" 
```


A more convenient approach to steamline the downloads (e.g., inside a script) is to download the full `data` directory as follows:


```bash
dx download "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data" \
--recursive \
--no-progress \
--lightweight \
-o "${HOME}/cadd_working_dir/" 
```

Now we have all the required inputs


We will need to install singularity on this VM


Download singularity source


```bash
wget https://github.com/apptainer/apptainer/releases/download/v1.4.1/apptainer_1.4.1_amd64.deb
```


Install singularity


```bash
sudo apt install -y ./apptainer_1.4.1_amd64.deb
```


We will now create a directory for the VCFs.


```bash
mkdir ${HOME}/cadd_working_dir/input_vcfs
```

We will copy the test file from inside the SIF image

```bash
singularity exec \
${HOME}/cadd_working_dir/cadd_v1_7_data/containers/CADD_scripts_v1_7.sif \
cp /opt/CADD/test/input.vcf.gz ${HOME}/cadd_working_dir/input_vcfs/test.vcf.gz
```

It has a few variants

```bash
zcat ${HOME}/cadd_working_dir/input_vcfs/test.vcf.gz
```

Now we will bind the directories and run CADD

```bash
singularity exec \
#--writable-tmpfs \
--bind ${HOME}/cadd_working_dir/input_vcfs:/opt/CADD/input_vcfs \
--bind ${HOME}/cadd_working_dir/cadd_v1_7_data/annotations:/opt/CADD/data/annotations \
--bind ${HOME}/cadd_working_dir/cadd_v1_7_data/prescored:/opt/CADD/data/prescored \
--bind ${HOME}/cadd_working_dir/cadd_v1_7_data/containers:/opt/CADD/src/sif \
${HOME}/cadd_working_dir/cadd_v1_7_data/containers/CADD_scripts_v1_7.sif \
run_cadd "/opt/CADD/input_vcfs/test.vcf.gz"
```

Check the results. You should see CADD raw and scaled scores

```bash
zcat ${HOME}/cadd_working_dir/input_vcfs/test.tsv.gz
```


3. **Automate CADD for multiple files**

We can use `parallel` inside the singularity container to run several files

First we need a temporary directory for parallel

```bash
mkdir ${HOME}/cadd_working_dir/parallel/
```

We will simulate 10 input files:


```bash
for ((v=1;v<=10;++v)); do

	cp ${HOME}/cadd_working_dir/input_vcfs/test.vcf.gz ${HOME}/cadd_working_dir/input_vcfs/${v}.vcf.gz

done

printf "%s.vcf.gz\n" {1..10} > ${HOME}/cadd_working_dir/parallel/input_vcfs_list.txt
```



Run (sequentially) 

```bash
singularity exec \
#--writable-tmpfs \
--bind ${HOME}/cadd_working_dir/parallel:/opt/CADD/parallel \
--bind ${HOME}/cadd_working_dir/input_vcfs:/opt/CADD/input_vcfs \
--bind ${HOME}/cadd_working_dir/cadd_v1_7_data/annotations:/opt/CADD/data/annotations \
--bind ${HOME}/cadd_working_dir/cadd_v1_7_data/prescored:/opt/CADD/data/prescored \
--bind ${HOME}/cadd_working_dir/cadd_v1_7_data/containers:/opt/CADD/src/sif \
${HOME}/cadd_working_dir/cadd_v1_7_data/containers/CADD_scripts_v1_7.sif \
parallel \
        --jobs 2 \
        --results "/opt/CADD/parallel" \
        --joblog "/opt/CADD/parallel/parallel.log" \
        --timeout 600 \
        run_cadd :::: /opt/CADD/parallel/input_vcfs_list.txt &
```


Observe the memory and cores with `htop` to determine how to scale parallel jobs with the instance size.

Average processing time

```bash
cat ${HOME}/cadd_working_dir/parallel/parallel.log  |\
awk 'NR>1{t+=$4;next}END{printf "%.2fmin\n", t/(NR-1)/60 }'
```


4. **Packing CADD in an applet**


When running applets, it is possible to give an array of files IDs as an input.

These files can be downloaded using `dx-download-all-inputs` where each file will be in a separate directory  under `${HOME}/in/`. The directory names will reflect the index in the input array. The path to these files will be saved in an array called `input_vcfs_path`. 

It is possible to cut the first 5 columns and use them as input for CADD (removing chr prefix). These can then be saved in CADD's working dir.


```bash
mkdir -p ${HOME}/out/cadd_scores/

for ((v=0;v<${#input_vcfs_path[@]};++v)); do

	input_vcf_file=$(ls "${input_vcfs_path[$v]}/*.vcf.gz")

	zless "${input_vcfs_path[$v]}/${input_vcf_file}" |\
	awk '{gsub(/^chr/,"",$1);gsub(/M/,"MT",$1);NF=5; print}' OFS="\t" |\
	gzip > "${HOME}/cadd_working_dir/input_vcfs/${input_vcf_file}"

	# Delete the input file
	rm -rf ${input_vcfs_path[$v]}

	# Update the path
	${input_vcfs_path[$v]}="${HOME}/cadd_working_dir/input_vcfs/${input_vcf_file}"


done
```


A list of these files can then be passed to parallel as we have shown above.

The output needs to be relocated to a new location under `${HOME}/out/`, each in its own directory, with numeric dir names to reflect the output array.


```bash
mv ${HOME}/in/input_vcfs ${HOME}/out/cadd_scores

for ((v=0;v<${#input_vcfs_path[@]};++v)); do

	if [[ -f "${input_vcfs_path[$v]}" ]]; then
		mv "${input_vcfs_path[$v]}" "${HOME}/out/cadd_scores/${v}/"
	fi

done
```

The outputs are ready for upload with `dx-upload-all-outputs`




