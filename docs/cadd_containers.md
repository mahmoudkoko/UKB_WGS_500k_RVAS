
## Singularity 






```bash

```

If not doing anything else, end session


```bash
dx terminate $DX_JOB_ID
```




wrapper main script (e.g., applet)


add validation script


modify validation to indel script to filter indels and strip chr prefix

add download all inputs

add script to stage cadd

add line read all input files from a given folder using find

add line to remove all inputs once done


docker bind IO directory as /opt/cadd/io
docker bind tmp directory as /tmp
docker bind annotations, containers, prescored as /opt/cadd/data/*


parralel use all files in IO as input to cadd and run nproc




