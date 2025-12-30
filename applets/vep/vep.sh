



```bash

VEP_CHR="7"
VEP_VER="114"




######
# IDs
######

VEP_PLUGINS=$(dx describe --multi --json "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_docker/vep_${VEP_VER}_plugins.tar.gz" | jq -r .[0].id || echo "")

VEP_DOCKER=$(dx describe --multi --json "$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_docker/vep_${VEP_VER}_docker_amd64.tar.gz" | jq -r .[0].id || echo "")

VEP_VAR=$(dx describe --multi --json "$DX_PROJECT_CONTEXT_ID:/Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${VEP_CHR}_b0_v1.pvar" | jq -r .[0].id || echo "")

VEP_DATA="$DX_PROJECT_CONTEXT_ID:/Resources/vep_114_data/chr${VEP_CHR}/"



##########
# Download
##########

mkdir -p $HOME/vep/cache $HOME/vep/fasta $HOME/vep/plugins $HOME/vep/in $HOME/vep/out $HOME/vep/tmp

dx download --no-progress ${VEP_DOCKER} -o $HOME/vep/tmp/docker.tar.gz

dx download --no-progress "$VEP_PLUGINS" -o $HOME/vep/tmp/plugins.tar.gz

dx download --no-progress "${VEP_VAR}" -o $HOME/vep/tmp/input.pvar

dx download --no-progress --recursive "$VEP_DATA" -o $HOME/vep/tmp/


########################
# Split input plink file
########################

zstdcat  "$HOME/vep/tmp/input.pvar" |\
    tr ' ' '\t' |\
    awk 'BEGIN{print "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO"}!/^#/{var_id=$3;gsub(".+:chr","chr",var_id);split(var_id, var_info, ":");print var_info[1],var_info[2],var_id,var_info[3],var_info[4],".",".","."}' OFS="\t" |\
    bgzip > "$HOME/vep/tmp/input.vcf.gz"

bcftools index "$HOME/vep/tmp/input.vcf.gz"

bcftools +scatter --threads 2 -Oz -o "$HOME/vep/in" -n100000 "$HOME/vep/tmp/input.vcf.gz"


################################
# Prep vep cache and annotations
################################

# Cache
tar -xf $HOME/vep/tmp/chr${VEP_CHR}/vep_cache_chr${VEP_CHR}.tar -C $HOME/vep/cache

rm $HOME/vep/tmp/chr${VEP_CHR}/vep_cache_chr${VEP_CHR}.tar

# Fasta files
tar -xf $HOME/vep/tmp/chr${VEP_CHR}/vep_fasta_chr${VEP_CHR}.tar -C $HOME/vep/fasta

rm $HOME/vep/tmp/chr${VEP_CHR}/vep_fasta_chr${VEP_CHR}.tar

# Plugins

tar -xzf $HOME/vep/tmp/plugins.tar.gz -C $HOME/vep/tmp/

mv $HOME/vep/tmp/vep_plugins/* $HOME/vep/plugins/

# Annotations

mv $HOME/vep/tmp/chr${VEP_CHR}/* $HOME/vep/plugins/

# remove "_chr*." from all file names

rename.ul "_chr${VEP_CHR}." "." $HOME/vep/fasta/* $HOME/vep/plugins/*

# Make the output folder and cache folder writable
chmod -R --silent a+rwx $HOME/vep/cache/homo_sapiens $HOME/vep/out/

# load docker image
docker load -q < $HOME/vep/tmp/docker.tar.gz

# delete tmp dir
rm -rf $HOME/vep/tmp

```






```bash

#########
# Run vep
#########

dx download file-J1KYjBQJZz4k761pPFpzF7X0

cat S91RsFnGwI0NoqEO.vcf | bgzip > ${HOME}/vep/in/test.vcf.gz


vep_input_prefix="test"

docker run \
--pull=never \
--platform linux/amd64 \
-v $HOME/vep/cache:/data \
-v $HOME/vep/fasta:/data/fasta \
-v $HOME/vep/plugins:/data/plugins \
-v $HOME/vep/in:/data/in/ \
-v $HOME/vep/out:/data/out/ \
vep_114 \
vep \
--offline \
--buffer_size 5000 \
--fork 1 \
--cache \
--dir_cache /data/ \
--dir_plugins /data/plugins \
--fasta /data/fasta/human_reference.fa.gz \
--input_file /data/in/${vep_input_prefix}.vcf.gz \
--format vcf \
--output_file /data/out/${vep_input_prefix}.tsv.gz \
--tab \
--force_overwrite \
--compress_output bgzip \
--no_stats \
--minimal \
--protein \
--biotype \
--variant_class \
--regulatory \
--cell_type "astrocyte,brain_(p),neural_progenitor_cell_(f,_5_dpf),neuronal_stem_cell_(m),tibial_nerve_(m,_37_y),tibial_nerve_(m,_54_y)" \
--numbers \
--nearest gene \
--shift_3prime 1 \
--show_ref_allele \
--af_gnomadg \
--plugin NMD \
--plugin LoF,loftee_path:/data/plugins,human_ancestor_fa:/data/fasta/human_ancestor.fa.gz,conservation_file:/data/plugins/loftee.sql,gerp_bigwig:/data/plugins/gerp.bw,debug:0 \
--plugin UTRAnnotator,file=/data/plugins/uORF_5UTR_GRCh38_PUBLIC.txt \
--plugin MiSc,MPC=/data/plugins/mpc.tsv.gz,REVEL=/data/plugins/revel.tsv.gz,AMis=/data/plugins/alpha_missense.tsv.gz,PAI3D=/data/plugins/pai3d.tsv.gz \
--custom short_name=GERP,file=/data/plugins/gerp.bw,format=bigwig,type=exact \
--custom short_name=PhyloP,file=/data/plugins/phylop30.bw,format=bigwig,type=exact \
--custom short_name=PhastCons,file=/data/plugins/phastcons30.bw,format=bigwig,type=exact \
--custom short_name=Gnocchi,file=/data/plugins/gnocchi.bw,format=bigwig,type=exact \
--custom short_name=JARVIS,file=/data/plugins/jarvis.bw,format=bigwig,type=exact \
--custom short_name=TSS,file=/data/plugins/tss.bed.gz,format=bed


add promoterai,spliceai,mtr
add cadd

fix TSS


--plugin SpliceAI,snv=/opt/vep/.vep/Plugins/spliceai_scores.raw.snv.hg38.vcf.gz,indel=/opt/vep/.vep/Plugins/spliceai_scores.raw.indel.hg38.vcf.gz \
--plugin CADD,/opt/vep/cadd/whole_genome_SNVs.tsv.gz,/opt/vep/cadd/gnomad.genomes.r3.0.indel.tsv.gz \







```