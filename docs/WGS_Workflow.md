# WGS Workflow





Submit with 40GB RAM (applet requires 8-14 per file; 40 for 4 files). It should take ~4hrs to finish and will cost ~£3.5 on high priority (to avoid interuptions).

```bash
dx run ${my_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:Scratch" \
--instance-type mem1_ssd1_v2_x36 \
--input ukb23374_vcf_list="${my_test_file_2_of_3}" \
--name "WGS QC: chr21 - test 2/3" \
--priority high \
--brief
```





There are 151,561 VCF files. The average size of GraphTyper VCFs is 10GB. The QC applet needs ~8-14GB RAM, 2-4 cores, and ~ 3.5hrs runtime to process a 10GB VCf file (files range between 10-20GB).

The output in this case is ~??MB (plink files: , sites bcf: , sample stats: variant scores:).


```bash
chr1 12448
chr2 12110
chr3 9915
chr4 9511
chr5 9077
chr6 8541
chr7 7968
chr8 7257
chr9 6920
chr10 6690
chr11 6755
chr12 6664
chr13 5719
chr14 5353
chr15 5100
chr16 4517
chr17 4163
chr18 4019
chr19 2931
chr20 3223
chr21 2336
chr22 2541
chrX 7803
```

When running *low priority* jobs, the pricing is based on cores not memory so you can process a substantially higher number of VCFs in parallel at a lower cost by using high memory instances (mem3) compared to mem1 or mem2.

Instance | RAM GB | Cost per hour (spot) | Total per 3.5hrs run | VCFs (RAM/14)| Cost per file (assuming 3.5hr run) | Total cost
---|---|---|---
mem1_ssd1_v2_x36 | 72 | £0.2628 | £0.9198 | 5 | £0.184 |  £28,000
mem1_ssd1_v2_x72 | 144 | £0.5256 | £1.8396 | 10 | £0.184 | £28,000
mem2_ssd1_v2_x32 | 128 | £0.2336 | £0.8176 | 9 | £0.0908 | £14,000
mem2_ssd1_v2_x64 | 256 | £0.4672 | £1.6352 | 18 | £0.0908 | £14,000
mem3_ssd1_v2_x48 | 384 | £0.3504 | | £1.2264 | 27 | £0.0454 | £7,000
mem3_ssd1_v2_x96 | 768 | £0.7008 | £2.4528 | 54 | £0.0454 | £7,000



Estimates from Whole Exome Analysis: 

977 files * 20 GB each on mem2_x64 = £578
It terms of size, this is equivalent to ~ 2,000(/150,000) WGS files (1.3%).
Projected cost for WGS is therefore 578x150000/2000 ~= 


## Processing chromosome 21




Create batches of 50 files

Each file requires 
Now proceed to testing larger files. This time we will use the WGS vcfs path to select files 1001-1005 (~10 GB each)



Once you have confirmed this runs without errors, continue to test 50 files on low priority. This time use a larger instance (x72; 144 GB RAM) on low priority to allow faster scheduling and 10 parallel VCF runs (~20 hrs to finish & £10 total cost).



```bash
my_test_file_2_of_3=$( (seq 1 5 |\
    xargs -I{} echo "Bulk/GATK and GraphTyper WGS/GraphTyper population level WGS variants, pVCF format [500k release]/chr21/ukb23374_c21_b100{}_v1.vcf.gz" )|\
    dx upload - --parents --path "/Scratch/batches/vcf_list_test_2_of_3.txt" --brief)
```


```bash
dx run ${my_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:Scratch" \
--instance-type mem1_ssd1_v2_x72 \
--input ukb23374_vcf_list="${my_test_file_3_of_3}" \
--name "WGS QC: chr21 - test 3/3" \
--priority low \
--brief
```



