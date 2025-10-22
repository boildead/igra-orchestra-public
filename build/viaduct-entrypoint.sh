#!/bin/bash
# Viaduct entrypoint script with backup restoration capability
# Checks if backup restoration is needed and handles it before starting viaduct

set -e

# Configuration
STORAGE_DIR="/app/storage"
BACKUP_SCRIPT="/app/scripts/download-from-s3.sh"
S3_BACKUP_BUCKET="${S3_BACKUP_BUCKET:-igralabs-viaduct-archival-data}"
S3_BACKUP_REGION="${S3_BACKUP_REGION:-eu-north-1}"
NETWORK="${NETWORK:-testnet}"
CONTAINER_NAME="viaduct"

# Function to log messages
log_message() {
    echo "▶ VIADUCT: $1"
}

# Function to check if storage is empty or needs restoration
needs_backup_restore() {
    if [[ "$FORCE_RESTORE_BACKUP" == "true" ]]; then
        return 0
    fi
    
    if [[ ! -d "$STORAGE_DIR" ]] || [[ -z "$(ls -A "$STORAGE_DIR" 2>/dev/null)" ]]; then
        return 0
    fi
    
    return 1
}

# Function to download backup from S3
download_backup() {
    local backup_file="$1"
    local s3_url="https://${S3_BACKUP_BUCKET}.s3.${S3_BACKUP_REGION}.amazonaws.com/archival-data/igra-orchestra/${NETWORK}/${backup_file}"
    local temp_file="/tmp/${backup_file}"
    
    log_message "Downloading backup..."
    
    if curl -L -s -o "$temp_file" "$s3_url"; then
        echo "$temp_file"
    else
        log_message "ERROR: Download failed"
        return 1
    fi
}

# Function to list available backups
list_s3_backups() {
    local s3_url="https://${S3_BACKUP_BUCKET}.s3.${S3_BACKUP_REGION}.amazonaws.com/?prefix=archival-data/igra-orchestra/${NETWORK}/&list-type=2"
    
    # Download the S3 listing XML silently
    local xml_response
    xml_response=$(curl -s "$s3_url")
    
    # Parse XML to extract file names containing the container name
    echo "$xml_response" | grep -oE "<Key>[^<]*${CONTAINER_NAME}[^<]*</Key>" | \
        sed 's/<Key>//g' | sed 's/<\/Key>//g' | \
        grep -E "\.tar\.gz$" | \
        while read -r key; do
            basename "$key"
        done | sort -r
}

# Function to get the latest backup
get_latest_backup() {
    local backups
    backups=$(list_s3_backups)
    
    if [[ -z "$backups" ]]; then
        return 1
    fi
    
    # Get the first (most recent) backup
    echo "$backups" | head -1
}

# Function to restore backup
restore_backup() {
    local backup_file="$1"
    local temp_file="/tmp/${backup_file}"
    
    log_message "Restoring backup..."
    
    # Ensure storage directory exists
    mkdir -p "$STORAGE_DIR"
    
    # Extract backup to storage directory
    if tar -xzf "$temp_file" -C "$STORAGE_DIR" 2>/dev/null; then
        log_message "Backup restored successfully ✅"
        
        # Clean up temp file
        rm -f "$temp_file"
        return 0
    else
        log_message "ERROR: Backup restoration failed"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to handle backup restoration
handle_backup_restore() {
    # Get the latest backup
    local latest_backup
    latest_backup=$(get_latest_backup)
    if [[ $? -ne 0 ]]; then
        return 0
    fi
    
    # Download backup
    local temp_file
    temp_file=$(download_backup "$latest_backup")
    if [[ $? -ne 0 ]]; then
        return 0
    fi
    
    # Restore backup
    restore_backup "$latest_backup"
}

# Main execution
main() {
    # Check if backup restoration is needed
    if needs_backup_restore; then
        log_message "Checking for backup..."
        handle_backup_restore
    fi
    
    log_message "Viaduct ready ✅"
    log_message "Starting viaduct daemon..."
    
    # Start viaduct with original arguments
    exec /app/viaduct "$@"
}

# Run main function
main "$@"

