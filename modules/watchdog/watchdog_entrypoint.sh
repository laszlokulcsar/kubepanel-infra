#!/bin/bash

# Infinite loop
while true
do
    echo "Iterating over directories in /kubepanel/yaml_templates/..."

    # Iterate over directories under /kubepanel/yaml_templates/
    for dir in /kubepanel/yaml_templates/*/ ; do
        if [ -d "$dir" ]; then
            echo "Applying YAMLs in $dir..."
            sleep 5
            # Apply YAML files in the current directory
            kubectl apply -f "$dir"
            rm -rf "$dir"
        fi
    done
    python3 /kubepanel/manage.py check_status
    # Sleep for 5 seconds between cycles
    sleep 5
done

