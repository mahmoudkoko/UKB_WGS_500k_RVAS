# CADD environment

```bash
dx run \
--priority high \
--instance-type mem1_ssd1_v2_x2 \
--ssh app-cloud_workstation
```




Install tabix, bcftools, parallel


```bash
sudo apt install tabix bcftools parallel 
```



```bash
mkdir cadd_docker && cd cadd_docker

```




## Docker image (ubuntu)



Download singularity


```bash
wget https://github.com/apptainer/apptainer/releases/download/v1.4.1/apptainer_1.4.1_amd64.deb
```


Download conda installation script


```bash
curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
```

Download CADD scripts



```bash
git clone https://github.com/kircherlab/CADD-scripts.git
```


Edit the wrapper script to remove dependency on path



```bash
sed -i -e 's/export CADD=.*/export CADD="\/opt\/cadd"/' -e 's/--bind ${TMP_FOLDER}/--bind ${TMP_FOLDER} --bind ${CADD}/' ./CADD-scripts/CADD.sh
```



Edit the config file of snakemake to point to this folder rather than docker repo


```bash
sed -i -e 's/containerized: "docker:.*"/containerized: "${CADD}\/data\/containers\/CADD_v1_7.sif"/' ./CADD-scripts/Snakefile
```






Copy to bin






```bash
sudo cp CADD-scripts/CADD.sh /usr/local/bin/cadd

cp -r ./CADD-scripts/Snakefile ./CADD-scripts/config CADD-scripts/envs CADD-scripts/schemas CADD-scripts/src ~/
```





```bash
cat > Dockerfile <<EOL
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
## Singularity 




Install singularity

```bash
sudo apt install -y ./apptainer_1.4.1_amd64.deb
```


Download CADD 1.7 from docker and save it locally (takes a while but not too long)


```bash
apptainer build CADD_v1_7.sif docker://visze/cadd-scripts-v1_7:0.1.1 >> sif_build.log 2>&1  &
```


Upload the docker image for future use


```bash
dx upload -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/cadd_v1_7_data/containers/" CADD_v1_7.sif
```




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




