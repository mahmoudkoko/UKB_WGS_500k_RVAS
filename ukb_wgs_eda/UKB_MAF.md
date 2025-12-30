

```bash

dx run \
--priority high \
--instance-type mem1_ssd1_v2_x16 \
--ssh app-cloud_workstation
```


Relatedness


```bash
mkdir kin

dx download "$DX_PROJECT_CONTEXT_ID:/Bulk/Genotype Results/Genotype calls/ukb_rel.dat" -o kin/

dx download "$DX_PROJECT_CONTEXT_ID:/Bulk/Genotype Results/Genotype calls/ukb_sqc_v2.txt" -o kin/

```


```r
ukb_rel <- fread('kin/ukb_rel.dat')

ukb_rel[,ID3:=fifelse(ID1 > ID2,ID1,ID2,ID2)]

ukb_samples <- unique(c(ukb_rel$ID1,ukb_rel$ID2))

#147,432

unrelated_samples <- relatedness_greedy_filtering(ukb_samples,ukb_rel)

fwrite(unrelated_samples$Filter,"kin/max_unrel_filter.txt",quote=FALSE)

```


```bash



main() {

	local N="$1"


mkdir plink aaf bgen


# All EUR 455,617

dx cat "$DX_PROJECT_CONTEXT_ID:/Phenotypes/ukb_phenotypes_copied_from_wh3_files.txt" |\
cut -f1,2 -d' ' > plink/All_EUR.txt

# Max Unrel EUR 383,256

dx download "$DX_PROJECT_CONTEXT_ID:/Phenotypes/Max_Unrel_EUR.txt" -o plink/Max_Unrel_EUR.txt

# download psam
dx download "$DX_PROJECT_CONTEXT_ID:Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c22_b0_v1.psam" -o plink/UKB_WGS.psam

# fix psam file
sed -i "s/ $/ OK/" plink/UKB_WGS.psam



# Download pgen
dx download "$DX_PROJECT_CONTEXT_ID:Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${N}_b0_v1.pgen" -o plink/chr${N}.pgen

# download pvar
dx download "$DX_PROJECT_CONTEXT_ID:Bulk/DRAGEN WGS/DRAGEN population level WGS variants, PLINK format [500k release]/ukb24308_c${N}_b0_v1.pvar" -o plink/chr${N}.pvar



# High quality vars

awk '$7 == "PASS"{print $3}' plink/chr${N}.pvar > plink/chr${N}.vars.txt


# AC in Max Unrel EUR

plink2 \
--psam plink/UKB_WGS.psam \
--keep plink/Max_Unrel_EUR.txt \
--pfile plink/chr${N} \
--extract plink/chr${N}.vars.txt \
--geno-counts 'zs' \
--out aaf/chr${N} \
--threads 15 \
--memory 28000


# allele frequencies

zstdcat aaf/chr${N}.gcount.zst |\
awk 'NR>1{ac=$6+$7+$7;an=2*($5+$6+$7);maf=ac/an; if(maf <= 0.0001) print $2}' > aaf/chr${N}.rare_vars.txt



# filter the file and convert to bgen: 452,842 samples

plink2 \
--export bgen-1.2 'bits=8' \
--psam plink/UKB_WGS.psam \
--keep plink/All_EUR.txt \
--extract aaf/chr${N}.rare_vars.txt \
--pfile plink/chr${N} \
--out bgen/chr${N} \
--threads 15 \
--memory 28000


# index bgen file




# upload

dx upload --no-progress --recursive -p bgen


# comit upload


}


```