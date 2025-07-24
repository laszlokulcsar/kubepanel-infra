#!/usr/bin/env bash
# File: /usr/local/bin/watchdog.sh
# Watchdog sidecar: restore thin-LVM snapshots based on uploads
# Iterates over /kubepanel/watchdog/uploads/<domain>/<job>/READY
# READY file contains the PV name (e.g. pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
# For each job, finds linstor-satellite pods holding the LV, and runs thin_recv

set -euo pipefail

# Configuration
UPLOAD_ROOT=/kubepanel/watchdog/uploads
WORK_ROOT=/kubepanel/watchdog/work
DONE_ROOT=/kubepanel/watchdog/done
FAILED_ROOT=/kubepanel/watchdog/failed
NAMESPACE=piraeus-datastore
INTERVAL=${WATCHDOG_INTERVAL:-5}

# Ensure directories exist
mkdir -p "$UPLOAD_ROOT" "$WORK_ROOT" "$DONE_ROOT" "$FAILED_ROOT"

echo "[$(date)] [watchdog] Starting restore loop (interval ${INTERVAL}s)"
while true; do
  # Loop domains
  for domain_dir in "$UPLOAD_ROOT"/*; do
    [ -d "$domain_dir" ] || continue
    domain=$(basename "$domain_dir")

    # Loop jobs under domain
    for job_dir in "$domain_dir"/*; do
      [ -d "$job_dir" ] || continue
      ready_file="$job_dir/READY"
      [ -f "$ready_file" ] || continue
      PV_NAME=$(<"$ready_file")
      job=$(basename "$job_dir")
      echo "[$(date)] [watchdog] Found job '$job' for domain '$domain'"

      # Move job to working area
      mkdir -p "$WORK_ROOT/$domain"
      mv "$job_dir" "$WORK_ROOT/$domain/"
      wd="$WORK_ROOT/$domain/$job"

      # Locate LV snapshot file
      LV_FILE=$(find "$wd" -maxdepth 1 -type f -name '*.lv.zst' | head -n1)
      if [[ -z "$LV_FILE" ]]; then
        echo "[$(date)] [watchdog] ERROR: no .lv.zst file in $wd" >&2
        mkdir -p "$FAILED_ROOT/$domain"
        mv "$wd" "$FAILED_ROOT/$domain/"
        continue
      fi

      # Read PV name from READY
      echo "[$(date)] [watchdog] PV to restore: $PV_NAME"

      # Find all linstor-satellite pods
      pods=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=linstor-satellite -o name)
      if [[ -z "$pods" ]]; then
        echo "[$(date)] [watchdog] ERROR: no linstor-satellite pods found" >&2
        mv "$wd" "$FAILED_ROOT/$domain/"
        continue
      fi

      success=true
      # Iterate pods and restore
      for pod in $pods; do
        # strip 'pod/' prefix
        pod_name=${pod#pod/}
        # find matching LV name (exclude snapshots)
        LV_NAME=$(kubectl exec -n "$NAMESPACE" "$pod_name" -- \
          sh -c "lvs --noheadings -o lv_name linstorvg | grep '$PV_NAME' | grep -v snapshot | xargs")
        if [[ -n "$LV_NAME" ]]; then
          echo "[$(date)] [watchdog] Restoring to pod $pod_name, LV: $LV_NAME"
          # Stream compressed file into container and decompress there
          if ! kubectl exec -i -n "$NAMESPACE" "$pod_name" -- \
              sh -c "zstd -d | thin_recv linstorvg/'$LV_NAME'" < "$LV_FILE"; then
            echo "[$(date)] [watchdog] ERROR: restore to $pod_name failed" >&2
            success=false
          fi
        else
          echo "ERROR"
          echo $LV_NAME
          echo $pod_name
          echo $PV_NAME
        fi
      done

      # Finalize job
      if $success; then
        echo "[$(date)] [watchdog] Job '$job' completed successfully"
        rm -rf "$wd"
      else
        echo "[$(date)] [watchdog] Job '$job' failed" >&2
        mkdir -p "$FAILED_ROOT/$domain"
        mv "$wd" "$FAILED_ROOT/$domain/"
      fi
    done
  done

  sleep "$INTERVAL"
done

