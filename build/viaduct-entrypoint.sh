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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] VIADUCT: $1"
}

# Function to check if storage is empty or needs restoration
needs_backup_restore() {
    if [[ "$FORCE_RESTORE_BACKUP" == "true" ]]; then
        log_message "Force restore backup requested"
        return 0
    fi
    
    if [[ ! -d "$STORAGE_DIR" ]] || [[ -z "$(ls -A "$STORAGE_DIR" 2>/dev/null)" ]]; then
        log_message "Storage directory is empty, backup restoration needed"
        return 0
    fi
    
    log_message "Storage directory has data, skipping backup restoration"
    return 1
}

# Function to download backup from S3
download_backup() {
    local backup_file="$1"
    local s3_url="https://${S3_BACKUP_BUCKET}.s3.${S3_BACKUP_REGION}.amazonaws.com/archival-data/igra-orchestra/${NETWORK}/${backup_file}"
    local temp_file="/tmp/${backup_file}"
    
    log_message "Downloading backup from S3: $s3_url"
    
    if curl -L --progress-bar -o "$temp_file" "$s3_url"; then
        log_message "Download completed: $temp_file"
        echo "$temp_file"
    else
        log_message "ERROR: Download failed"
        return 1
    fi
}

# Function to list available backups
list_s3_backups() {
    local s3_url="https://${S3_BACKUP_BUCKET}.s3.${S3_BACKUP_REGION}.amazonaws.com/?prefix=archival-data/igra-orchestra/${NETWORK}/&list-type=2"
    
    log_message "Listing available backups..."
    
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
        log_message "ERROR: No backups found for container: $CONTAINER_NAME"
        return 1
    fi
    
    # Get the first (most recent) backup
    echo "$backups" | head -1
}

# Function to restore backup
restore_backup() {
    local backup_file="$1"
    local temp_file="/tmp/${backup_file}"
    
    log_message "Restoring backup: $backup_file"
    
    # Ensure storage directory exists
    mkdir -p "$STORAGE_DIR"
    
    # Extract backup to storage directory
    if tar -xzf "$temp_file" -C "$STORAGE_DIR"; then
        log_message "Backup restoration completed successfully"
        
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
    log_message "Starting backup restoration process..."
    
    # Get the latest backup
    local latest_backup
    latest_backup=$(get_latest_backup)
    if [[ $? -ne 0 ]]; then
        log_message "WARNING: Could not find latest backup, continuing without restoration"
        return 0
    fi
    
    log_message "Latest backup found: $latest_backup"
    
    # Download backup
    local temp_file
    temp_file=$(download_backup "$latest_backup")
    if [[ $? -ne 0 ]]; then
        log_message "WARNING: Backup download failed, continuing without restoration"
        return 0
    fi
    
    # Restore backup
    if restore_backup "$latest_backup"; then
        log_message "Backup restoration completed successfully"
    else
        log_message "WARNING: Backup restoration failed, continuing without restoration"
    fi
}

# Main execution
main() {
    log_message "Starting viaduct entrypoint..."
    
    # Check if backup restoration is needed
    if needs_backup_restore; then
        handle_backup_restore
    fi
    
    log_message "Starting viaduct daemon with args: $*"
    
    # Start viaduct with original arguments
    exec /app/viaduct "$@"
}

# Run main function
main "$@"

