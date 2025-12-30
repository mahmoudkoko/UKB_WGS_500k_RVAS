


### Build

```bash
regenie_applet2_id=$(dx build -f ./ -d "Applets/" --brief | jq -r .id)
```



### Test

```bash
for ((N=1;N<=22;++N)); do

regenie_job_ids+=( $(dx run ${regenie_applet2_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}" \
--input chr=${N} \
--name "Regenie test submission: chr${N}" \
--priority high \
--brief \
-y) )

sleep 1

done

N=1
dx run ${regenie_applet_id} \
--instance-type mem1_ssd1_v2_x72 \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}" \
--input chr=${N} \
--name "Regenie test submission: chr${N}" \
--priority high \
--brief \
-y


```