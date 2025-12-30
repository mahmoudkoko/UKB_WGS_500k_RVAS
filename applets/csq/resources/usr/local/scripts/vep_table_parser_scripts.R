###########################
## Split table into batches
###########################

read_vep_table_blocks <- function(
  vep_table_path,
  vep_cols_to_read = c(
  "#Uploaded_variation",
  "VARIANT_CLASS",
  "BIOTYPE",
  "FLAGS",
  "CELL_TYPE",
  "MOTIF_NAME",
  "Gene",
  "Feature",
  "Feature_type",
  "Consequence",
  "LoF",
  "LoF_filter",
  "LoF_flags",
  "NMD",
  "5UTR_annotation",
  "5UTR_consequence",
  "Existing_InFrame_oORFs",
  "Existing_OutOfFrame_oORFs",
  "Existing_uORFs",
  "CADD",
  "MPC",
  "REVEL",
  "AlphaMissense",
  "PrimateAI_3D",
  "SpliceAI",
  "PromoterAI",
  "MTR",
  "Gnocchi",
  "JARVIS",
  "UKBDR",
  "GERP",
  "PhyloP",
  "PhastCons",
  "gnomADg_AF",
  "TSSDistance",
  "TSS_region",
  "TAD_boundary"),
  target_block_size=10000 ){

# Default column classes

vep_col_classes_all = c(
  "#Uploaded_variation" = "character", "Location" = "character", "Allele" = "character",
  "Gene" = "character", "Feature" = "character", "Feature_type" = "character",
  "Consequence" = "character", "cDNA_position" = "character", "CDS_position" = "character",
  "Protein_position" = "character", "Amino_acids" = "character", "Codons" = "character",
  "Existing_variation" = "character", "ALLELE_NUM" = "character", "REF_ALLELE" = "character",
  "IMPACT" = "character", "DISTANCE" = "character", "STRAND" = "character",
  "FLAGS" = "character", "VARIANT_CLASS" = "character", "MINIMISED" = "character",
  "BIOTYPE" = "character", "ENSP" = "character", "SOURCE" = "character",
  "NEAREST" = "character", "gnomADg_AF" = "numeric", "gnomADg_AFR_AF" = "numeric",
  "gnomADg_AMI_AF" = "numeric", "gnomADg_AMR_AF" = "numeric", "gnomADg_ASJ_AF" = "numeric",
  "gnomADg_EAS_AF" = "numeric", "gnomADg_FIN_AF" = "numeric", "gnomADg_MID_AF" = "numeric",
  "gnomADg_NFE_AF" = "numeric", "gnomADg_REMAINING_AF" = "numeric", "gnomADg_SAS_AF" = "numeric",
  "CLIN_SIG" = "character", "SOMATIC" = "character", "PHENO" = "character",
  "MOTIF_NAME" = "character", "MOTIF_POS" = "character", "HIGH_INF_POS" = "character",
  "MOTIF_SCORE_CHANGE" = "character", "TRANSCRIPTION_FACTORS" = "character",
  "CELL_TYPE" = "character", "NMD" = "character", "LoF" = "character",
  "LoF_filter" = "character", "LoF_flags" = "character", "LoF_info" = "character",
  "5UTR_annotation" = "character", "5UTR_consequence" = "character",
  "Existing_InFrame_oORFs" = "character", "Existing_OutOfFrame_oORFs" = "character",
  "Existing_uORFs" = "character", "AlphaMissense" = "numeric", "MPC" = "numeric",
  "PrimateAI_3D" = "numeric", "REVEL" = "numeric", "MTR" = "numeric",
  "PromoterAI" = "numeric", "SpliceAI" = "numeric", "CADD" = "numeric",
  "TSSDistance" = "integer", "Gnocchi" = "character", "JARVIS" = "character",
  "UKBDR" = "character", "GERP" = "character", "PhyloP" = "character",
  "PhastCons" = "character", "TSS_region" = "character", "TAD_boundary" = "character"
)


# Set droppted columns to "NULL"
vep_col_classes_target <- ifelse(names(vep_col_classes_all) %in% vep_cols_to_read, vep_col_classes_all, "NULL")
names(vep_col_classes_target) <- names(vep_col_classes_target)


# Read VEP table and split into blocks
vep_data_table <- fread(vep_table_path,colClasses=vep_col_classes_target,skip="##",sep="\t",na.strings=c("-",".","","NA"))


# Fix gnomad col
vep_data_table[,gnomADg_AF:=fifelse( is.na(gnomADg_AF),0,gnomADg_AF,0)]


# count rows
n_rows <- nrow(vep_data_table)

# estimate blocks
n_blocks <- ceiling(n_rows / target_block_size)

target_nrows <- ceiling(n_rows / n_blocks)

# initiate list
target_table <- vector(length=n_blocks, mode="list")


# Process batches first, then columns within each batch
for (rows_block in 1:n_blocks) {

  # Calculate row indices for current batch
  start_row <- (rows_block - 1) * target_nrows + 1
  end_row <- min(rows_block * target_nrows, n_rows)
  
  target_table[[ rows_block ]] <- vep_data_table[start_row : end_row,]
  
  }

rm(vep_data_table); invisible(gc())

return(target_table)

}



############################################################################################################
## A) Helper functions to pre-process columns in-place #####################################################
############################################################################################################


#################################################
### Parsing several CSQ per line to a single term
#################################################

# VEP assigns several consequences per line on the same feature.
# The goal here is to pick the worst consequence across these consequences.

collapse_csq <- function(input_strings,
  ranking_vector = c(
  "transcript_ablation",
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
  "upstream_gene_variant",
  "downstream_gene_variant",
  "TFBS_ablation",
  "TFBS_amplification",
  "TF_binding_site_variant",
  "regulatory_region_ablation",
  "regulatory_region_amplification",
  "regulatory_region_variant",
  "intergenic_variant",
  "sequence_variant")) {


  # Pre-allocate result vector for memory efficiency
  n <- length(input_strings)
  result <- character(n)
  
  # Process each string
  for (i in seq_len(n)) {

    # Split the current string
    values <- strsplit(input_strings[i], ",", fixed = TRUE)[[1]]
    
    # Find matches in ranking vector
    matches <- match(values, ranking_vector, nomatch = NA)
    
    # Ignore NA's
    valid_matches <- matches[!is.na(matches)]
    
    # Return best match or first value if no matches
    if (length(valid_matches) > 0) {

      # pick best rank
      best_idx <- which.min(valid_matches)

      # pick value of best rank
      result[i] <- values[!is.na(matches)][best_idx]

    } else {

      # return first value as fall-back
      result[i] <- values[1]
    }
  }
  
  return(result)
}




################################################################
### Parsing UTRAnnotator results into a single output: uORF/oORF
################################################################

# Function to assess whether the variant creates an overlapping ORF or not. It assesses one entry of UTRAnnotar consequence/annotation results (label and its details)
assess_oORF_impact <- function(label, details) {
  # Default to low impact
  impact <- 1
  
  if (label == "5_prime_UTR_premature_start_codon_gain_variant") {
    # Criteria:
    # 1. type is "inframe_oORF" or "OutOfFrame_oORF"
    # 2. KozakStrength is "Moderate" OR "Strong"
    # 3. DistanceToCDS < 50
    
    type_check <- ("type" %in% names(details)) && 
                 (details[["type"]] %in% c("inframe_oORF", "OutOfFrame_oORF"))
    
    kozak_check <- ("KozakStrength" %in% names(details)) && 
                  (details[["KozakStrength"]] %in% c("Moderate", "Strong"))
    
    distance_check <- FALSE
    if ("DistanceToCDS" %in% names(details)) {
      distance_val <- as.numeric(details[["DistanceToCDS"]])
      if (!is.na(distance_val) && distance_val < 50) {
        distance_check <- TRUE
      }
    }
    
    if (type_check && kozak_check && distance_check) {
      impact <- 0
    }
    
  } else if (label == "5_prime_UTR_uORF_stop_codon_loss_variant") {
    # Criteria:
    # 1. type is "inframe_oORF" or "OutOfFrame_oORF"
    # 2. KozakStrength is "Moderate" OR "Strong" OR Evidence is "True"
    
    type_check <- ("type" %in% names(details)) && 
                 (details[["type"]] %in% c("inframe_oORF", "OutOfFrame_oORF"))
    
    kozak_evidence_check <- FALSE
    if ("KozakStrength" %in% names(details)) {
      kozak_evidence_check <- details[["KozakStrength"]] %in% c("Moderate", "Strong")
    }
    if (!kozak_evidence_check && "Evidence" %in% names(details)) {
      kozak_evidence_check <- details[["Evidence"]] == "True"
    }
    
    if (type_check && kozak_evidence_check) {
      impact <- 0
    }
    
  } else if (label == "5_prime_UTR_uORF_frameshift_variant") {
    # Criteria:
    # 1. alt_type is "inframe_oORF" or "OutOfFrame_oORF"
    # 2. KozakStrength is "Moderate" OR "Strong" OR Evidence is "True"
    # 3. ref_type is "uORF"
    
    alt_type_check <- ("alt_type" %in% names(details)) && 
                     (details[["alt_type"]] %in% c("inframe_oORF", "OutOfFrame_oORF"))
    
    kozak_evidence_check <- FALSE
    if ("KozakStrength" %in% names(details)) {
      kozak_evidence_check <- details[["KozakStrength"]] %in% c("Moderate", "Strong")
    }
    if (!kozak_evidence_check && "Evidence" %in% names(details)) {
      kozak_evidence_check <- details[["Evidence"]] == "True"
    }
    
    ref_type_check <- ("ref_type" %in% names(details)) && 
                     (details[["ref_type"]] == "uORF")
    
    if (alt_type_check && kozak_evidence_check && ref_type_check) {
      impact <- 0
    }
  }
  # For any other labels, impact remains "low"
  
  return(impact)
}


# Function to parse a single line of UTRAnnotator results (takes annotation labels nad details strings and assess overall impact of each pair if there are several pairs)
parse_uORF_annotation <- function(details_string, label_string) {
  # Split labels by &
  labels <- strsplit(label_string, "&")[[1]]
  
  # Split details by &
  details_groups <- strsplit(details_string, "&")[[1]]
  
  # Parse each details group into key-value pairs
  parsed_details <- list()
  
  for (i in seq_along(details_groups)) {
    # Split by : to get key=value pairs
    pairs <- strsplit(details_groups[i], ":")[[1]]
    details_dict <- list()
    
    for (pair in pairs) {
      if (grepl("=", pair)) {
        # Split only on first = in case value contains =
        key_value <- strsplit(pair, "=", fixed = TRUE)[[1]]
        if (length(key_value) >= 2) {
          key <- key_value[1]
          value <- paste(key_value[2:length(key_value)], collapse = "=")
          details_dict[[key]] <- value
        }
      }
    }
    
    parsed_details[[i]] <- details_dict
  }
  
  # Assess individual impacts and calculate overall impact
  overall_impact <- 1
  
  for (i in seq_along(labels)) {
    current_details <- if (i <= length(parsed_details)) parsed_details[[i]] else list()
    current_impact <- assess_oORF_impact(labels[i], current_details)
    overall_impact <- (overall_impact * current_impact)
  }
  
  # Overall impact: high if ANY individual impact is high (overall_impact == 0)
  overall_impact <- if (overall_impact == 0) "oORF" else "uORF"
  
  return(overall_impact)
}


# Wrapper to run the last function on vector of results (a for loop to limit mem dependence) - returns vector of impact assessments
parse_UTRAnnotator_results <- function(details_vector, label_vector) {
  # Check that vectors are the same length
  if (length(details_vector) != length(label_vector)) {
    stop("Details vector and label vector must be the same length")
  }
  
  # Apply to all entries in the vectors and return as vector
  result <- character(length(details_vector))
  for (i in seq_along(details_vector)) {
    result[i] <- parse_uORF_annotation(details_vector[i], label_vector[i])
  }
  
  return(result)
}


#########################################
### Parsing activity of regulatory motifs
#########################################



parse_regulatory_activity <- function(vep_cell_types_anno, target_cell_types=c("astrocyte","brain_(p)","neuronal_stem_cell_(m)")) {
  
  # Pre-allocate result vector for memory efficiency
  result <- character(length(vep_cell_types_anno))
  
  # Loop over each input string
  for (i in seq_along(vep_cell_types_anno)) {
    item <- vep_cell_types_anno[i]
    is_active <- FALSE
    
    # Split into key:value pairs
    pairs <- strsplit(item, ",")[[1]]
    
    # Loop over each key:value pair
    for (pair in pairs) {
      kv <- strsplit(pair, ":")[[1]]
      if (length(kv) == 2) {
        key <- trimws(kv[1])
        value <- trimws(kv[2])
        
        if (key %in% target_cell_types && value == "ACTIVE") {
          is_active <- TRUE
          break  # No need to check further
        }
      }
    }
    
    result[i] <- if (is_active) "ACTIVE" else "INACTIVE"
  }
  
  return(result)
}



#######################################################
### Splitting csv of conservation and constraint scores
#######################################################

# This function takes the max per line from custom scores (vep --custom BigWig)


collapse_csv_scores <- function(input_strings) {
  results <- numeric(length(input_strings))  # Preallocate as numeric
  
  for (i in seq_along(input_strings)) {
    j <- input_strings[i]
    
    if (is.na(j) || j == "") {
      results[i] <- NA_integer_
      next
    }

    if (is.numeric(j) ){

      results[i] <- j
      next

    }
    
    # Split and safely coerce to numeric
    values <- suppressWarnings(as.numeric(strsplit(j, ",", fixed = TRUE)[[1]]))
    
    # Remove NAs before taking max, or return NA if all are invalid
    if (all(is.na(values))) {
      results[i] <- NA_integer_
    } else {
      results[i] <- as.numeric(max(values, na.rm = TRUE))
    }
  }
  
  return(results)
}



###########################
### Update VEP Consequences
###########################

update_vep_consequences <- function(vep_data_table){


# Parse consequences: select most severe per line if several
vep_data_table[ , Consequence := collapse_csq(Consequence) ]


# Update CSQ for cryptic splice sites
vep_data_table[

  SpliceAI > 0.5 & !( Consequence %in% c(
    "splice_acceptor_variant",
    "splice_donor_variant",
    "splice_region_variant",
    "splice_donor_5th_base_variant",
    "splice_donor_region_variant",
    "splice_polypyrimidine_tract_variant"
    )
  )
  ,

  "Consequence" := "splice_cryptic_region_variant"

]


# Parse oORF data: assess whether this is high or low impact uORF variant
vep_data_table[ !is.na(`5UTR_consequence`), "5UTR_consequence" := parse_UTRAnnotator_results(`5UTR_annotation`,`5UTR_consequence`) ]


# Update 5UTR if it is annotated as uORF-creating (this leaves 5UTR if not not creating uORF)
vep_data_table[ Consequence == "5_prime_UTR_variant" , Consequence := fcase(
                                                                                (`5UTR_consequence` == "oORF" & Existing_OutOfFrame_oORFs == 0 & Existing_InFrame_oORFs == 0), "5_prime_oORF_variant",
                                                                                (`5UTR_consequence` == "uORF" | Existing_OutOfFrame_oORFs > 0 | Existing_InFrame_oORFs > 0), "5_prime_uORF_variant",
                                                                                default = "5_prime_UTR_variant" ) ]




# update activity column
vep_data_table[ !is.na(CELL_TYPE) ,  "CELL_TYPE" := parse_regulatory_activity(CELL_TYPE) ]


# Update Gene column
vep_data_table[, "Gene" := fcase(
                                  (Feature_type == "Transcript"), as.character(Gene),
                                  Feature_type == "RegulatoryFeature", as.character(Feature),
                                  Feature_type == "MotifFeature", as.character(MOTIF_NAME),
                                  default = "None" ) ]



}


update_lof_consequences <- function(vep_data_table){

# LoF confidence


# Update the column LoF (Loftee) to represent LoF impact more generally

# 1. Revise Loftee verdict to take flags into account
vep_data_table[ !is.na(LoF) , "LoF" := fcase( 
                                              (LoF == "HC" & is.na(LoF_filter) & is.na(LoF_flags) & is.na(NMD)), "HC",
                                               default = "LC") ]


# 2. Annotate transcript ablation as HC LoF if no loftee flag
vep_data_table[ Consequence == "transcript_ablation", "LoF" := fcase ( LoF == "LC", "LC", default = "HC") ]


# 3. Upgrade splice site variants as high confidence if splice ai score is > 0.5
vep_data_table[ Consequence %in% c(
  "splice_acceptor_variant",
  "splice_donor_variant", 
  "splice_donor_5th_base_variant",
  "splice_region_variant",
  "splice_donor_region_variant",
  "splice_polypyrimidine_tract_variant"
   ),

  "LoF" := fcase( (LoF == "HC" | SpliceAI > 0.5 ), "HC", default = "LC") ]



# 4. Annotate LoF for cryptic splice regions as high confidence if spliceai > 0.8
vep_data_table[ Consequence == "splice_cryptic_region_variant", "LoF" := fcase( (LoF == "HC" | SpliceAI > 0.8 ), "HC", default = "LC") ]


# 4. Annotate candidate pLoF with missing LOFTEE annotation as LC

vep_data_table[

  is.na(LoF) &
  Consequence %in% c(
  "splice_acceptor_variant",
  "splice_donor_variant",
  "stop_gained",
  "frameshift_variant",
  "stop_lost",
  "start_lost",
  "splice_donor_5th_base_variant",
  "splice_region_variant",
  "splice_donor_region_variant",
  "splice_polypyrimidine_tract_variant",
  "5_prime_oORF_variant"),

  "LoF" := "LC"]


}




#####################################################################################################
## B) Functions to stratifying variants in groups ###################################################
#####################################################################################################

###################################
### CADD/ Conservation / constraint
###################################


stratify_constraint_cadd_conservarion_maf <- function(vep_data_table){


# Take the max value from custom columns (conservation and constraint scores):

# Vector of target column names
vep_bigwig_cols <- c("Gnocchi", "JARVIS", "UKBDR", "GERP", "PhyloP", "PhastCons")



# Doing one column at a time to reduce mem usage

for ( col in vep_bigwig_cols) { vep_data_table[, (col) := collapse_csv_scores( get(col) )]  }


# Create numeric scores for MAF/Conservation&CADD/Constraint

vep_data_table[, "CONSERVED" :=  pmax(na.rm=TRUE, 0, CADD > 1, GERP > 2, PhyloP > 1, PhastCons > 0.5) ]

vep_data_table[, "CONSTRAINED" :=  pmax(na.rm=TRUE, 0, Gnocchi > 2, JARVIS > 0.8, UKBDR < 25, MTR < 0.8) ]

vep_data_table[, "URARE" := pmax(na.rm=TRUE, 0, gnomADg_AF < 1e-5) ]




# Create "Deleteriousness" tranches

vep_data_table[ , "DAMAGING" := fcase (
                                      (CONSERVED == 1 & CONSTRAINED == 1 & URARE == 1 ) , "Plausible",
                                      (CONSERVED == 1 | CONSTRAINED == 1 ), "Possible",
                                      default = "Unlikely"
                                      )]

}


############
### Biotypes
############


stratify_vep_biotypes <- function(vep_data_table){


# Classify features to five analysis groups: protein-coding, lncRNA, (short) ncRNA, conserved Regulatory Elements, intergenic

# 1. Protein-coding and RNA genes (including polymorphic pseudogenes with evidence of translation)

transcript_biotypes <- c(
  "protein_coding",
  "protein_coding_LoF",
  "lncRNA",
  "miRNA",
  "snRNA",
  "snoRNA",
  "scaRNA",
  "vault_RNA",
  "sRNA",
  "misc_RNA",
  "tRNA",
  "ribozyme",
  "Mt_tRNA",
  "Mt_rRNA"
  )


vep_data_table[ BIOTYPE %in% transcript_biotypes ,
  "GROUP" := fcase(
                  (BIOTYPE %in% c("protein_coding","protein_coding_LoF") ), "PROT",
                  (BIOTYPE == "lncRNA" ), "LRNA",
                  default = "NCRNA" ) ]


# 2. cRE and TFBS


cre_biotypes <- c(
  "promoter",
  "enhancer",
  "CTCF_binding_site",
  "open_chromatin_region",
  "TF_binding_site"
  )

# add UTR to these as well 
vep_data_table[ BIOTYPE %in% cre_biotypes | Consequence %in% c("upstream_gene_variant","downstream_gene_variant"), "GROUP" := "CRE" ]

       

# 3. All other things or flagged transcripts:

vep_data_table[ is.na(GROUP) | !is.na(FLAGS) , GROUP:="OTHER" ]


}




########################
### Variant consequences
########################


stratify_protein_csq <- function(vep_data_table){

# PTVs

ptv_csq <- c(
    "transcript_ablation",
    "stop_gained",
    "frameshift_variant",
    "stop_lost",
    "start_lost",
    "5_prime_oORF_variant"
    )

vep_data_table[ GROUP == "PROT" & Consequence %in% ptv_csq, "CSQ_PROT" := fcase( (LoF == "HC"), "PTV_HC", default = "PTV_LC") ]


# Splice sites

splice_csq <- c(
    "splice_acceptor_variant",
    "splice_donor_variant",
    "splice_region_variant",
    "splice_donor_5th_base_variant",
    "splice_donor_region_variant",
    "splice_polypyrimidine_tract_variant",
    "splice_cryptic_region_variant"
    )

vep_data_table[ GROUP == "PROT" & Consequence %in% splice_csq , "CSQ_PROT" := fcase( (LoF == "HC"), "SPLICE_HC", default = "SPLICE_LC") ]



# Missense

vep_data_table[ GROUP == "PROT" & Consequence == "missense_variant", "CSQ_PROT" := as.character(
                                                                factor(
                                                                      x=(fifelse( MPC > 2, 1, 0, na=0) + fifelse( REVEL > 0.5, 1, 0, na=0) + fifelse( AlphaMissense > 0.5, 1, 0, na=0) + fifelse( PrimateAI_3D > 0.8, 1, 0, na=0) ),
                                                                      levels=c(0,1,2,3,4),
                                                                      labels = c("MIS_NC","MIS_LC","MIS_LC","MIS_HC","MIS_HC") 
                                                                      )
                                                                      )]

# Inframe and other

indel_csq <- c(
  "inframe_insertion",
  "inframe_deletion",
  "protein_altering_variant",
  "coding_sequence_variant",
  "feature_elongation",
  "feature_truncation",
  "transcript_amplification"
  )

vep_data_table[ GROUP == "PROT" & Consequence %in% indel_csq , "CSQ_PROT" := "INFRAME" ]



# UTR
utr_csq <- c("5_prime_UTR_variant", "3_prime_UTR_variant", "5_prime_uORF_variant", "intron_variant")


vep_data_table[ GROUP == "PROT" & Consequence %in% utr_csq , "CSQ_PROT" := fcase(
                                                        (Consequence == "5_prime_uORF_variant"), "UTR_uORF",
                                                        (Consequence == "5_prime_UTR_variant"), "UTR_5prime",
                                                        (Consequence == "3_prime_UTR_variant"), "UTR_3prime",
                                                        default = "INTRON" )]


# Synonymous
vep_data_table[ GROUP == "PROT" & Consequence %in% c("start_retained_variant", "stop_retained_variant", "synonymous_variant"), "CSQ_PROT" := "SYN"]



# Fall back

vep_data_table[ GROUP == "PROT" & is.na(CSQ_PROT), "CSQ_PROT" := "UNCLASSIFIED"]


# Other groups

#vep_data_table[ GROUP != "PROT" , "CSQ_PROT" := "NOT_APPLICABLE"]




}






stratify_lrna_csq <- function(vep_data_table){


# RNA variants other than intronic

lncrna_csq <- c("transcript_ablation",
    "splice_acceptor_variant",
    "splice_donor_variant",
    "splice_region_variant",
    "splice_donor_5th_base_variant",
    "splice_donor_region_variant",
    "splice_polypyrimidine_tract_variant",
    "splice_cryptic_region_variant",
    "non_coding_transcript_exon_variant",
    "non_coding_transcript_variant","intron_variant")

vep_data_table[ GROUP == "LRNA" & Consequence %in% lncrna_csq , "CSQ_LRNA" := fcase( 
                                                                    (LoF == "HC" | Consequence %in% c("transcript_ablation","splice_acceptor_variant","splice_donor_variant")), "SPLICE_HC",
                                                                    (Consequence %in% c("non_coding_transcript_exon_variant")), "EXON",
                                                                    (Consequence %in% c("non_coding_transcript_variant","intron_variant")), "INTRON",
                                                                    default = "SPLICE_LC") ]




# Fall back

vep_data_table[ GROUP == "LRNA" & is.na(CSQ_LRNA), "CSQ_LRNA" := "UNCLASSIFIED"]


#vep_data_table[ GROUP != "LRNA" , "CSQ_LRNA" := "NOT_APPLICABLE"]



}



stratify_ncrna_csq <- function(vep_data_table){

rna_csq <- c("transcript_ablation",
    "splice_acceptor_variant",
    "splice_donor_variant",
    "splice_region_variant",
    "splice_donor_5th_base_variant",
    "splice_donor_region_variant",
    "splice_polypyrimidine_tract_variant",
    "splice_cryptic_region_variant",
    "mature_miRNA_variant",
    "non_coding_transcript_exon_variant",
    "non_coding_transcript_variant","intron_variant")


vep_data_table[ GROUP == "NCRNA" & Consequence %in% rna_csq , "CSQ_NCRNA" := fcase( 
                                                                    (LoF == "HC" | Consequence %in% c("transcript_ablation","splice_acceptor_variant","splice_donor_variant")), "SPLICE_HC",
                                                                    (Consequence %in% c("non_coding_transcript_exon_variant","mature_miRNA_variant")), "EXON",
                                                                    (Consequence %in% c("non_coding_transcript_variant","intron_variant")), "INTRON",
                                                                    default = "SPLICE_LC") ]

# Fall back

vep_data_table[ GROUP == "NCRNA" & is.na(CSQ_NCRNA), "CSQ_NCRNA" := "UNCLASSIFIED"]


# Other groups


#vep_data_table[ GROUP != "NCRNA" , "CSQ_NCRNA" := "NOT_APPLICABLE"]



}





stratify_cre_csq <- function(vep_data_table){



# Promoter variants
vep_data_table[ BIOTYPE == 'promoter'  & CELL_TYPE == "ACTIVE"  , "CSQ_CRE" := fcase(
                                                                              ( PromoterAI > 0.5 | PromoterAI < -0.5), "PROM_ActH",
                                                                              ( PromoterAI > 0.2 | PromoterAI < -0.2), "PROM_ActM",
                                                                              default = "PROM_Act" )]


vep_data_table[ BIOTYPE == 'promoter'  & (CELL_TYPE == "INACTIVE" | is.na(CELL_TYPE) )  , "CSQ_CRE" := fcase(
                                                                                ( PromoterAI > 0.5 | PromoterAI < -0.5), "PROM_InactH",
                                                                                ( PromoterAI > 0.2 | PromoterAI < -0.2), "PROM_InactM",
                                                                                default = "PROM_Inact" )]



# Enhancer variants

# Need to double check if pELS can be after the TSS or only upstream

vep_data_table[ BIOTYPE == 'enhancer' & CELL_TYPE == "ACTIVE"   , "CSQ_CRE" := fcase( 
                                                                              ( TSSDistance < 2000 | !is.na(TSS_region) ), "ENH_ActProx",
                                                                               default = "ENH_ActDist" ) ]


vep_data_table[ BIOTYPE == 'enhancer' & (CELL_TYPE == "INACTIVE" | is.na(CELL_TYPE) ) , "CSQ_CRE" := fcase( 
                                                                              ( TSSDistance < 2000 | !is.na(TSS_region) ), "ENH_InactProx",
                                                                               default = "ENH_InactDist" ) ]

# CTCF-bindings sites
vep_data_table[ BIOTYPE %in% c("CTCF_binding_site", "open_chromatin_region", "TF_binding_site") | Consequence %in% c("upstream_gene_variant","downstream_gene_variant"),
                                                                  "CSQ_CRE" := fcase(
                                                                              ( BIOTYPE == "CTCF_binding_site" & !is.na(TAD_boundary) ), "EMAR_TAD",
                                                                              ( BIOTYPE == "CTCF_binding_site" ), "EMAR_CTCF",
                                                                              ( BIOTYPE == "TF_binding_site" ), "EMAR_TFBS",
                                                                              ( BIOTYPE == "open_chromatin_region" ), "EMAR_OTHER",
                                                                              ( Consequence == "upstream_gene_variant"), "UPST_GENE",
                                                                              ( Consequence == "downstream_gene_variant"), "DNST_GENE",
                                                                               default = "CRE_OTHER" )]



# Fall back

vep_data_table[ GROUP == "CRE" & is.na(CSQ_CRE), "CSQ_CRE" := "UNCLASSIFIED"]



# Other groups

#vep_data_table[ GROUP != "CRE" , "CSQ_CRE" := "NOT_APPLICABLE"]

}




stratify_other_csq <- function(vep_data_table){



ig_tr_biotypes <- c(
  "IG_C_gene",
  "IG_V_gene",
  "TR_J_gene",
  "IG_J_gene",
  "TR_D_gene",
  "IG_D_gene",
  "TR_C_gene",
  "TR_V_gene"
  )


other_biotypes <- c(
"protein_coding_CDS_not_defined",
"retained_intron",
"non_stop_decay",
"nonsense_mediated_decay",
"processed_transcript",
"transcribed_unitary_pseudogene",
"transcribed_unprocessed_pseudogene",
"unitary_pseudogene",
"translated_processed_pseudogene",
"IG_C_pseudogene",
"transcribed_processed_pseudogene",
"IG_pseudogene",
"IG_J_pseudogene",
"rRNA_pseudogene",
"TR_J_pseudogene",
"IG_V_pseudogene",
"pseudogene",
"TR_V_pseudogene",
"unprocessed_pseudogene",
"processed_pseudogene",
"artifact",
"TEC"
)



vep_data_table[GROUP == "OTHER" , "CSQ_OTHER" := fcase(
#                                        (GROUP != "OTHER"), "NOT_APPLICABLE",
                                        (BIOTYPE %in% ig_tr_biotypes ), "IGTR",
                                        (!is.na(FLAGS) | BIOTYPE %in% other_biotypes | Consequence %in% c("NMD_transcript_variant","coding_transcript_variant","incomplete_terminal_codon_variant")), "FLAG",
                                        (Consequence %in% c("intergenic_variant","sequence_variant")), "INTERGENIC",
                                        default = "UNCLASSIFIED") ]


#


}




#########
# Wrapper
#########


process_vep_block <- function(vep_data_table){

# Process the consequences column, update the regulatory acitivity, add feature names to gene name, etc
update_vep_consequences(vep_data_table)


# Update LoF classification
update_lof_consequences(vep_data_table)


# Stratify constraint/cadd/conservation/maf (this calls collapse_csv_scores())
stratify_constraint_cadd_conservarion_maf(vep_data_table)


# Stratify biotype groups
stratify_vep_biotypes(vep_data_table)


# Stratify CSQ
stratify_protein_csq(vep_data_table)
stratify_lrna_csq(vep_data_table)
stratify_ncrna_csq(vep_data_table)
stratify_cre_csq(vep_data_table)
stratify_other_csq(vep_data_table)




# Rename ID column
setnames(vep_data_table,"#Uploaded_variation","ID")

# Get allele from var ID
vep_data_table[,c("Chrom","Pos","Ref_allele","Alt_allele"):=tstrsplit(ID,":",fixed=TRUE,type.convert = list(as.character, as.integer, as.character, as.character))]


# Original ID format
vep_data_table[,"ID":=paste0("DRAGEN:",ID)]

# Order columns
keep_vep_cols <- c('Chrom','Pos','ID','Ref_allele','Alt_allele','Gene','VARIANT_CLASS','gnomADg_AF','CADD','CONSERVED','CONSTRAINED','DAMAGING','GROUP','CSQ_PROT','CSQ_CRE','CSQ_LRNA','CSQ_NCRNA','CSQ_OTHER')
setcolorder(vep_data_table,keep_vep_cols)

# squish cols
vep_data_table[, setdiff(names(vep_data_table), keep_vep_cols) := NULL]


#order rows
setorder(vep_data_table,"Pos","Ref_allele","Alt_allele","Gene")


# Cleanup mem once done
invisible(gc())

}



bind_variant_blocks <- function(variant_csq_blocks,
variant_csq_rank=c(
"PTV_HC",
"SPLICE_HC",
"MIS_HC",
"PROM_ActH",
"PTV_LC",
"SPLICE_LC",
"MIS_LC",
"INFRAME",
"MIS_NC",
"EXON",
"IGTR",
"PROM_ActM",
"PROM_Act",
"ENH_ActProx",
"ENH_ActDist",
"UTR_uORF",
"UTR_5prime",
"UTR_3prime",
"PROM_InactH",
"PROM_InactM",
"PROM_Inact",
"ENH_InactProx",
"ENH_InactDist",
"EMAR_TAD",
"EMAR_CTCF",
"EMAR_TFBS",
"EMAR_OTHER",
"UPST_GENE",
"DNST_GENE",
"CRE_OTHER",
"SYN",
"INTRON",
"FLAG",
"UNCLASSIFIED",
"INTERGENIC",
"NOT_APPLICABLE")
){


# Merge all blocks
vep_csq_table <- rbindlist(variant_csq_blocks) |>
          melt(
                    measure.vars = c('CSQ_PROT','CSQ_CRE','CSQ_LRNA','CSQ_NCRNA','CSQ_OTHER'),
                    variable.name = "CSQ_GROUP",
                    value.name="CSQ",
                    variable.factor = FALSE,
                    value.factor = FALSE,
                    na.rm=TRUE) |>
                    unique()


vep_csq_table[, Worst_Rank:= as.integer(as.character(factor(CSQ,levels=variant_csq_rank,labels=1:length(variant_csq_rank))))]

# Worst within an analysis group (e.g., across transcripts within protein coding or across cRE)
vep_csq_table[,Worst_Within:=(Worst_Rank == min(Worst_Rank)),by= c("ID","GROUP")]

# Remove any CSQ that is not the worst within its own group
vep_csq_table <- vep_csq_table[Worst_Within==TRUE,][,Worst_Within:=NULL] |> unique()


# Worst across all annotations (i.e., across all transcripts, regulatory, etc)
vep_csq_table[,WORST_GROUP:=paste0(collapse=",",unique(na.omit(fifelse(Worst_Rank == min(Worst_Rank),GROUP,NA,NA)))),by= "ID"]
vep_csq_table[,WORST_CSQ:= fifelse(Worst_Rank == min(Worst_Rank),"Yes","No","-"),by= "ID"]



vep_csq_table[,Worst_Rank:=NULL]
vep_csq_table[,CSQ_GROUP:=NULL]

return(vep_csq_table[])

}
