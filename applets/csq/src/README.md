```bash
burden_applet_id=$(dx build -f ./ -d "Applets/" --brief | jq -r .id)
```

```bash
dx mkdir "CSQ/"
```



```bash
for ((chr=1;chr<=22;++chr)); do

echo $chr $(dx run $burden_applet_id \
--destination "project-GzKk3XjJZz4ZgXzP2v1029qB:/CSQ" \
--instance-type mem1_ssd1_v2_x36 \
--name "CSQ ${chr}" \
--input vep_chr=${chr} \
--priority high \
--brief \
-y)

sleep 2

done
```



