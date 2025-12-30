#!/usr/bin/env Rscript


library(optparse)
library(data.table)
setDTthreads(1)
options(datatable.showProgress = FALSE)
source("/usr/local/scripts/vep_table_parser_scripts.R")
on.exit({ rm(list = ls()); invisible(gc())})




#############
# I/O options
#############


# Options
option_list <- list(
  make_option(c("-i", "--input"), type="character", default=NULL,
              help="Input file path", metavar="character"),
  make_option(c("-o", "--output"), type="character", default=NULL,
              help="Output file path", metavar="character"),
  make_option(c("-v", "--verbose"), action="store_true", default=FALSE,
              help="Print verbose output")
)

# Arguments
opt_parser <- OptionParser(option_list=option_list)
opt <- parse_args(opt_parser)

# Check required arguments
if (is.null(opt$input) || is.null(opt$output)) {
  print_help(opt_parser)
  stop("Both --input and --output arguments are required")
}

# Use the arguments
input_file <- opt$input
output_file <- opt$output


################
# Read VEP table
################


# Read VEP table in blocks

variant_blocks <- read_vep_table_blocks(input_file)


# Process blocks sequentially (keeps mem requirement low)
for( vb in seq_along(variant_blocks) ) { process_vep_block( variant_blocks[[ vb ]] ) }


# release mem
invisible(gc())


# Filter and bind blocks
variant_groups <- bind_variant_blocks(variant_blocks)

# release mem
rm(variant_blocks); invisible(gc())


# Ensure order
setorder(variant_groups,"Pos","Ref_allele","Alt_allele","Gene")

# write output

fwrite(variant_groups,output_file,sep="\t",quote=FALSE,col.names=FALSE,na="NA")
