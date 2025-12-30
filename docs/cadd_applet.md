# Creating the applet


Create a build directory


```bash
mkdir cadd_v1_7 && cd cadd_v1_7
```


Clone CADD scripts


```bash
git clone https://github.com/kircherlab/CADD-scripts.git
```



Create docker image




```bash
sudo tar \
--exclude=/proc \
--exclude=/tmp \
--exclude=/run \
--exclude=/boot \
--exclude=/home/dnanexus \
--exclude=/sys \
--exclude=/bin \
--exclude=/sbin \
--exclude=/opt/dnanexus \
--exclude=/opt/containerd \
-czf /tmp/CADD_v1_7_docker.tar.gz /
```


Import

```bash
docker import /tmp/CADD_v1_7_docker.tar.gz cadd_scripts:latest
```

Save

```bash
docker save cadd_scripts:latest > CADD_v1_7_scripts_docker.tar
```

Test

```bash
docker load < CADD_v1_7_scripts_docker.tar


docker run \
--pull=never \
--platform linux/amd64 \
cadd_scripts:latest \
cadd
```



Compress

```bash
gzip CADD_v1_7_scripts_docker.tar
```

Upload

```bash
dx upload CADD_v1_7_scripts_docker.tar.gz --path "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/envs/"
```




######


Download conda script

```bash
mkdir resources/home/dnanexus/conda


curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"

curl -O https://raw.githubusercontent.com/apptainer/apptainer/main/tools/install-unprivileged.sh

mv Miniforge3-Linux-x86_64.sh ./resources/home/dnanexus/conda/Miniforge3-Linux-x86_64

mv install-unprivileged.sh ./resources/home/dnanexus/conda/apptainer-install-unprivileged

chmod +x ./resources/home/dnanexus/conda/*

```


Create an entry point


```bash
mkdir src/
```


```bash
cat > src/main.sh <<EOL
#!/bin/bash

set -e -x -o pipefail

#####################
# Set up dependencies

# Instsall singularity
cat \${HOME}/conda/apptainer-install-unprivileged |\\
bash -s - \${HOME}/conda/  2>&1 > /dev/null


# Install conda
mv \${HOME}/conda/Miniforge3-Linux-x86_64 \${HOME}/conda/Miniforge3-Linux-x86_64.sh

bash \${HOME}/conda/Miniforge3-Linux-x86_64.sh -u -b -p \${HOME}/conda 2>&1 > /dev/null

# Export conda to path
export PATH=\${HOME}/conda/bin:\${PATH}

# Instsall snakemake
conda config --set channel_priority strict
conda install -p \${HOME}/conda/ -y -c conda-forge -c bioconda 'snakemake=8' 2>&1 > /dev/null


#########


main() {


	echo "Downloading ${#input_vcfs_path[@]} input VCFs: "

	printf "%s\n" ${input_vcfs_path[@]}


	dx-download-all-inputs --parallel



	echo "Moving to CADD dir"

	cd "\${HOME}/cadd_dir"


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



	echo "Downloading annotations. This takes > 1hr"

	dx cat "\$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/GRCh38_v1.7.tar.gz" |\\
	gunzip |\\
	tar -xf - -C ./data/annotations/


	echo "Annotating VCFs"

	mkdir \${HOME}/parallel_dir/

	N_JOBS=\$(cat \${HOME}/job_input.json  | jq -r '.cadd_jobs' || echo 1 )

	if parallel \\
	        --jobs "\$N_JOBS" \\
	        --results "\${HOME}/parallel_dir" \\
	        --joblog "\${HOME}/parallel_dir/parallel.log" \\
	        --timeout 300 \\
	        ./CADD.sh ::: "\${input_vcfs_path[@]}"; then

			echo "All CADD jobs were successful"
	else

			echo "Some CADD jobs failed"

	fi


	echo "Collecting results"


	mkdir -p "\${HOME}/out/cadd_scores/"

	for ((v=0;v< \${#input_vcfs_path[@]};++v)); do

		rm "\${input_vcfs_path[\$v]}"

		mv "\${HOME}/in/input_vcfs/\${v}" "\${HOME}/out/cadd_scores/\${v}"

	done



	mkdir -p "\${HOME}/out/cadd_log/"

	echo "==== Summary ==== " >> "\${HOME}/out/cadd_log/\${DX_JOB_ID}.cadd.log"

	cat "\${HOME}/parallel_dir/parallel.log"  |\\
	awk -F"\t" 'BEGIN{t=0;f=0;s=0}NR>1{t+=\$4}NR>1{if(\$7==0) ++s ; else ++f}END{print "Pass/Fail: " s"/"f ; printf "Avergage time: %.2fmin\n", t/(NR-1)/60 }' >> "\${HOME}/out/cadd_log/\${DX_JOB_ID}.cadd.log"

	cat "\${HOME}/out/cadd_log/\${DX_JOB_ID}.cadd.log"

	echo "==== Parallel ==== " >> "\${HOME}/out/cadd_log/\${DX_JOB_ID}.cadd.log"

	cat "\${HOME}/parallel_dir/parallel.log" >> "\${HOME}/out/cadd_log/\${DX_JOB_ID}.cadd.log"

	echo "==== Logs ==== " >> "\${HOME}/out/cadd_log/\${DX_JOB_ID}.cadd.log"

	find "\${HOME}/parallel_dir/" -name std* -exec cat {} + >> "\${HOME}/out/cadd_log/\${DX_JOB_ID}.cadd.log"


	echo "Uploading results"

	dx-upload-all-outputs
}
EOL
```



Create a json file for the applet


```bash
cat > dxapp.json <<EOL
{
  "name": "ukb_cadd_applet",
  "title": "CADD Annotation Applet",
  "summary": "WGS annotation applet. Takes a list of VCFs. Runs a bunch of pre-defined annotations. Creates TSV annotation files.",
  "version": "1.0.0",
  "inputSpec":
    [
      {
        "name": "input_vcfs",
        "label": "Input vcf file IDs",
        "help": "Array of vcf file IDs",
        "class": "array:file",
        "optional": false
      },
      {
        "name": "cadd_jobs",
        "label": "Parallel jobs",
        "help": "Number of files to process in parallel",
        "class": "int",
        "default": 5,
        "optional": true
      }
    ],
  "outputSpec":
    [
      {
        "name": "cadd_log",
        "label": "Log file",
        "help": "Job log: a text file with summaries and concatenated STDERR files",
        "class": "file",
        "patterns": ["*.log"],
        "optional": true
      },
      {
        "name": "cadd_scores",
        "label": "Output files",
        "help": "One tsv file per input VCF",
        "class": "array:file",
        "patterns": [".tsv.gz"],
        "optional": true

      }
    ],
  "runSpec":
    {
      "file": "src/main.sh",
      "interpreter": "bash" ,
      "systemRequirements": {"*": {"instanceType": "mem1_ssd1_v2_x36"} },
      "distribution": "Ubuntu",
      "release": "24.04",
      "version": "0",
      "execDepends": [{"name": "parallel"}, {"name": "rpm2cpio"}]
    },

  "access": { "network": ["*"] },
  "openSource": false
}
EOL
```





Compile

```bash
cadd_applet_id=$(dx build -f -d "$DX_PROJECT_CONTEXT_ID:/Applets/" ./ | jq -r .id)
```


Test with a small file


```bash
cadd_test_vcf_id=$(dx upload --brief ./resources/home/dnanexus/cadd_dir/test/input.vcf.gz)
```


```bash
cadd_test_job_id=$(dx run ${cadd_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/Scratch/" \
--instance-type "mem1_ssd1_v2_x2" \
--input input_vcfs="project-GzKk3XjJZz4ZgXzP2v1029qB:${cadd_test_vcf_id}" \
--name "CADD: test" \
--brief \
--priority high \
-y)
```
