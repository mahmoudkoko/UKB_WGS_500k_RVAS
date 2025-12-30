```bash
######
mapfile -t revel_transcripts < "revel_transcripts.txt"

# Set batch size
batch_size=400
total_transcripts=${#revel_transcripts[@]}

echo "Processing $total_transcripts transcripts in batches of $batch_size..."

# Initialize output file
> revel_transcripts_mapped.txt

# Process in batches
for ((g = 0; g < total_transcripts; g += batch_size)); do
    
    # Calculate start and end indices for this batch
    start_idx=$g
    end_idx=$batch_size
    
    # Adjust end_idx for the last batch if necessary
    if ((g + batch_size > total_transcripts)); then
        end_idx=$((total_transcripts - g))
    fi
    
    echo "Processing batch $((g/batch_size + 1)): transcripts $((start_idx + 1)) to $((start_idx + end_idx))"
    
    # Create XML query for this batch
    cat > revel_transcripts.xml << EOL
http://www.ensembl.org/biomart/martservice?query=<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE Query><Query virtualSchemaName="default" formatter="TSV" header="0" uniqueRows="0" count="" datasetConfigVersion="0.6"><Dataset name="hsapiens_gene_ensembl" interface="default"><Filter name="ensembl_transcript_id" value="$(printf "%s," "${revel_transcripts[@]:start_idx:end_idx}" | sed 's/,$//')"/><Attribute name="ensembl_gene_id"/><Attribute name="ensembl_transcript_id"/></Dataset></Query>
EOL

    # Remove newlines to create single-line URL
    tr -d '\n' < revel_transcripts.xml > revel_query.xml
    
    # Read the query URL
    mapfile -t revel_query < "revel_query.xml"
    
    # Submit the query with retry logic
    max_retries=3
    retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo "  Attempting query (try $((retry_count + 1))/$max_retries)..."
        
        if wget -O revel_genes.tmp "${revel_query[@]}" 2>/dev/null; then
            # Check if we got valid results (not an error page)
            if ! grep -q "<html>" revel_genes.tmp 2>/dev/null; then
                echo "  Batch completed successfully"
                cat revel_genes.tmp >> revel_transcripts_mapped.txt
                break
            else
                echo "  Got HTML error response, retrying..."
                ((retry_count++))
            fi
        else
            echo "  wget failed, retrying..."
            ((retry_count++))
        fi
        
        if [ $retry_count -lt $max_retries ]; then
            echo "  Waiting 2 seconds before retry..."
            sleep 2
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        echo "  ERROR: Failed to process batch after $max_retries attempts"
        echo "  Batch range: ${start_idx} to $((start_idx + end_idx - 1))" >> failed_batches.log
    fi
    
    # Small delay between batches to be nice to the server
    sleep 1
done



awk -F"\t" 'NR==FNR{++genes[$2];next}!($1 in genes)' revel_transcripts_mapped.txt revel_transcripts.txt > revel_transcripts_unmapped.txt



######
# remaining
mapfile -t revel_transcripts < "revel_transcripts_unmapped.txt"

# Set batch size
batch_size=400
total_transcripts=${#revel_transcripts[@]}

echo "Processing $total_transcripts transcripts in batches of $batch_size..."


# Process in batches
for ((g = 0; g < total_transcripts; g += batch_size)); do
    
    # Calculate start and end indices for this batch
    start_idx=$g
    end_idx=$batch_size
    
    # Adjust end_idx for the last batch if necessary
    if ((g + batch_size > total_transcripts)); then
        end_idx=$((total_transcripts - g))
    fi
    
    echo "Processing batch $((g/batch_size + 1)): transcripts $((start_idx + 1)) to $((start_idx + end_idx))"
    
    # Create XML query for this batch
    cat > revel_transcripts.xml << EOL
http://jan2020.archive.ensembl.org/biomart/martservice?query=<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE Query><Query virtualSchemaName="default" formatter="TSV" header="0" uniqueRows="0" count="" datasetConfigVersion="0.6"><Dataset name="hsapiens_gene_ensembl" interface="default"><Filter name="ensembl_transcript_id" value="$(printf "%s," "${revel_transcripts[@]:start_idx:end_idx}" | sed 's/,$//')"/><Attribute name="ensembl_gene_id"/><Attribute name="ensembl_transcript_id"/></Dataset></Query>
EOL

    # Remove newlines to create single-line URL
    tr -d '\n' < revel_transcripts.xml > revel_query.xml
    
    # Read the query URL
    mapfile -t revel_query < "revel_query.xml"
    
    # Submit the query with retry logic
    max_retries=3
    retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo "  Attempting query (try $((retry_count + 1))/$max_retries)..."
        
        if wget -O revel_genes.tmp "${revel_query[@]}" 2>/dev/null; then
            # Check if we got valid results (not an error page)
            if ! grep -q "<html>" revel_genes.tmp 2>/dev/null; then
                echo "  Batch completed successfully"
                cat revel_genes.tmp >> revel_transcripts_mapped.txt
                break
            else
                echo "  Got HTML error response, retrying..."
                ((retry_count++))
            fi
        else
            echo "  wget failed, retrying..."
            ((retry_count++))
        fi
        
        if [ $retry_count -lt $max_retries ]; then
            echo "  Waiting 2 seconds before retry..."
            sleep 2
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        echo "  ERROR: Failed to process batch after $max_retries attempts"
        echo "  Batch range: ${start_idx} to $((start_idx + end_idx - 1))" >> failed_batches.log
    fi
    
    # Small delay between batches to be nice to the server
    sleep 1
done

####

awk -F"\t" 'NR==FNR{++genes[$2];next}!($1 in genes)' revel_transcripts_mapped.txt revel_transcripts.txt > revel_transcripts_unmapped.txt

mapfile -t revel_transcripts < "revel_transcripts_unmapped.txt"

# Set batch size
batch_size=400
total_transcripts=${#revel_transcripts[@]}

echo "Processing $total_transcripts transcripts in batches of $batch_size..."


# Process in batches
for ((g = 0; g < total_transcripts; g += batch_size)); do
    
    # Calculate start and end indices for this batch
    start_idx=$g
    end_idx=$batch_size
    
    # Adjust end_idx for the last batch if necessary
    if ((g + batch_size > total_transcripts)); then
        end_idx=$((total_transcripts - g))
    fi
    
    echo "Processing batch $((g/batch_size + 1)): transcripts $((start_idx + 1)) to $((start_idx + end_idx))"
    
    # Create XML query for this batch
    cat > revel_transcripts.xml << EOL
http://may2015.archive.ensembl.org/biomart/martservice?query=<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE Query><Query virtualSchemaName="default" formatter="TSV" header="0" uniqueRows="0" count="" datasetConfigVersion="0.6"><Dataset name="hsapiens_gene_ensembl" interface="default"><Filter name="ensembl_transcript_id" value="$(printf "%s," "${revel_transcripts[@]:start_idx:end_idx}" | sed 's/,$//')"/><Attribute name="ensembl_gene_id"/><Attribute name="ensembl_transcript_id"/></Dataset></Query>
EOL

    # Remove newlines to create single-line URL
    tr -d '\n' < revel_transcripts.xml > revel_query.xml
    
    # Read the query URL
    mapfile -t revel_query < "revel_query.xml"
    
    # Submit the query with retry logic
    max_retries=3
    retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo "  Attempting query (try $((retry_count + 1))/$max_retries)..."
        
        if wget -O revel_genes.tmp "${revel_query[@]}" 2>/dev/null; then
            # Check if we got valid results (not an error page)
            if ! grep -q "<html>" revel_genes.tmp 2>/dev/null; then
                echo "  Batch completed successfully"
                cat revel_genes.tmp >> revel_transcripts_mapped.txt
                break
            else
                echo "  Got HTML error response, retrying..."
                ((retry_count++))
            fi
        else
            echo "  wget failed, retrying..."
            ((retry_count++))
        fi
        
        if [ $retry_count -lt $max_retries ]; then
            echo "  Waiting 2 seconds before retry..."
            sleep 2
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        echo "  ERROR: Failed to process batch after $max_retries attempts"
        echo "  Batch range: ${start_idx} to $((start_idx + end_idx - 1))" >> failed_batches.log
    fi
    
    # Small delay between batches to be nice to the server
    sleep 1
done

####

awk -F"\t" 'NR==FNR{++genes[$2];next}!($1 in genes)' revel_transcripts_mapped.txt revel_transcripts.txt > revel_transcripts_unmapped.txt

wc -l revel_transcripts_unmapped.txt

# 13210 unmapped

####

mapfile -t revel_transcripts < "revel_transcripts_unmapped.txt"

# Set batch size
batch_size=400
total_transcripts=${#revel_transcripts[@]}

echo "Processing $total_transcripts transcripts in batches of $batch_size..."


# Process in batches
for ((g = 0; g < total_transcripts; g += batch_size)); do
    
    # Calculate start and end indices for this batch
    start_idx=$g
    end_idx=$batch_size
    
    # Adjust end_idx for the last batch if necessary
    if ((g + batch_size > total_transcripts)); then
        end_idx=$((total_transcripts - g))
    fi
    
    echo "Processing batch $((g/batch_size + 1)): transcripts $((start_idx + 1)) to $((start_idx + end_idx))"
    
    # Create XML query for this batch
    cat > revel_transcripts.xml << EOL
http://grch37.ensembl.org/biomart/martservice?query=<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE Query><Query virtualSchemaName="default" formatter="TSV" header="0" uniqueRows="0" count="" datasetConfigVersion="0.6"><Dataset name="hsapiens_gene_ensembl" interface="default"><Filter name="ensembl_transcript_id" value="$(printf "%s," "${revel_transcripts[@]:start_idx:end_idx}" | sed 's/,$//')"/><Attribute name="ensembl_gene_id"/><Attribute name="ensembl_transcript_id"/></Dataset></Query>
EOL

    # Remove newlines to create single-line URL
    tr -d '\n' < revel_transcripts.xml > revel_query.xml
    
    # Read the query URL
    mapfile -t revel_query < "revel_query.xml"
    
    # Submit the query with retry logic
    max_retries=3
    retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo "  Attempting query (try $((retry_count + 1))/$max_retries)..."
        
        if wget -O revel_genes.tmp "${revel_query[@]}" 2>/dev/null; then
            # Check if we got valid results (not an error page)
            if ! grep -q "<html>" revel_genes.tmp 2>/dev/null; then
                echo "  Batch completed successfully"
                cat revel_genes.tmp >> revel_transcripts_mapped.txt
                break
            else
                echo "  Got HTML error response, retrying..."
                ((retry_count++))
            fi
        else
            echo "  wget failed, retrying..."
            ((retry_count++))
        fi
        
        if [ $retry_count -lt $max_retries ]; then
            echo "  Waiting 2 seconds before retry..."
            sleep 2
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        echo "  ERROR: Failed to process batch after $max_retries attempts"
        echo "  Batch range: ${start_idx} to $((start_idx + end_idx - 1))" >> failed_batches.log
    fi
    
    # Small delay between batches to be nice to the server
    sleep 1
done

####

awk -F"\t" 'NR==FNR{++genes[$2];next}!($1 in genes)' revel_transcripts_mapped.txt revel_transcripts.txt > revel_transcripts_unmapped.txt

wc -l revel_transcripts_unmapped.txt

# 6742 unmapped

#####



mapfile -t am_transcripts < "am_transcripts.txt"
#IFS=$'\n' read -d '' -r -a am_transcripts < "am_transcripts.txt"

# Set batch size
batch_size=400
total_transcripts=${#am_transcripts[@]}

echo "Processing $total_transcripts transcripts in batches of $batch_size..."

# Initialize output file
> am_genes_mapped.txt

# Process in batches
for ((g = 0; g < total_transcripts; g += batch_size)); do
    
    # Calculate start and end indices for this batch
    start_idx=$g
    end_idx=$batch_size
    
    # Adjust end_idx for the last batch if necessary
    if ((g + batch_size > total_transcripts)); then
        end_idx=$((total_transcripts - g))
    fi
    
    echo "Processing batch $((g/batch_size + 1)): transcripts $((start_idx + 1)) to $((start_idx + end_idx))"
    
    # Create XML query for this batch
    cat > am_transcripts.xml << EOL
http://www.ensembl.org/biomart/martservice?query=<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE Query><Query virtualSchemaName="default" formatter="TSV" header="0" uniqueRows="0" count="" datasetConfigVersion="0.6"><Dataset name="hsapiens_gene_ensembl" interface="default"><Filter name="ensembl_transcript_id" value="$(printf "%s," "${am_transcripts[@]:start_idx:end_idx}" | sed 's/,$//')"/><Attribute name="ensembl_gene_id"/><Attribute name="ensembl_transcript_id"/></Dataset></Query>
EOL

    # Remove newlines to create single-line URL
    tr -d '\n' < am_transcripts.xml > am_query.xml
    
    # Read the query URL
    mapfile -t am_query < "am_query.xml"
    #IFS=$'\n' read -d '' -r -a am_query < "am_query.xml"

    # Submit the query with retry logic
    max_retries=3
    retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo "  Attempting query (try $((retry_count + 1))/$max_retries)..."
        
        if wget -O am_genes.tmp "${am_query[@]}" 2>/dev/null; then
            # Check if we got valid results (not an error page)
            if ! grep -q "<html>" am_genes.tmp 2>/dev/null; then
                echo "  Batch completed successfully"
                cat am_genes.tmp >> am_genes_mapped.txt
                break
            else
                echo "  Got HTML error response, retrying..."
                ((retry_count++))
            fi
        else
            echo "  wget failed, retrying..."
            ((retry_count++))
        fi
        
        if [ $retry_count -lt $max_retries ]; then
            echo "  Waiting 2 seconds before retry..."
            sleep 2
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        echo "  ERROR: Failed to process batch after $max_retries attempts"
        echo "  Batch range: ${start_idx} to $((start_idx + end_idx - 1))" >> failed_batches.log
    fi
    
    # Small delay between batches to be nice to the server
    sleep 1
done

rm am_genes.tmp am_query.xml am_transcripts.xml


awk -F"\t" 'NR==FNR{++genes[$2];next}!($1 in genes)' am_genes_mapped.txt am_transcripts.txt > am_transcripts_unmapped.txt

mv am_genes_mapped.txt am_genes_mapped.tsv


###########



mapfile -t am_transcripts < "am_transcripts_unmapped.txt"

# Set batch size
batch_size=400
total_transcripts=${#am_transcripts[@]}

echo "Processing $total_transcripts transcripts in batches of $batch_size..."

# Initialize output file
> am_genes_mapped.txt

# Process in batches
for ((g = 0; g < total_transcripts; g += batch_size)); do
    
    # Calculate start and end indices for this batch
    start_idx=$g
    end_idx=$batch_size
    
    # Adjust end_idx for the last batch if necessary
    if ((g + batch_size > total_transcripts)); then
        end_idx=$((total_transcripts - g))
    fi
    
    echo "Processing batch $((g/batch_size + 1)): transcripts $((start_idx + 1)) to $((start_idx + end_idx))"
    
    # Create XML query for this batch
    cat > am_transcripts.xml << EOL
http://jan2020.archive.ensembl.org/biomart/martservice?query=<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE Query><Query virtualSchemaName="default" formatter="TSV" header="0" uniqueRows="0" count="" datasetConfigVersion="0.6"><Dataset name="hsapiens_gene_ensembl" interface="default"><Filter name="ensembl_transcript_id" value="$(printf "%s," "${am_transcripts[@]:start_idx:end_idx}" | sed 's/,$//')"/><Attribute name="ensembl_gene_id"/><Attribute name="ensembl_transcript_id"/></Dataset></Query>
EOL


    # Remove newlines to create single-line URL
    tr -d '\n' < am_transcripts.xml > am_query.xml
    
    # Read the query URL
    mapfile -t am_query < "am_query.xml"
    #IFS=$'\n' read -d '' -r -a am_query < "am_query.xml"

    # Submit the query with retry logic
    max_retries=3
    retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo "  Attempting query (try $((retry_count + 1))/$max_retries)..."
        
        if wget -O am_genes.tmp "${am_query[@]}" 2>/dev/null; then
            # Check if we got valid results (not an error page)
            if ! grep -q "<html>" am_genes.tmp 2>/dev/null; then
                echo "  Batch completed successfully"
                cat am_genes.tmp >> am_genes_mapped.txt
                break
            else
                echo "  Got HTML error response, retrying..."
                ((retry_count++))
            fi
        else
            echo "  wget failed, retrying..."
            ((retry_count++))
        fi
        
        if [ $retry_count -lt $max_retries ]; then
            echo "  Waiting 2 seconds before retry..."
            sleep 2
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        echo "  ERROR: Failed to process batch after $max_retries attempts"
        echo "  Batch range: ${start_idx} to $((start_idx + end_idx - 1))" >> failed_batches.log
    fi
    
    # Small delay between batches to be nice to the server
    sleep 1
done

rm am_genes.tmp am_query.xml am_transcripts.xml



awk -F"\t" 'NR==FNR{++genes[$2];next}!($1 in genes)' am_genes_mapped.txt am_transcripts_unmapped.txt > am_transcripts_unmapped2.txt

cat am_genes_mapped.txt >> am_genes_mapped.tsv

######



mapfile -t am_transcripts < "am_transcripts_unmapped2.txt"

# Set batch size
batch_size=400
total_transcripts=${#am_transcripts[@]}

echo "Processing $total_transcripts transcripts in batches of $batch_size..."

# Initialize output file
> am_genes_mapped.txt

# Process in batches
for ((g = 0; g < total_transcripts; g += batch_size)); do
    
    # Calculate start and end indices for this batch
    start_idx=$g
    end_idx=$batch_size
    
    # Adjust end_idx for the last batch if necessary
    if ((g + batch_size > total_transcripts)); then
        end_idx=$((total_transcripts - g))
    fi
    
    echo "Processing batch $((g/batch_size + 1)): transcripts $((start_idx + 1)) to $((start_idx + end_idx))"
    
    # Create XML query for this batch
    cat > am_transcripts.xml << EOL
http://may2015.archive.ensembl.org/biomart/martservice?query=<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE Query><Query virtualSchemaName="default" formatter="TSV" header="0" uniqueRows="0" count="" datasetConfigVersion="0.6"><Dataset name="hsapiens_gene_ensembl" interface="default"><Filter name="ensembl_transcript_id" value="$(printf "%s," "${am_transcripts[@]:start_idx:end_idx}" | sed 's/,$//')"/><Attribute name="ensembl_gene_id"/><Attribute name="ensembl_transcript_id"/></Dataset></Query>
EOL


    # Remove newlines to create single-line URL
    tr -d '\n' < am_transcripts.xml > am_query.xml
    
    # Read the query URL
    mapfile -t am_query < "am_query.xml"
    #IFS=$'\n' read -d '' -r -a am_query < "am_query.xml"

    # Submit the query with retry logic
    max_retries=3
    retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo "  Attempting query (try $((retry_count + 1))/$max_retries)..."
        
        if wget -O am_genes.tmp "${am_query[@]}" 2>/dev/null; then
            # Check if we got valid results (not an error page)
            if ! grep -q "<html>" am_genes.tmp 2>/dev/null; then
                echo "  Batch completed successfully"
                cat am_genes.tmp >> am_genes_mapped.txt
                break
            else
                echo "  Got HTML error response, retrying..."
                ((retry_count++))
            fi
        else
            echo "  wget failed, retrying..."
            ((retry_count++))
        fi
        
        if [ $retry_count -lt $max_retries ]; then
            echo "  Waiting 2 seconds before retry..."
            sleep 2
        fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
        echo "  ERROR: Failed to process batch after $max_retries attempts"
        echo "  Batch range: ${start_idx} to $((start_idx + end_idx - 1))" >> failed_batches.log
    fi
    
    # Small delay between batches to be nice to the server
    sleep 1
done

rm am_genes.tmp am_query.xml am_transcripts.xml



awk -F"\t" 'NR==FNR{++genes[$2];next}!($1 in genes)' am_genes_mapped.txt am_transcripts_unmapped2.txt > am_transcripts_unmapped3.txt


```