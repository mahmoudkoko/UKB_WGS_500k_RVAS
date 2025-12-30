# Preparing annotation cache and databases



```bash

dx run \
--priority high \
--instance-type mem1_ssd1_v2_x8 \
--ssh app-cloud_workstation


```


Some useful apps

```bash
sudo apt install tabix bcftools samtools parallel

sudo pip install numpy pandas pandas-stubs matplotlib pyBigWig CrossMap

```


### VEP Docker


```bash
mkdir vep_docker && cd vep_docker
# download docker image
docker pull --platform linux/amd64 ensemblorg/ensembl-vep:latest

# add instructions to install tabix and samtools
cat > Dockerfile << 'EOF'
FROM ensemblorg/ensembl-vep:latest
USER root
RUN apt-get update && apt-get install -y \
    samtools \
    tabix \
    && rm -rf /var/lib/apt/lists/*
USER vep
EOF

# build with newly installed programs
docker build -t vep_114 .

# save image
docker save vep_114 | gzip > vep_114_docker_amd64.tar.gz

# Upload to RAP
dx upload --brief -p --path $DX_PROJECT_CONTEXT_ID:/Resources/vep_114_docker/vep_114_docker_amd64.tar.gz vep_114_docker_amd64.tar.gz

cd ..

rm -rf vep_docker
```


### VEP plugins:


```bash
mkdir vep_anno && cd vep_anno

git clone --branch release/114 --single-branch https://github.com/Ensembl/VEP_plugins.git

mv VEP_plugins vep_plugins


# add a custom plugin to annotate missense variants
# URL: add

cat > MiSc.pm <<EOL
#<plugin code below>
EOL


mv MiSc.pm vep_plugins/

# Add UTRAnnotator resource file
curl -O https://raw.githubusercontent.com/Ensembl/UTRannotator/refs/heads/master/uORF_5UTR_GRCh38_PUBLIC.txt

mv uORF_5UTR_GRCh38_PUBLIC.txt vep_plugins/

# Clone loftee
git clone --branch grch38 --single-branch https://github.com/konradjk/loftee.git

cd loftee

# Download the conservation database
curl -O https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/loftee.sql.gz

# Unpack
gunzip loftee.sql.gz

cd ..

# move the data into the plugins folder
mv ./loftee/* ./vep_plugins

# Compress into a tarball
tar -czf vep_114_plugins.tar.gz vep_plugins/


# upload

dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_docker/" vep_114_plugins.tar.gz

cd ..

# delete tmp dir/files
rm -rf vep_anno
```




### VEP Cache

```bash
mkdir vep_cache && cd vep_cache

# Download cache (30 GB)

curl -O https://ftp.ensembl.org/pub/release-114/variation/indexed_vep_cache/homo_sapiens_vep_114_GRCh38.tar.gz


# Unpack

tar -xzf homo_sapiens_vep_114_GRCh38.tar.gz


# pack each chromosome into its own tar


chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

chr=${chr_list[$c]}

echo "Packing chromosome $chr"

mkdir chr"$chr"

if tar -cf chr"$chr"/vep_cache_chr${chr}.tar homo_sapiens/114_GRCh38/${chr} homo_sapiens/114_GRCh38/chr_synonyms.txt homo_sapiens/114_GRCh38/info.txt; then
	
	dx upload --brief -p --path $DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/ --recursive chr"$chr"

	rm -rf homo_sapiens/114_GRCh38/${chr} chr"$chr"

	echo "Done"

fi

done

cd ..

rm -rf vep_cache
```


### VEP Fasta


```bash
mkdir vep_fasta && cd vep_fasta

# Download fasta
curl -O https://ftp.ensembl.org/pub/release-114/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz

# Split per chromosome

zcat Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz |\
awk -F" " 'BEGIN{for (c=1;c<=22;++c)  chr_list[c]=c;chr_list["X"]="X";chr_list["Y"]="Y"}/^>/{chr_name=$1;gsub(/[>]/,"",chr_name)}{if(chr_name in chr_list) { print $0 > ("human_reference_chr"chr_name".fa") } else next;}'


# Compress chr files with bgzip and index

chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

chr=${chr_list[$c]}


	if bgzip human_reference_chr${chr}.fa && samtools faidx human_reference_chr${chr}.fa.gz; then
		
		echo "Chromosome $chr"

	fi

done



# Download the ancestor fasta (loftee data)

curl -O https://personal.broadinstitute.org/konradk/loftee_data/GRCh38/human_ancestor.fa.gz

# Split per chromosome

zcat human_ancestor.fa.gz |\
awk -F" " 'BEGIN{for (c=1;c<=22;++c)  chr_list[c]=c;chr_list["X"]="X";chr_list["Y"]="Y"}/^>/{chr_name=$1;gsub(/[>]/,"",chr_name)}{if(chr_name in chr_list) { print $0 > ("human_ancestor_chr"chr_name".fa") } else next;}'



# Compress chr files with bgzip and index

chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

	chr=${chr_list[$c]}


	if bgzip human_ancestor_chr${chr}.fa && samtools faidx human_ancestor_chr${chr}.fa.gz; then

		echo "Chromosome $chr"

	fi

done




# compress in tarballs and upload


for (( c=0;c<${#chr_list[@]};++c )); do

	chr=${chr_list[$c]}

	mkdir chr${chr}

	if tar -cf chr${chr}/vep_fasta_chr${chr}.tar human_reference_chr${chr}.fa* human_ancestor_chr${chr}.fa*; then

		dx upload --brief -p --path $DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/ --recursive "chr$chr"

		rm -rf "chr$chr"

		echo "Uploaded chromosome $chr"

	fi

done

cd ..


# delete temp

rm -rf vep_fasta
```


### Transcripts to genes

```bash

# get gene names for all transcripts

mkdir ensembl && cd ensembl

# batch 1 GRCh38
seq 76 114 |\
xargs -I% -P1 wget https://ftp.ensembl.org/pub/release-%/gtf/homo_sapiens/Homo_sapiens.GRCh38.%.gtf.gz



# batch 2 GRCh37
seq 55 75 |\
xargs -I% -P1 wget https://ftp.ensembl.org/pub/release-%/gtf/homo_sapiens/Homo_sapiens.GRCh37.%.gtf.gz




for ((v=114;v>=55;--v)); do

  zcat Homo_sapiens.GRCh3*.$v.gtf.gz  |\
  awk -F"\t" '$3 == "transcript"{gsub("\"","",$9);gsub("; ",";",$9);split($9,info,";"); print $9}' |\
  awk -F";"  '{for(c = 1; c<NF; ++c) {field_name=$c; field_info=$c; gsub(" .+","",field_name);gsub(".+ ","",field_info);transcript_info[field_name]=field_info}}{print transcript_info["gene_name"], transcript_info["gene_id"], transcript_info["transcript_id"]}' OFS="\t" |\
  awk -F "\t" -v version=$v '{if($1=="") $1 = "NA"; print $0,version}' OFS="\t"
done |\
  awk -F"\t" 'BEGIN{print "#Gene\tID\tFeature\tRelease"}{if($3 in transcripts) next; else ++transcripts[$3]}{print}' |\
  gzip > ensembl_genes_to_transcripts.tsv.gz


dx upload --path $DX_PROJECT_CONTEXT_ID:/Resources/tmp_files/ ensembl_genes_to_transcripts.tsv.gz
```


### Region-based annotations



#### TSS boundaries

Needed to define

```bash
mkdir tss_boundaries && cd tss_boundaries

# Download 

curl -O https://ftp.ensembl.org/pub/release-114/gtf/homo_sapiens/Homo_sapiens.GRCh38.114.gtf.gz

# Extract TSS and split per chromosome
zcat Homo_sapiens.GRCh38.114.gtf.gz |\
awk -F"\t" '{for(c=1;c<=22;++c) ++chr[c]; ++chr["X"]; ++chr["Y"]}{if($3 == "gene" && $1 in chr ) ; else next;}$7 == "+"{tss_position=$4; tss_start=$4; tss_end=$4}$7 == "-"{tss_position=$5; tss_start=$5; tss_end=$5}{split($NF,rec,";"); gene_id=rec[1]; gsub("gene_id","",gene_id); gsub("\"","",gene_id)}{tss_start += -2000; tss_end += 2000;if(tss_start < 0) tss_start=0}{print $1,tss_start,tss_end,gene_id }' OFS="\t" |\
sort -k1,1V -k2,2n -k3,3n -k4,4V |\
bgzip > Homo_sapiens.GRCh38.114.bed.gz

tabix -p bed Homo_sapiens.GRCh38.114.bed.gz



# compress, index and upload

chr_list=( $(echo {1..22} X Y) )


for (( c=0;c<${#chr_list[@]};++c )); do

# get chr name from array

chr=${chr_list[$c]}

# make tmp dir

mkdir "chr$chr/"

tabix Homo_sapiens.GRCh38.114.bed.gz $chr | bgzip > chr$chr/tss_chr$chr.bed.gz && tabix -p bed chr$chr/tss_chr$chr.bed.gz

# upload

echo "Uploading chromosome $chr"

dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

# delete tmp

rm -rf "chr$chr"

done  &


cd ..

rm -rf tss_boundaries

```




#### TAD boundaries

Needed to define

```bash
mkdir tad_boundaries && cd tad_boundaries

# Download 

curl -O https://cb.csail.mit.edu/tadmap/TADMap_scaffold_hs.bed

# Extract TSS and split per chromosome
cat TADMap_scaffold_hs.bed |\
sed 's/^chr//' |\
awk '{print $1,$2-2000,$2+2000; print $1,$3-2000,$3+2000}' OFS="\t" |\
awk '{if($2 < 0) $2=0; print}' OFS="\t" |\
sort -k1,1V -k2,2n -k3,3n |\
bedtools merge |\
awk '{print $0"\tTAD_"$1"_"$2"_"$3}' |\
bgzip > TAD_boundaries.bed.gz

tabix -p bed TAD_boundaries.bed.gz



# compress, index and upload

chr_list=( $(echo {1..22} X) )


for (( c=0;c<${#chr_list[@]};++c )); do

# get chr name from array

chr=${chr_list[$c]}

# make tmp dir

mkdir "chr$chr/"

tabix TAD_boundaries.bed.gz $chr | bgzip > chr$chr/tad_chr$chr.bed.gz && tabix -p bed chr$chr/tad_chr$chr.bed.gz

# upload

echo "Uploading chromosome $chr"

dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

# delete tmp

rm -rf "chr$chr"

done  &


cd ..

rm -rf tad_boundaries

```

### Pre-calculated protein-level scores (amino-acid scores)


#### AlphaMissense

```bash
mkdir am_scores && cd am_scores
# dowload here  https://console.cloud.google.com/storage/browser/dm_alphamissense 

# get the list of transcripts

gunzip -dc AlphaMissense_hg38.tsv.gz AlphaMissense_isoforms_hg38.tsv.gz |\
awk -F"\t" '!/^#/{gene=$7;if($6 ~ "ENS") gene=$6; gsub("\\\..+","",gene); ++genes[gene];next}END{for(g in genes) print g}' > am_transcripts.txt &

# 81980 transcripts


# get gene names for all transcripts

mkdir ensembl && cd ensembl

# batch 1 GRCh38
seq 76 114 |\
xargs -I% -P1 wget https://ftp.ensembl.org/pub/release-%/gtf/homo_sapiens/Homo_sapiens.GRCh38.%.gtf.gz



# batch 2 GRCh37
seq 55 75 |\
xargs -I% -P1 wget https://ftp.ensembl.org/pub/release-%/gtf/homo_sapiens/Homo_sapiens.GRCh37.%.gtf.gz



for ((v=77;v<=114;++v)); do
zcat Homo_sapiens.GRCh38.${v}.gtf.gz |\
awk -F"\t" '$9 ~ "ENST"{print $9}' | tr ';' '\t' | tr ' ' '\t' | tr -d '"' | awk '{print $2,$6}' OFS="\t" |\
awk '{if($2 in genes) next; else genes[$2]=$1}END{for(g in genes) print genes[g],g}' OFS="\t" > ensembl_genes_${v}.tsv &
done


# the file structure changed in v 77


for ((v=55;v<=76;++v)); do

zcat Homo_sapiens.*.${v}.gtf.gz |\
awk -F"\t" '$9 ~ "ENST"{print $9}' | tr ';' '\t' | tr ' ' '\t' | tr -d '"' | awk '{print $2,$4}' OFS="\t" |\
awk '{if($2 in genes) next; else genes[$2]=$1}END{for(g in genes) print genes[g],g}' OFS="\t" > ensembl_genes_${v}.tsv &

done


cat ensembl_genes_{114..55}.tsv |\
awk '{genes[$2]=$1;next}END{for(g in genes) print genes[g],g}' OFS="\t" |\
sort -k1,1V -k2,2V |\
uniq > ensembl_transcripts_to_genes.tsv &


mv ensembl_transcripts_to_genes.tsv ../

cd ..




# map names
cp am_transcripts.txt am_transcripts_unmapped.txt


> am_transcripts_mapped.txt


awk 'NR==FNR{genes[$2]=$1;next}{if($1 in genes ) print genes[$1],$1}' OFS="\t" ensembl_transcripts_to_genes.tsv am_transcripts_unmapped.txt >> am_transcripts_mapped.txt


wc -l am_transcripts_mapped.txt
# 81980




awk -F"\t" 'NR==FNR{++genes[$2];next}!($1 in genes)' am_transcripts_mapped.txt am_transcripts.txt > am_transcripts_unmapped.txt

wc -l am_transcripts_unmapped.txt





#####


mv am_transcripts_mapped.txt am_transcripts_to_genes.tsv



awk '{aa_ref=$6;gsub("[0-9]+[A-Z]","",aa_ref);aa_pos=$6;gsub("[A-Z]","",aa_pos);aa_alt=$6;gsub("[A-Z][0-9]+","",aa_alt);$6=aa_ref"\t"aa_pos"\t"aa_alt;print}' OFS="\t" |\


# annotate
echo -e "#chrom\tpos\tref\talt\tgene_id\tamino_acid\tam_score" | bgzip > alpha_missense_hg38.tsv.gz 

gunzip -dc AlphaMissense_hg38.tsv.gz  AlphaMissense_isoforms_hg38.tsv.gz|\
awk -F"\t" 'NR==FNR{genes[$2]=$1;next}!/^#/{gsub("chr","",$1);gene=$7;protein=$8;score=$9;if($6 ~ "ENS") {gene=$6;protein=$7;score=$8}; gsub("\\\..+","",gene); print $1,$2,$3,$4,genes[gene],protein,score}' OFS="\t" am_transcripts_to_genes.tsv - |\
sort -k1,1V -k2,2n -k4,4 -k5,5V -k6,6 -k7,7 --compress-program=gzip -T ./ --parallel=4 |\
awk -F"\t" 'BEGIN{prev_var="na"}{this_var=$1":"$2":"$3":"$4":"$5":"$6}{if(this_var == prev_var) next; else prev_var=this_var}{print}' |\
bgzip >> alpha_missense_hg38.tsv.gz &



# index

tabix -s1 -S1 -b2 -e2 alpha_missense_hg38.tsv.gz 


# back up
echo -e "gene_id\tisoform_id" |\
cat - am_transcripts_to_genes.tsv |\
gzip > alpha_missense_isoforms_map.tsv.gz

# archive
tar -cvf alpha_missense_score.tar alpha_missense_isoforms_map.tsv.gz alpha_missense_hg38.tsv.gz alpha_missense_hg38.tsv.gz.tbi &



#
dx upload --brief --path $DX_PROJECT_CONTEXT_ID:Resources/tmp_files/ alpha_missense_score.tar &



# split per chromosome
chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

    chr=${chr_list[$c]}

    echo "Chromosome $chr"

    mkdir "chr$chr/"

    # header
    zcat alpha_missense_hg38.tsv.gz |\
    head -n1 |\
    bgzip > "chr$chr/alpha_missense_chr${chr}.tsv.gz";

    # body
    tabix alpha_missense_hg38.tsv.gz $chr |\
    awk '{raa=$6;aaa=$6;gsub("[0-9].+","",raa);gsub("[A-Z][0-9]+","",aaa);$6=raa"/"aaa;print}' OFS="\t" |\
    bgzip >> "chr$chr/alpha_missense_chr${chr}.tsv.gz";

    tabix -S1 -s1 -b2 -e2 "chr$chr/alpha_missense_chr${chr}.tsv.gz";

    # upload
    dx upload --brief -p --path $DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/ --recursive "./chr$chr"

    # delete

    rm -rf "./chr$chr"

done &


cd ..

rm -rf ./am_scores
```


#### REVEL

```bash
mkdir revel_scores && cd revel_scores

# Download curl -O https://rothsj06.dmz.hpc.mssm.edu/revel-v1.3_all_chromosomes.zip

unzip revel-v1.3_all_chromosomes.zip

# get a list of transcripts

cut -f9 -d, revel_with_transcript_ids |\
tr ';' '\n' |\
awk 'NR>1{++gene[$1];next}END{for(g in gene) print g}' > revel_transcripts.txt


cp revel_transcripts.txt revel_transcripts_unmapped.txt

# get gene names for all transcripts

wget https://ftp.ensembl.org/pub/release-114/gtf/homo_sapiens/Homo_sapiens.GRCh38.114.gtf.gz


zcat Homo_sapiens.GRCh38.114.gtf.gz |awk -F"\t" '$3 == "transcript"{print $9}' | tr ';' '\t' | tr ' ' '\t' | tr -d '"' | cut -f2,8 |\
awk '{if($2 in genes) next; else genes[$2]=$1}END{for(g in genes) print genes[g],g}' OFS="\t" |\
awk 'NR==FNR{genes[$2]=$1;next}{if($1 in genes ) print genes[$1],$1}' OFS="\t" - revel_transcripts_unmapped.txt >> revel_transcripts_mapped.txt


wc -l revel_transcripts_mapped.txt
# 62014

#######

awk -F"\t" 'NR==FNR{++genes[$2];next}!($1 in genes)' revel_transcripts_mapped.txt revel_transcripts.txt > revel_transcripts_unmapped.txt

wc -l revel_transcripts_unmapped.txt


wget https://ftp.ensembl.org/pub/release-64/gtf/homo_sapiens/Homo_sapiens.GRCh37.64.gtf.gz


zcat Homo_sapiens.GRCh37.64.gtf.gz |\
cut -f9 |\
awk -F";" '{gsub(" gene_id ","",$1);gsub(" transcript_id ","",$2);if($2 in genes) next; else genes[$2]=$1}END{for(g in genes) print genes[g],g}' OFS="\t" |\
tr -d '"' |\
awk 'NR==FNR{genes[$2]=$1;next}{if($1 in genes ) print genes[$1],$1}' OFS="\t" - revel_transcripts_unmapped.txt >> revel_transcripts_mapped.txt

wc -l revel_transcripts_mapped.txt

awk -F"\t" 'NR==FNR{++genes[$2];next}!($1 in genes)' revel_transcripts_mapped.txt revel_transcripts.txt > revel_transcripts_unmapped.txt

wc -l revel_transcripts_unmapped.txt



mv revel_transcripts_mapped.txt revel_transcripts_to_genes.tsv

####



# header
echo "#chrom,pos,ref,alt,gene_id,amino_acid,revel" |\
tr ',' '\t' |\
bgzip > revel_1_3_liftover_hg38.tsv.gz


# flatten and annotate genes
awk -F"," '{pos="\n"$1","$2","$3","$4","$5","$6","$7","$8","; gsub(";",pos,$9)}{print}' revel_with_transcript_ids |\
tr ',' '\t' |\
awk -F"\t" 'NR==FNR{genes[$2]=$1;next}{if($9 in genes && $3 != ".") print $1,$3,$4,$5,genes[$9],$6"/"$7,$8}' OFS="\t" revel_transcripts_to_genes.tsv - |\
sort -k1,1V -k2,2n -k4,4 -k5,5V -k6,6 -k7,7 --compress-program=gzip -T ./ --parallel=4 |\
awk -F"\t" 'BEGIN{prev_var="na"}{this_var=$1":"$2":"$4":"$5":"$6}{if(this_var == prev_var) next; else prev_var=this_var}{print}' |\
bgzip >> revel_1_3_liftover_hg38.tsv.gz &


# index

tabix -S1 -s1 -b2 -e2 revel_1_3_liftover_hg38.tsv.gz



# backup
gzip revel_transcripts_to_genes.tsv

tar -cf revel_1_3_liftover_hg38.tar revel_transcripts_to_genes.tsv.gz revel_1_3_liftover_hg38.tsv.gz revel_1_3_liftover_hg38.tsv.gz.tbi


dx upload --path $DX_PROJECT_CONTEXT_ID:Resources/tmp_files/ revel_1_3_liftover_hg38.tar



# split per chromosome


chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

	chr=${chr_list[$c]}

	echo "Indexing chromosome $chr"

	mkdir "chr$chr/"

	# header
	echo "#chrom,pos,ref,alt,gene_id,amino_acid,revel" |\
	tr ',' '\t' |\
	bgzip > ./chr$chr/revel_chr${chr}.tsv.gz;

	# body
	tabix revel_1_3_liftover_hg38.tsv.gz $chr |\
	bgzip >> ./chr$chr/revel_chr${chr}.tsv.gz;

	tabix -S1 -s1 -b2 -e2 ./chr$chr/revel_chr${chr}.tsv.gz;


	# upload
	dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

	# delete

	rm -rf "./chr$chr"

done &


cd ..

rm -rf revel_scores

```

# Handle insertions where end < start by adjusting query coordinates
  my $query_start = $vf->{start};
  my $query_end = $vf->{end};
  if ($query_end < $query_start) {
    $query_end = $query_start;
  }

#### MPC

```bash
mkdir mpc_scores && cd mpc_scores

# download curl -O https://grr.iossifovlab.com/hg19/scores/MPC/fordist_constraint_official_mpc_values_v2.txt.gz


# crossmap from

#https://crossmap.sourceforge.net/

# chain files from 

#ftp://ftp.ensembl.org/pub/assembly_mapping/homo_sapiens/

# lift over to hg38

echo -e 'Chr_GRCh37\tPos_GRCh37\tCross_mapping\tChr_GRCh38\tPos_GRCh38\tMPC_annotation' | gzip > mpc_score_2.0_crossmap_hg38.txt.gz

CrossMap bed --chromid s --unmap-file mpc_score_2.0_crossmap_unmapped.log GRCh37_to_GRCh38.chain.gz <(zcat fordist_constraint_official_mpc_values_v2.txt.gz | awk -F"\t" 'NR>1{for(c = 4; c <= NF;++c) if($c == "") $c = "NA";$1 = $1"\t"$2-1;print}' OFS="\t" | sed  's/\t/,/4g' ) | cut -f1,3,5,6,8- | gzip >> mpc_score_2.0_crossmap_hg38.txt.gz

# collect 110,946 unmapped records to mpc_score_2.0_crossmap_unmapped.tsv

zcat mpc_score_2.0_crossmap_hg38.txt.gz |\
awk 'NR >1 && ($3 != "->" || $1 != $4)' |\
uniq |\
gzip > mpc_score_2.0_crossmap_unmapped.tsv.gz


# header
zcat fordist_constraint_official_mpc_values_v2.txt.gz |\
head -n1 |\
sed '1s/.*/#&/' |\
bgzip > mpc_score_2.0_crossmap_hg38.tsv.gz



# sort and compress
zcat mpc_score_2.0_crossmap_hg38.txt.gz |\
awk '($3 == "->" || $3 ~ $1":"$2-1":"$2) && $1 == $4' |\
cut -f4- |\
tr ',' '\t' |\
sort -k1,1V -k2,2n --compress-program=gzip -T ./ --parallel=4 |\
bgzip >> mpc_score_2.0_crossmap_hg38.tsv.gz &

# index
tabix -S1 -s1 -b2 -e2 mpc_score_2.0_crossmap_hg38.tsv.gz &

# backup

tar -cf mpc_score_2.0_crossmap_hg38.tar mpc_score_2.0_crossmap_hg38.tsv.gz mpc_score_2.0_crossmap_hg38.tsv.gz.tbi mpc_score_2.0_crossmap_unmapped.tsv.gz

dx --path $DX_PROJECT_CONTEXT_ID:Resources/tmp_files/ upload mpc_score_2.0_crossmap_hg38.tar


# split

chr_list=( $(echo {1..22} X Y) )


for (( c=0;c<${#chr_list[@]};++c )); do

	chr=${chr_list[$c]}

	echo "Indexing chromosome $chr"

	mkdir "chr$chr/"

	# header
	echo -e "#chrom\tpos\tref\talt\tgene_id\tamino_acid\tmpc_score" |\
	bgzip > chr$chr/mpc_chr${chr}.tsv.gz 

	# body
	tabix mpc_score_2.0_crossmap_hg38.tsv.gz $chr |\
    awk '{$NF=sprintf("%.2f",$NF);print $1,$2,$3,$4,$7,$12,$NF}' OFS="\t" |\
	sort -k2,2n -k4,4 -k5,5V -k6,6 -k7,7n --compress-program=gzip -T ./chr$chr/ --parallel=2 |\
	uniq |\
	awk -F"\t" 'BEGIN{prev_var="na"}{this_var=$1":"$2":"$3":"$4":"$5":"$6}{if(this_var == prev_var) next; else prev_var=this_var}{print}' |\
	bgzip >> chr$chr/mpc_chr${chr}.tsv.gz

	tabix -S1 -s1 -b2 -e2 chr$chr/mpc_chr${chr}.tsv.gz


	# upload
	dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

	# delete

	rm -rf "./chr$chr"

done &

cd ..

rm -rf mpc_scores
```



#### PrimateAI-3D

```bash
mkdir primate3d_scores && cd primate3d_scores

dx download "$DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/PrimateAI-3D.hg38.txt.gz"

# get the transcripts

zcat PrimateAI-3D.hg38.txt.gz |\
awk -F"\t" 'NR>1{gsub("\\.[0-9]+","",$5);++ids[$5];next}END{for(i in ids) print i}' > PrimateAI3D_transcripts.txt

# 19,068 transcripts


# get gene names for all transcripts in r114
dx download $DX_PROJECT_CONTEXT_ID:/Resources/tmp_files/ensembl_genes_to_transcripts.tsv.gz

gunzip ensembl_genes_to_transcripts.tsv.gz


# check if all found

awk 'NR==FNR{genes[$3]=$2;next}{if($1 in genes ) print genes[$1],$1}' OFS="\t" ensembl_genes_to_transcripts.tsv PrimateAI3D_transcripts.txt > PrimateAI3D_transcripts_mapped.txt


wc -l PrimateAI3D_transcripts_mapped.txt
# 19,068

# Convert to bgzip

zcat PrimateAI-3D.hg38.txt.gz |\
awk 'BEGIN{print "#chrom\tpos\tref\talt\tgene_id\tamino_acid\tpai3d_score"}NR==FNR{genes[$3]=$2;next}FNR>1{gsub("chr","",$1);gsub("\\.[0-9]+","",$5); $5=genes[$5]; $9 = sprintf("%.4f", $9); print $1,$2,$3,$4,$5,$7"/"$8,$9}' OFS="\t" ensembl_genes_to_transcripts.tsv - |\
bgzip > PrimateAI-3D.hg38.tsv.gz

tabix -s1 -S1 -b2 -e2 PrimateAI-3D.hg38.tsv.gz

tar -czvf PrimateAI-3D.hg38.tar.gz PrimateAI-3D.hg38.tsv.gz PrimateAI-3D.hg38.tsv.gz.tbi

dx upload --path "$DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/" PrimateAI-3D.hg38.tar.gz



# split

chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

  chr=${chr_list[$c]}

  mkdir "chr$chr/"

  # header
  echo -e "#chrom\tpos\tref\talt\tgene_id\tamino_acid\tpai3d_score" |\
  bgzip > chr$chr/pai3d_chr${chr}.tsv.gz 



  tabix PrimateAI-3D.hg38.tsv.gz $chr |\
  bgzip >> chr$chr/pai3d_chr${chr}.tsv.gz 

  tabix -S1 -s1 -b2 -e2 chr$chr/pai3d_chr${chr}.tsv.gz

  echo "Chromosome $chr"

  # upload
  dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

  # delete

  rm -rf "./chr$chr"

done &

cd ..

rm -rf primate3d_scores





```


### Pre-calculated transcript-level scores (e.g., splicing, promoter)


#### SpliceAI (SNVs)

The aim is to summarize these data into delta scores and fix annotations so that they are matched by ensembl gene ID.


```bash
mkdir spliceai_scores && cd spliceai_scores

dx download $DX_PROJECT_CONTEXT_ID:Resources/precalculated_scores/spliceai_scores.masked.snv.hg38.vcf.gz
dx download $DX_PROJECT_CONTEXT_ID:Resources/precalculated_scores/spliceai_scores.masked.snv.hg38.vcf.gz.tbi



# gene names map

bcftools query -f '%SpliceAI\n' spliceai_scores.masked.snv.hg38.vcf.gz |\
awk -F"|" '{++genes[$2];next}END{for(g in genes) print g}' >  spliceai_genes.txt &

#20,273


# gencode genes (documentation of spliceai indicates the use of gencode)
wget https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_24/gencode.v24.annotation.gtf.gz

zcat gencode.v24.annotation.gtf.gz |\
tr -d '"' |\
awk -F"\t" '$3 == "gene"{print $9}' |\
awk -F";" '{for(c=2;c<=NF;++c) if($c ~ "gene_name") { gsub("gene_id ","",$1);gsub("\\\..+","",$1);gsub(" gene_name ","",$c);gsub("\\\.[0-9]+","",$c);print $c"\t"$1;next}}' > gencode_genes.tsv


awk '{gsub("\\\.[0-9]+","",$1);print}' spliceai_genes.txt > spliceai_genes_no_version.txt



# missing

#295 genes

awk 'NR==FNR{gene_ids[$1]=$2;next}{if ($1 in gene_ids) {print $1"\t"gene_ids[$1] > ( "spliceai_genes_mapped.tsv"  ); next}}{ print > ( "missing_genes_all.txt" )}' OFS="\t" gencode_genes.tsv spliceai_genes_no_version.txt 


sed -i 's/ORF/orf/' missing_genes_all.txt

mapfile -t missing_genes < missing_genes_all.txt



# search hgnc

for (( g=0; g< ${#missing_genes[@]}; ++g )); do

echo ${missing_genes[$g]} $(curl --no-progress-meter -H"Accept:application/json" https://rest.genenames.org/fetch/symbol/${missing_genes[$g]} | jq -r ."response"."docs".[0]."ensembl_gene_id" 2> /dev/null)

done | grep -v "null" > missing_genes_hgnc.txt


for (( g=0; g< ${#missing_genes[@]}; ++g )); do

echo ${missing_genes[$g]} $(curl --no-progress-meter -H"Accept:application/json" https://rest.genenames.org/fetch/prev_symbol/${missing_genes[$g]} | jq -r ."response"."docs".[0]."ensembl_gene_id" 2> /dev/null)

done | grep -v "null" >> missing_genes_hgnc.txt


for (( g=0; g< ${#missing_genes[@]}; ++g )); do

echo ${missing_genes[$g]} $(curl --no-progress-meter -H"Accept:application/json" https://rest.genenames.org/fetch/alias_symbol/${missing_genes[$g]} | jq -r ."response"."docs".[0]."ensembl_gene_id" 2> /dev/null)

done | grep -v "null" >> missing_genes_hgnc.txt


# append 36 genes

cat missing_genes_hgnc.txt | tr ' ' '\t'  >> spliceai_genes_mapped.tsv




# split

chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

  chr=${chr_list[$c]}

  mkdir "chr$chr/"

  # header
  echo -e "#chrom\tpos\tref\talt\tgene_id\tspliceai_score" |\
  bgzip > chr$chr/spliceai_chr${chr}.tsv.gz 



  bcftools query -r $chr -f '%CHROM|%POS|%REF|%ALT|%SpliceAI\n' spliceai_scores.masked.snv.hg38.vcf.gz |\
  awk -F"|" '{ds=$7;for(s=8;s<=10;++s) if($s > ds) ds=$s}{gene=$6;gsub("\\\.[0-9]+","",gene)}{print $1,$2,$3,$5,gene,ds}' OFS="\t" |\
  awk -F"\t" 'NR==FNR{gene_ids[$1]=$2;next}$5 in gene_ids && $NF >= 0.2{$5=gene_ids[$5];print}' OFS="\t" spliceai_genes_mapped.tsv -  |\
  bgzip >> chr$chr/spliceai_chr${chr}.tsv.gz 

  tabix -S1 -s1 -b2 -e2 chr$chr/spliceai_chr${chr}.tsv.gz

  echo "Chromosome $chr"

  # upload
  dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

  # delete

  rm -rf "./chr$chr"

done

cd ..

rm -rf spliceai_scores
```


#### SpliceAI




```bash
mkdir spliceai_scores && cd spliceai_scores


####
dx download $DX_PROJECT_CONTEXT_ID:Resources/precalculated_scores/spliceai_scores.masked.snv.hg38.vcf.gz
dx download $DX_PROJECT_CONTEXT_ID:Resources/precalculated_scores/spliceai_scores.masked.snv.hg38.vcf.gz.tbi


####
dx download $DX_PROJECT_CONTEXT_ID:Resources/precalculated_scores/spliceai_scores.masked.indel.hg38.vcf.gz
dx download $DX_PROJECT_CONTEXT_ID:Resources/precalculated_scores/spliceai_scores.masked.indel.hg38.vcf.gz.tbi


####
dx download $DX_PROJECT_CONTEXT_ID:Resources/tmp_files/ensembl_genes_to_transcripts.tsv.gz
gunzip ensembl_genes_to_transcripts.tsv.gz



process_chr_scores() {
	chr_list=( $(echo {1..22} X Y) )

  chr=${chr_list["$1"]}


 	mkdir "chr$chr/";


  bcftools query -r $chr -f '%CHROM|%POS|%REF|%ALT|%SpliceAI\n' spliceai_scores.masked.snv.hg38.vcf.gz |\
  awk -F"|" '{ds=$7;for(s=8;s<=10;++s) if($s > ds) ds=$s}{gene=$6;gsub("\\\.[0-9]+","",gene)}{print $1,$2,$3,$5,gene,ds}' OFS="\t" |\
  awk -F"\t" 'NR==FNR{if($1 in gene_ids) {next;} else {gene_ids[$1]=$2;next}}$5 in gene_ids && $NF > 0{$5=gene_ids[$5];print}' OFS="\t" ensembl_genes_to_transcripts.tsv -  |\
  gzip >> chr$chr/tmp.snvs.gz;


  bcftools query -r $chr -f '%CHROM|%POS|%REF|%ALT|%SpliceAI\n' spliceai_scores.masked.indel.hg38.vcf.gz |\
  awk -F"|" '{ds=$7;for(s=8;s<=10;++s) if($s > ds) ds=$s}{gene=$6;gsub("\\\.[0-9]+","",gene)}{print $1,$2,$3,$5,gene,ds}' OFS="\t" |\
  awk -F"\t" 'NR==FNR{if($1 in gene_ids) {next;} else {gene_ids[$1]=$2;next}}$5 in gene_ids && $NF > 0{$5=gene_ids[$5];print}' OFS="\t" ensembl_genes_to_transcripts.tsv -  |\
  gzip >> chr$chr/tmp.indels.gz;


  # header
  echo -e "#chrom\tpos\tref\talt\tgene_id\tspliceai_score" |\
  bgzip > chr$chr/spliceai_chr${chr}.tsv.gz 


  zcat chr$chr/tmp.snvs.gz chr$chr/tmp.indels.gz |\
  sort -k2,2n -k3,3 -k4,4 -k5,5 --compress-program=gzip -T ./chr$chr/ --parallel=2 |\
  bgzip >> chr$chr/spliceai_chr${chr}.tsv.gz;

 
 	rm chr$chr/tmp.snvs.gz chr$chr/tmp.indels.gz 

  tabix -S1 -s1 -b2 -e2 chr$chr/spliceai_chr${chr}.tsv.gz;
 

   # upload
  dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"


  rm -rf chr$chr/

}

export -f process_chr_scores

process_chr_scores 23


seq 22 -1 0 | parallel --jobs 8 process_chr_scores &


cd ..

rm -rf spliceai_scores
```


#### PromoterAI

```bash
mkdir promoterai_scores && cd promoterai_scores

dx download "$DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/promoterAI_tss500.tsv.gz"


# convert to bgzip and reformat

zcat promoterAI_tss500.tsv.gz |\
awk -F"\t" '{if(NR==1) gsub("chr","#chr",$1) ; else gsub("chr","",$1)}{print $1,$2,$3,$4,$6,$NF}' OFS="\t" |\
bgzip > PromoterAI_scores.tsv.gz



tabix -s1 -S1 -b2 -e2 PromoterAI_scores.tsv.gz

tar -czvf PromoterAI_scores.tar.gz PromoterAI_scores.tsv.gz PromoterAI_scores.tsv.gz.tbi

dx upload --path "$DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/" PromoterAI_scores.tar.gz


# split

chr_list=( $(echo {1..22} X Y) )


for (( c=0;c<${#chr_list[@]};++c )); do

  chr=${chr_list[$c]}

  mkdir "chr$chr/"

  # header
  echo -e "#chrom\tpos\tref\talt\tgene_id\tpromai_score" |\
  bgzip > chr$chr/promoterai_chr${chr}.tsv.gz 



  tabix PromoterAI_scores.tsv.gz $chr |\
  sed 's/_PAR_Y//' |\
  bgzip >> chr$chr/promoterai_chr${chr}.tsv.gz 

  tabix -S1 -s1 -b2 -e2 chr$chr/promoterai_chr${chr}.tsv.gz

  echo "Chromosome $chr"

  # upload
  dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

  # delete

  rm -rf "./chr$chr"

done

cd ..

rm -rf promoterai_scores


```



#### MTR

Positions are off by one in this script, 


```bash
mkdir mtr_scores && cd mtr_scores

dx download "$DX_PROJECT_CONTEXT_ID:/Resources/tmp_files/mtrflatfile_2.0.txt.gz"

dx download "$DX_PROJECT_CONTEXT_ID:/Resources/tmp_files/ensembl_genes_to_transcripts.tsv.gz"

dx download "$DX_PROJECT_CONTEXT_ID:/Resources/tmp_files/GRCh37_to_GRCh38.chain.gz"

gunzip ensembl_genes_to_transcripts.tsv.gz 



# lift over to hg38

~/.local/bin/CrossMap bed --chromid s --unmap-file mtr_score_2.0_crossmap_unmapped.log GRCh37_to_GRCh38.chain.gz <(zcat mtrflatfile_2.0.txt.gz  | awk -F"\t" 'NR==FNR{genes[$3]=$2;next}FNR> 1&& $11!=""{if($5 in genes) print $1,$2-1,$2,$3,$4,genes[$5],$11}' OFS="\t" ensembl_genes_to_transcripts.tsv - | sed  's/\t/,/4g' ) |\
bgzip > mtr_score_2.0_crossmap_hg38.tmp.gz &


# header
echo -e "#chrom\tpos\tref\talt\tgene_id\tmtr_score" |\
bgzip > mtr_score_2.0_crossmap_hg38.tsv.gz


zcat mtr_score_2.0_crossmap_hg38.tmp.gz |\
awk '($5 == "->" || $5 ~ $1":"$3-1":"$3) && $1 == $6{print $6,$8,$NF}' OFS="," |\
tr ',' '\t' |\
sort -k1,1V -k2,2n -k3,3 -k4,4 -k5,5V -k6,6 --compress-program=gzip -T ./ --parallel=2 |\
awk -F"\t" 'BEGIN{prev_var="na"}{this_var=$1":"$2":"$3":"$4":"$5}{if(this_var == prev_var) next; else prev_var=this_var}{print}' |\
bgzip >> mtr_score_2.0_crossmap_hg38.tsv.gz &


# index
tabix -S1 -s1 -b2 -e2 mtr_score_2.0_crossmap_hg38.tsv.gz


# backup
tar -cf mtr_score_2.0_crossmap_hg38.tar mtr_score_2.0_crossmap_hg38.tsv.gz mtr_score_2.0_crossmap_hg38.tsv.gz.tbi


dx upload --path $DX_PROJECT_CONTEXT_ID:Resources/tmp_files/ mtr_score_2.0_crossmap_hg38.tar


# split

chr_list=( $(echo {1..22} X Y) )


for (( c=0;c<${#chr_list[@]};++c )); do

  chr=${chr_list[$c]}

  echo "Indexing chromosome $chr"

  mkdir "chr$chr/"

  # header
  echo -e "#chrom\tpos\tref\talt\tgene_id\tmtr_score" |\
  bgzip > chr$chr/mtr_chr${chr}.tsv.gz 

  # body
  tabix mtr_score_2.0_crossmap_hg38.tsv.gz $chr |\
  bgzip >> chr$chr/mtr_chr${chr}.tsv.gz

  tabix -S1 -s1 -b2 -e2 chr$chr/mtr_chr${chr}.tsv.gz


  # upload
  dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

  # delete

  rm -rf "./chr$chr"

done &

cd ..

rm -rf mtr_scores

dx terminate $DX_JOB_ID
```



#### CCR


#### HMC


### Pre-calculated varinat-level scores (e.g., CADD)


#### CADD

```bash
mkdir cadd_scores && cd cadd_scores

# Downloaded using the URL download app; renamed to CADD_whole_genome_SNVs.tsv.gz

dx download $DX_PROJECT_CONTEXT_ID:Resources/precalculated_scores/CADD_whole_genome_SNVs.tsv.gz

wget https://kircherlab.bihealth.org/download/CADD/v1.7/GRCh38/whole_genome_SNVs.tsv.gz.tbi

mv whole_genome_SNVs.tsv.gz.tbi CADD_whole_genome_SNVs.tsv.gz.tbi



# split

chr_list=( $(echo {1..22} X Y) )

for (( c=0;c<${#chr_list[@]};++c )); do

  chr=${chr_list[$c]}


  mkdir "chr$chr/"

  # header
  echo -e "#chrom\tpos\tref\talt\tcadd_score" |\
  bgzip > chr$chr/cadd_chr${chr}.tsv.gz 

  # body
  tabix CADD_whole_genome_SNVs.tsv.gz $chr |\
  awk '{NF=5;print}' OFS="\t" |\
  bgzip >> chr$chr/cadd_chr${chr}.tsv.gz

  tabix -S1 -s1 -b2 -e2 chr$chr/cadd_chr${chr}.tsv.gz

  echo "Chromosome $chr"

  # upload
  dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

  # delete

  rm -rf "./chr$chr"

done &

cd ..


rm -rf cadd_scores

```



### Pre-calculated site-level scores (e.g., conservation and constraint scores)


#### GERP conservation scores 


```bash
mkdir gerp_scores && cd gerp_scores

# Using the custom script "bigwig_splitter" which handles the download and splitting.

# this will take a while; use tmux session to detach


dx download $DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/gerp_conservation_scores.homo_sapiens.GRCh38.bw

# This file was downloaded using URL file fetcher
# URL: https://ftp.ensembl.org/pub/current_compara/conservation_scores/91_mammals.gerp_conservation_score/gerp_conservation_scores.homo_sapiens.GRCh38.bw
# If not already downloaded, pass the URL to the script below and it will be downloaded

chr_list=( $(echo {1..22} X Y) )


for (( c=0;c<${#chr_list[@]};++c )); do

# get chr name from array

chr=${chr_list[$c]}

# make tmp dir

mkdir "chr$chr/"

# split

python3 ./bigwig_splitter.py \
--url "gerp_conservation_scores.homo_sapiens.GRCh38.bw" \
--prefix "chr$chr/gerp" \
--chromosomes "$chr"

# upload

echo "Uploading chromosome $chr"

dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

# delete tmp

rm -rf "chr$chr"

done  &


cd ..

rm -rf gerp_scores
```


#### Gnocchi

Note that this file does not contain chrY


```bash
mkdir gnomad_scores && cd gnomad_scores

# Using the custom script "bigwig_splitter" which handles the download and splitting.

# this will take a while; use tmux session to detach

chr_list=( $(echo {1..22} X Y) )


for (( c=0;c<${#chr_list[@]};++c )); do

# get chr name from array

chr=${chr_list[$c]}

# make tmp dir

mkdir "chr$chr/"

# split (not the chr names are prefixed)

python3 ./bigwig_splitter.py \
--url "https://hgdownload.soe.ucsc.edu/gbdb/hg38/gnomAD/mutConstraint/mutConstraint.bw" \
--prefix "chr$chr/gnocchi" \
--chromosomes "chr$chr"


# fix name (small bug in the code that results in using chrchr when the chr name is prefixed)

rename.ul "chrchr" "chr" chr$chr/*


# upload

echo "Uploading chromosome $chr"

dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

# delete tmp

rm -rf "chr$chr"

done  &


dx upload --path $DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/ mutConstraint.bw

cd ..

rm -rf gnomad_scores
```

```bash

for i in $(echo {1..22} X Y) ; do


for i in $(echo Y) ; do

mv zcat mtr_chr${i}.tsv.gz zcat mtr_chr${i}.tsv.tmp && zcat mtr_chr${i}.tsv.tmp | awk 'NR>1{$2 = $2-1}{print}' OFS="\t" | bgzip > mtr_chr${i}.tsv.tmp && mv mtr_chrY.tsv.tmp mtr_chr${i}.tsv.gz && tabix -S1 -s1 -b2 -e2 mtr_chr${i}.tsv.gz 

done



&& dx upload --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/chr${i}/" mtr_chr${i}.tsv.gz mtr_chr${i}.tsv.gz.tbi


```

#### Depletion Rank (DR)

Note that this file does not contain chrX/Y


```bash
mkdir ukbdr_scores && cd ukbdr_scores

# Using the custom script "bigwig_splitter" which handles the download and splitting.

# this will take a while; use tmux session to detach


dx download $DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/ukbDepletion.bw

# This file was downloaded using URL file fetcher
# URL: https://hgdownload.soe.ucsc.edu/gbdb/hg38/xxxxx
# If not already downloaded, pass the URL to the script below and it will be downloaded

chr_list=( $(echo {1..22} X Y) )


for (( c=0;c<${#chr_list[@]};++c )); do

# get chr name from array

chr=${chr_list[$c]}

# make tmp dir

mkdir "chr$chr/"

# split (not the chr names are prefixed)

python3 ./bigwig_splitter.py \
--url "ukbDepletion.bw" \
--prefix "chr$chr/ukb_depletion" \
--chromosomes "chr$chr"


# fix name (small bug in the code that results in using chrchr when the chr name is prefixed)

rename.ul "chrchr" "chr" "chr$chr/*"


# upload

echo "Uploading chromosome $chr"

dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

# delete tmp

rm -rf "chr$chr"

done  &


cd ..

rm -rf ukbdr_scores


```



#### JARVIS

Note that this file does not contain chrX/Y

```bash
mkdir jarvis_scores && cd jarvis_scores

# Using the custom script "bigwig_splitter" which handles the download and splitting.

# this will take a while; use tmux session to detach


dx download $DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/jarvis.bw

# This file was downloaded using URL file fetcher
# URL: https://hgdownload.soe.ucsc.edu/gbdb/hg38/jarvis/jarvis.bw
# If not already downloaded, pass the URL to the script below and it will be downloaded

chr_list=( $(echo {1..22} X Y) )


for (( c=0;c<${#chr_list[@]};++c )); do

# get chr name from array

chr=${chr_list[$c]}

# make tmp dir

mkdir "chr$chr/"

# split (not the chr names are prefixed)

python3 ./bigwig_splitter.py \
--url "jarvis.bw" \
--prefix "chr$chr/jarvis" \
--chromosomes "chr$chr"


# fix name (small bug in the code that results in using chrchr when the chr name is prefixed)

rename.ul "chrchr" "chr" chr$chr/*

# upload

echo "Uploading chromosome $chr"

dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

# delete tmp

rm -rf "chr$chr"

done  &


cd ..

rm -rf jarvis_scores


```



#### PhyloP


```bash
mkdir phylop_scores && cd phylop_scores

# Using the custom script "bigwig_splitter" which handles the download and splitting.

# this will take a while; use tmux session to detach

chr_list=( $(echo {1..22} X Y) )


for (( c=0;c<${#chr_list[@]};++c )); do

# get chr name from array

chr=${chr_list[$c]}

# make tmp dir

mkdir "chr$chr/"

# split (not the chr names are prefixed)

python3 ./bigwig_splitter.py \
--url "https://hgdownload.cse.ucsc.edu/goldenPath/hg38/phyloP30way/hg38.phyloP30way.bw" \
--prefix "chr$chr/phylop30" \
--chromosomes "chr$chr"


# fix name (small bug in the code that results in using chrchr when the chr name is prefixed)

rename.ul "chrchr" "chr" chr$chr/*


# upload

echo "Uploading chromosome $chr"

dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

# delete tmp

rm -rf "chr$chr"

done  &


dx upload --path $DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/ hg38.phyloP30way.bw

cd ..

rm -rf phylop_scores

```


#### PhastCons

```bash
mkdir phastcons_scores && cd phastcons_scores

# Using the custom script "bigwig_splitter" which handles the download and splitting.

# this will take a while; use tmux session to detach

chr_list=( $(echo {1..22} X Y) )


for (( c=0;c<${#chr_list[@]};++c )); do

# get chr name from array

chr=${chr_list[$c]}

# make tmp dir

mkdir "chr$chr/"

# split (not the chr names are prefixed)

python3 ./bigwig_splitter.py \
--url "https://hgdownload.cse.ucsc.edu/goldenPath/hg38/phastCons30way/hg38.phastCons30way.bw" \
--prefix "chr$chr/phastcons30" \
--chromosomes "chr$chr"


# fix name (small bug in the code that results in using chrchr when the chr name is prefixed)

rename.ul "chrchr" "chr" chr$chr/*


# upload

echo "Uploading chromosome $chr"

dx upload --brief -p --path "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/" --recursive "./chr$chr"

# delete tmp

rm -rf "chr$chr"

done  &


dx upload --path $DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/ hg38.phastCons30way.bw

cd ..

rm -rf phastcons_scores


```


