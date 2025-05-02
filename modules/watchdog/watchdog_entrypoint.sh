#!/bin/bash

# Infinite loop
while true
do
  for dir in /kubepanel/yaml_templates/*/; do
    [ -d "$dir" ] || continue
    echo "$(date): Iterating over directories in $dir"
    sleep 5

    if [ "$dir" = "/kubepanel/yaml_templates/fwrules/" ]; then
      echo "→ Patching modsecurity-snippet from all YAMLs in fwrules/"
      kubectl patch configmap nginx-load-balancer-microk8s-conf -n ingress --type merge --patch "$(cat "${dir}"*.yaml)"
    else
      echo "→ Applying all manifests in $dir"
      kubectl apply -f "$dir"
    fi

    rm -rf "$dir"
  done

    python3 /kubepanel/manage.py check_status
    # Sleep for 5 seconds between cycles
    sleep 5
done

