


### Build

```bash
regenie_applet_id=$(dx build -f ./ -d "Applets/" --brief | jq -r .id)
```



### Test

```bash
for ((N=2;N<=17;++N)); do

regenie_job_ids+=( $(dx run ${regenie_applet_id} \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}" \
--input chr=${N} \
--name "Regenie test submission: chr${N}" \
--priority high \
--brief \
-y) )

sleep 1

done

N=3
dx run ${regenie_applet_id} \
--instance-type mem1_ssd1_v2_x72 \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/WGS/chr${N}" \
--input chr=${N} \
--name "Regenie test submission: chr${N}" \
--priority high \
--brief \
-y


```