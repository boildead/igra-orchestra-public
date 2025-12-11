#!/bin/bash
# Viaduct entrypoint script
# Simple wrapper that starts viaduct with the provided arguments
# Note: Backup restoration is handled by start-unified-deployment.sh before services start

set -e

# Configuration
STORAGE_DIR="/app/storage"

# Function to log messages
log_message() {
    echo "▶ VIADUCT: $1" >&2
}

# Check if storage directory exists, create if not
if [[ ! -d "$STORAGE_DIR" ]]; then
    log_message "Creating storage directory..."
    mkdir -p "$STORAGE_DIR"
fi

# Check if storage is empty (backup might have been restored already)
if [[ -z "$(ls -A "$STORAGE_DIR" 2>/dev/null)" ]]; then
    log_message "Storage directory is empty - viaduct will sync from scratch"
    log_message "Note: If you expected a backup, ensure it was restored before starting viaduct"
else
    log_message "Storage directory contains data - starting with existing database"
fi

log_message "Starting viaduct daemon..."

# Start viaduct with original arguments
exec /app/viaduct "$@"

