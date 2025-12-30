annotate_vep() {


if [[ -f "$1" ]]; then

local input_vcf=$(basename "$1")

docker run \
--pull=never \
--platform linux/amd64 \
-v $VEP_HOME:/data \
vep_${VEP_VER} \
vep \
--offline \
--buffer_size ${VEP_BUFFER} \
--fork ${VEP_FORKS} \
--cache \
--dir_cache /data/cache \
--dir_plugins /data/plugins \
--fasta /data/fasta/human_reference.fa.gz \
--input_file /data/io/${input_vcf} \
--format vcf \
--output_file /data/io/${input_vcf%.vcf.gz}.vep.tsv.gz \
--tab \
--force_overwrite \
--compress_output gzip \
--minimal \
--protein \
--biotype \
--variant_class \
--regulatory \
--cell_type "astrocyte,brain_(p),neural_progenitor_cell_(f,_5_dpf),neuronal_stem_cell_(m),tibial_nerve_(m,_37_y),tibial_nerve_(m,_54_y)" \
--nearest gene \
--shift_3prime 1 \
--show_ref_allele \
--af_gnomadg \
--plugin NMD \
--plugin LoF,loftee_path:/data/plugins,human_ancestor_fa:/data/fasta/human_ancestor.fa.gz,conservation_file:/data/plugins/loftee.sql,gerp_bigwig:/data/plugins/gerp.bw,debug:0 \
--plugin UTRAnnotator,file=/data/plugins/uORF_5UTR_GRCh38_PUBLIC.txt \
--custom short_name=Gnocchi,file=/data/plugins/gnocchi.bw,format=bigwig \
--custom short_name=JARVIS,file=/data/plugins/jarvis.bw,format=bigwig \
--custom short_name=UKBDR,file=/data/plugins/ukb_depletion.bw,format=bigwig \
--custom short_name=GERP,file=/data/plugins/gerp.bw,format=bigwig \
--custom short_name=PhyloP,file=/data/plugins/phylop30.bw,format=bigwig \
--custom short_name=PhastCons,file=/data/plugins/phastcons30.bw,format=bigwig \
--custom short_name=TSS_region,file=/data/plugins/tss.bed.gz,format=bed \
--custom short_name=TAD_boundary,file=/data/plugins/tad.bed.gz,format=bed \
--plugin MiSc,MPC=/data/plugins/mpc.tsv.gz,REVEL=/data/plugins/revel.tsv.gz,AlphaMissense=/data/plugins/alpha_missense.tsv.gz,PrimateAI_3D=/data/plugins/pai3d.tsv.gz,multi=max,exact_indel_match=false \
--plugin GenSc,MTR=/data/plugins/mtr.tsv.gz,PromoterAI=/data/plugins/promoterai.tsv.gz,SpliceAI=/data/plugins/spliceai.tsv.gz,multi=max,exact_indel_match=false \
--plugin VarSc,CADD=/data/plugins/cadd.tsv.gz,multi=max,exact_indel_match=false \
--plugin TSSDistance \
--no_stats

else

    return 1

fi

}

