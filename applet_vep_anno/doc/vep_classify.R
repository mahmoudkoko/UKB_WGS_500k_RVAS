input_file <- 'vep/ukb24308_c19_b350.qc.sites.vep.tsv.gz'




```r
library(data.table)

args <- commandArgs(trailingOnly = TRUE)


# Read the first and second arguments
input_file <- args[1]

output_file <- gsub(pattern=".qc.sites.vep.tsv.gz",replacement=".csq.txt.gz",input_file)


VEP <- fread(paste0("vep/",input_file),skip="##",sep="\t",na.strings=c("-",".","","NA"),showProgress=FALSE,nThread=1)



collapse_scores <- function(i,s=",",d=2){

	o=max(-Inf,unlist(tstrsplit(gsub(i,pattern=",...",fixed=TRUE,replacement=""),s,type.convert=TRUE)));

	if (is.numeric(o) & !is.infinite(o)) {

  posneg = sign(o)
  z = abs(o)*10^d
  z = z + 0.5 + sqrt(.Machine$double.eps)
  z = trunc(z)
  z = z/10^d
  z*posneg

} else NA

}



collapse_scores_vector <- Vectorize(collapse_scores)



VEP[,c("Gnocchi","JARVIS","UKBDR","GERP","PhyloP","PhastCons"):=lapply(.SD,collapse_scores_vector),.SDcols=c("Gnocchi","JARVIS","UKBDR","GERP","PhyloP","PhastCons")]




##### Grouping



VEP[pmax(na.rm=TRUE,0, gnomADg_AF, gnomADg_NFE_AF) >= 1e-3,MAF:="Common"]
VEP[pmax(na.rm=TRUE,0, gnomADg_AF, gnomADg_NFE_AF) < 1e-3,MAF:="Low_freq"]
VEP[pmax(na.rm=TRUE,0, gnomADg_AF, gnomADg_NFE_AF) < 1e-4,MAF:="Rare"]
VEP[pmax(na.rm=TRUE,0, gnomADg_AF, gnomADg_NFE_AF) < 1e-5,MAF:="Ultra_rare"]




VEP[,CONSERVED:= (
		pmax(na.rm=TRUE,0,CADD > 2) +
			pmax(na.rm=TRUE,0,GERP > 2) +
				pmax(na.rm=TRUE,0,PhyloP > 1) +
					pmax(na.rm=TRUE,0,PhastCons > 0.5)
				)]



VEP[,CONSTRAINED:= (
		pmax(na.rm=TRUE,0,Gnocchi > 2) +
			pmax(na.rm=TRUE,0,JARVIS > 0.8) +
				pmax(na.rm=TRUE,0,UKBDR < 25) +
					pmax(na.rm=TRUE,0,MTR < 0.8)
						
				)]


VEP[ MAF == "Common" | ( CONSERVED == 0 & CONSTRAINED == 0), DAMAGING:="Unlikley"] # no evidence

VEP[ MAF != "Common" & ( CONSERVED > 0 | CONSTRAINED > 0), DAMAGING:="Possible"] # evidence from one domain

VEP[ MAF == "Ultra_rare" & CONSERVED > 0 & CONSTRAINED > 0, DAMAGING:="Plausible"] # evidence from all domains




### Collapse consequences


# split annotations (when there are several per variant# function to split multiple annotations annotated by vep for the same transcript
# from https://www.ensembl.org/info/genome/variation/prediction/predicted_data.html
csq_list <- c(
  "transcript_ablation",
  "high_confidence_ptv",
  "damaging_missense_variant",
  "low_confidence_ptv",  
  "splice_acceptor_variant",
  "splice_donor_variant", 
  "stop_gained",
  "frameshift_variant",
  "stop_lost",
  "start_lost",
  "transcript_amplification",
  "feature_elongation",
  "feature_truncation",
  "inframe_insertion",
  "inframe_deletion",
  "missense_variant",
  "protein_altering_variant",
  "splice_donor_5th_base_variant",
  "splice_region_variant",
  "splice_donor_region_variant",
  "splice_polypyrimidine_tract_variant",
  "incomplete_terminal_codon_variant",
  "start_retained_variant",
  "stop_retained_variant",
  "synonymous_variant",
  "coding_sequence_variant",
  "mature_miRNA_variant",
  "5_prime_UTR_variant",
  "3_prime_UTR_variant",
  "non_coding_transcript_exon_variant",
  "intron_variant",
  "NMD_transcript_variant",
  "non_coding_transcript_variant",
  "coding_transcript_variant",
  "TFBS_ablation",
  "TFBS_amplification",
  "TF_binding_site_variant",
  "damaging_promoter_variant",
  "promoter_region_variant",
  "proximal_enhancer_region",
  "distal_enhancer_region",
  "CTCF_TAD_region",
  "CTCF_binding_region",
  "regulatory_region_ablation",
  "regulatory_region_amplification",
  "regulatory_region_variant",
  "upstream_gene_variant",
  "downstream_gene_variant",
  "intergenic_variant",
  "sequence_variant"
)


collapse_csq <- function(i,o=csq_list){
j = strsplit(i,",")[[1]]
C <- length(o)+1
if(sum(j %in% o) > 0){
j <- j[j %in% o]
	for(c in seq_along(j)){ 
		C=min(C,which(o == j[c])) 
		}
	return(o[C])
}
else{
	return(j[1])
}
}

VEP[,CSQ:=as.character(collapse_csq(Consequence)),by=1:nrow(VEP)]






VEP[ LoF == "HC" & is.na(LoF_filter) & is.na(LoF_flags) &  is.na(NMD),CSQ:="high_confidence_ptv"]

VEP[ LoF == "LC" | LoF == "HC" & ( !is.na(LoF_filter) | !is.na(LoF_flags) |  !is.na(NMD) ),CSQ:="low_confidence_ptv"]

VEP[ CSQ == "missense_variant" & REVEL > 0.5 & MPC > 2 & AlphaMissense > 0.565 ,CSQ:="damaging_missense_variant"]




VEP[BIOTYPE == 'promoter' , CSQ:="promoter_region_variant"]

VEP[BIOTYPE == 'promoter' &  (PromoterAI > 0.5 | PromoterAI < -0.5) ,CSQ:="damaging_promoter_variant"]



VEP[BIOTYPE == 'enhancer' & ( !is.na(TSS_region) | TSSDistance < 2000 ) ,CSQ:="proximal_enhancer_region"]

# add activity to ranking

VEP[BIOTYPE == 'enhancer' &  CSQ !=  'proximal_enhancer_region' , CSQ:="distal_enhancer_region"]


VEP[BIOTYPE == 'CTCF_binding_site' & !is.na(TAD_boundary),CSQ:="CTCF_TAD_region"]

VEP[BIOTYPE == 'CTCF_binding_site' & is.na(TAD_boundary),CSQ:="CTCF_binding_region"]




# Worst per variant

VEP[,CSQ_Rank:=as.integer(as.character(factor(CSQ,levels=csq_list,labels=1:length(csq_list))))]




VEP[,CSQ_WORST:=(CSQ_Rank == min(CSQ_Rank)),by= "#Uploaded_variation"]
# Recoding


VEP_FILTERED <- VEP[CSQ_WORST==TRUE & CSQ %in% c('high_confidence_ptv','low_confidence_ptv','damaging_missense_variant','damaging_promoter_variant','promoter_region_variant','proximal_enhancer_region','distal_enhancer_region','CTCF_TAD_region','CTCF_binding_region')][,.N,by=c("#Uploaded_variation","Gene","CSQ","DAMAGING")][,.(ID=paste0("DRAGEN:",`#Uploaded_variation`),CSQ)]

fwrite(VEP_FILTERED,paste0("csq/",output_file),col.names=FALSE)


```