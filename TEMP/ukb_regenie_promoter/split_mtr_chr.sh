#!/bin/bash

mkdir mtr_scores && cd mtr_scores

dx download "$DX_PROJECT_CONTEXT_ID:/Resources/precalculated_scores/mtrflatfile_2.0.txt.gz"

dx download "$DX_PROJECT_CONTEXT_ID:/Resources/tmp_files/ensembl_genes_to_transcripts.tsv.gz"

dx download "$DX_PROJECT_CONTEXT_ID:/Resources/tmp_files/GRCh37_to_GRCh38.chain.gz"

gunzip ensembl_genes_to_transcripts.tsv.gz 



# header
echo -e "#chrom\tpos\tref\talt\tgene_id\tmtr_score" |\
bgzip > mtr_score_2.0_crossmap_hg38.tsv.gz


# lift over to hg38

~/.local/bin/CrossMap bed --chromid s --unmap-file mtr_score_2.0_crossmap_unmapped.log GRCh37_to_GRCh38.chain.gz <(zcat mtrflatfile_2.0.txt.gz  | awk -F"\t" 'NR==FNR{genes[$3]=$2;next}FNR> 1&& $11!=""{if($5 in genes) print $1,$2-1,$2,$3,$4,genes[$5],$11}' OFS="\t" ensembl_genes_to_transcripts.tsv - | sed  's/\t/,/4g' ) |\
awk '($5 == "->" || $5 ~ $1":"$3-1":"$3) && $1 == $6{print $1,$3,$NF}' OFS="," |\
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