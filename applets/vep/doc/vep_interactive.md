# Testing interactively



Start an interactive session for one hour and 8 cores.


```bash
dx run \
--priority high \
--destination "/Scratch/vep_tests/" \
--instance-type mem1_ssd1_v2_x8 \
--ssh app-cloud_workstation
```


Once running, install the required dependencies and create an input list. 




```bash
# dependencies
sudo apt install tabix bcftools parallel
```


## Input list

Prepare a text file containing a few (sites-only) compressed VCFs.

The file name needs to start with ukb and should contain the chromosome that you intend to annotate (i.e.  `ukbxxx_c${vep_chr}_`). 


Assuming you have create VCF chunks of 50k variants [as shown here](resources/usr/doc/vep_input.md), you can select the first 5 files and upload them as your input list.

If using your own file, e.g., copy the file ID from the platform or use the path to find the file ID

From the file path

```bash
vep_test_list_path="/where/the/file/is/uploaded/ukb0000_c21_test_vcf_list.txt"
```

Get the file ID


```bash
vep_test_list_fid=$(dx describe "${DX_PROJECT_CONTEXT_ID}:${vep_test_list_path}" \
--json \
--multi |\
jq -r .[0].id)
```




Here, we are reading the full list of input sites-only VCF files from `/WGS/chr21/logs/ukb24308_c21_all_vep_input_file_ids.txt`, selecting the first 5, and uploading it back.

Depending on where the lists were saved, the path in this example may vary.


```bash
vep_test_list_fid=$(dx cat "${DX_PROJECT_CONTEXT_ID}:/WGS/chr21/logs/ukb24308_c21_all_vep_input_file_ids.txt" |\
head -n5 |\
dx upload - \
--path "${DX_PROJECT_CONTEXT_ID}:/Scratch/vep_tests/logs/ukb24308_c21_test_vep_input_file_ids.txt" \
-p \
--no-progress \
--brief)
```


## Input parameters (JSON)

Add the input list and other inputs to the input JSON file of your workstation to simulate the inputs used by the applet. 


```bash
sed -e 's/^{/{"vep_buffer": 50000,/1' \
    -e 's/^{/{"vep_timeout": 1000,/1' \
    -e 's/^{/{"vep_forks": 1,/1' \
	-e 's/^{/{"vep_chr": 21,/1' \
	-e "s/^{/{\"vep_vcfs\": {\"\$dnanexus_link\": \"${vep_test_list_fid}\"},/1" \
	-e 's/^{/{"vep_ver": 114,/1' \
	-i job_input.json
```

## Applet scripts


Next, download the scripts of the applet and move them to the expected location to simulate the runtime environment


```bash
# Download and source the scripts
git clone https://github.com/mahmoudkoko/UKB_WGS_VEP.git
# Move them to where they would be if using an applet
sudo mv UKB_WGS_VEP/resources/usr/scripts /usr/scripts
```

Now follow the code in the main entry point.


## Main entry point explained


The applet stats by sourcing the pre-bundled scripts


```bash
source /usr/scripts/export_global_vars.sh
source /usr/scripts/check_ongoing_applet_runs.sh
source /usr/scripts/utilities.sh
source /usr/scripts/validate_input.sh
source /usr/scripts/stage_vep.sh
source /usr/scripts/process_vep_vcf_block.sh
source /usr/scripts/annotate_vep.sh
```


The first few lines of the main entry point initiate some variables and then test the required apps


```bash
tabix_=$(which tabix || echo "not found")
bgzip_=$(which bgzip || echo "not found")
bcftools_=$(which bcftools || echo "not found")
parallel_=$(which parallel || echo "not found")

# dependencies

if [[ $tabix_ =~ "not found" || $bgzip_ =~ "not found" || $bcftools_ =~ "not found" || $parallel_ =~ "not found"  ]]; then 
	echo "ERROR";
    #return 1
fi

```

This initiates local variables


```bash
vep_log_dx_id=""
vep_out_dx_ids=()

vep_input_files=()
vep_valid_files=()
```


The next lines export variables and functions and create a runtime directory.


```bash
# global vars
export_global_vars
```


```bash
# functions
export -f validate_input_vcf_files;
export -f process_vep_vcf_block;
export -f annotate_vep;
export -f log_message;
```


```bash
# runtime dir
mkdir -p "$RUNTIME_DIR/VEP" "$RUNTIME_DIR/LOG"
```


The applet then checks for ongoing runs with similar input VCF list.


```bash
check_ongoing_applet_runs
```


This will fail when testing interactively because we are using a workstation.


Next, the entry point calls `dx cat` to read the input lines into an array and makes sure the file is not empty.

```bash
mapfile -t vep_input_files < <(dx cat "${DX_PROJECT_CONTEXT_ID}:${VCF_LIST_HASH}") 
```


```bash
if [[ ${#vep_input_files[@]} -eq 0 ]]; then 
	
    log_message "No files" # this is added here to replace the return
    #return 1

else

   log_message "INFO: Proceeding to validate ${#vep_input_files[@]} input files ..."

fi
```


The second code block runs a function which validates the input lines

```bash
parallel \
        --jobs "$N_JOBS" \
        --results "${RUNTIME_DIR}/LOG" \
        --joblog "${RUNTIME_DIR}/LOG/${VAL_LOG}" \
        --timeout 200 \
        validate_input_vcf_files ::: "${vep_input_files[@]}"
```

Afterwards, it collects the results

```bash
if ! [[ -f "${RUNTIME_DIR}/LOG/${VAL_LOG}" ]]; then

    log_message "ERROR: Could not find validation log"
    #return 1


elif ! mapfile -t vep_valid_files < <(get_validation_results); then

    log_message "ERROR: Failed to get a list of validated file IDs - exiting"
    #return 1

elif [[ ${#vep_valid_files[@]} -eq 0 || ${vep_valid_files[0]} == "NA" ]]; then
    
    log_message "INFO: No valid files to process - terminating applet"
    #return 0

else

    log_message "INFO: Proceeding with ${#vep_valid_files[@]} valid files ..."

fi
```


The third block loads VEP.

It downloads the cache files and runs a quick test on a dummy VCF. 

If running OK, it initiates a monitor to follow the number of processed files and traps a cleanup function.

```bash
if ! stage_vep; then

	log_message "ERROR: Failed to load VEP - exiting"

    #return 1


else

    log_message "INFO: Starting a progress monitor"

    progress_monitor_fx "${#vep_valid_files[@]}" &
    
    #trap cleanup_and_exit EXIT

fi
```



The final block runs the annotation jobs.

This should take ~3-10 min.

Here, we will send it to the background with `&`.

```bash
parallel \
    --jobs "$N_JOBS" \
    --results "${RUNTIME_DIR}/LOG" \
    --joblog "${RUNTIME_DIR}/LOG/${PAR_LOG}" \
    --timeout "${VEP_TIMEOUT}" \
    process_vep_vcf_block ::: "${vep_valid_files[@]}" &
```

Meanwhile you could monitor the cores and mem usage with `htop` to have a sense of how intense it is.


Once done, the main scripts moves to collecting the results



```bash
if ! [[ -f "${RUNTIME_DIR}/LOG/${PAR_LOG}" ]] ; then

    log_message "ERROR: Parallel vep_annotate runs failed - exiting"

    #return 1


elif ! create_session_log; then

    log_message "ERROR: Failed to create session log - exiting"

    #return 1

else

    log_message "INFO: Finished running VEP"

    #return 0

fi
```

Once done, the `trap cleanup_and_exit EXIT` triggers a cleanup process to remove the runtime directory created at the beginning.

```bash
cleanup_and_exit
```

By now the applet exits.


When testing interactiven, VEP output files can be explored here:

```bash
dx ls vep/
```

The list of outputs can be found here


```bash
dx ls logs/
```

The log file can be explored using 

```bash
dx cat logs/${DX_JOB_ID}.vep.log
```

If not using the workstation for something else, terminate


```bash
dx terminate $DX_JOB_ID
```