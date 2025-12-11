#!/bin/bash
# Kaspad sync status healthcheck script
# Checks kaspad sync status (orchestrator uses logs, healthcheck uses RPC)

set -e

# Configuration

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHCHECK: $1"
}


# Function to check sync status
check_sync_status() {
    log_message "Checking kaspad logs for sync completion..."
    
    # Check the kaspad log file for "IBD: ... blocks (100%)" or "Accepted ... blocks ... via relay" messages
    local log_file="/app/data/kaspad.log"
    
    if [[ -f "$log_file" ]]; then
        log_message "Found kaspad log file: $log_file"
        if tail -n 2000 "$log_file" 2>/dev/null | grep -E -q "(IBD:.* blocks \(100%\)|Accepted .* blocks .* via relay)"; then
            log_message "Node is fully synced (found sync message in logs)"
            return 0
        else
            log_message "Node is still syncing (no sync message found in recent logs)"
            return 1
        fi
    else
        log_message "Kaspad log file not found: $log_file"
        return 1
    fi
}


# Main execution
main() {
    log_message "Checking kaspad sync status..."
    
    # Check sync status
    if check_sync_status; then
        log_message "Healthcheck passed - node is synced"
        exit 0
    else
        log_message "Healthcheck failed - node not synced"
        exit 1
    fi
}

# Run main function
main "$@"

