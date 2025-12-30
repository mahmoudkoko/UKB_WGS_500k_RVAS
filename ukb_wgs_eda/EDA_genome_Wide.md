```bash
mapfile -t csq_list < <(ls scount/ | grep zst)

melt_scount() {

csq="$1"

zstdcat "scount/$csq"  |\
awk -F"\t" -v csq="${csq%.scount.zst}" 'NR>1{gsub("__","\t",csq);$1=csq"\t"$1; if($2 > 0) print $1,"HOM",$2; if($3 > 0) print $1,"HET",$3; if($4 > 0) print $1,"SIN",$4}' OFS="\t" |\
gzip > "scount/${csq%.scount.zst}.tsv.gz"

}


mapfile -t csq_list < <(ls CSQ/ | grep gz)

# collapse into 25 blocks
echo "0/5959" && for((b = 0; b < 24; ++b )); do
	b_start=$((b * 250))
	b_end=$(( (b+1) * 250))
	if [[ $b -eq 23 ]]; then b_end="5959"; fi

	
	for(( c = $b_start; c <  $b_end; ++c)); do 
		printf "\n$((c+1))/5959\r" >&2
		zcat CSQ/${csq_list[$c]};
	done |\
	awk -F"\t" '{id=$2":"$3":"$4":"$5":"$6":"$7;counts[id]+=$8;next}END{for(i in counts) print i":"counts[i]}' |\
	tr ':' ' ' |\
	gzip >> CSQ.blocks.txt.gz

done && echo "5959/5959" &






for(( c =0; c <  5959; ++c)); do

	echo "$((c+1))/5959" >&2

	zcat CSQ/${csq_list[$c]}

done | awk -F"\t" '{id=$2":"$3":"$4":"$5":"$6":"$7;counts[id]+=$8;next}END{for(i in counts) print i":"counts[i]}' | tr ':' ' ' | gzip > CSQ.txt.gz &






```

