#!/bin/bash

# ================================================================
# IGRA Orchestra S3 Streaming Restore Script
# ================================================================
# Downloads backup from S3 and restores directly to Docker volume
# No intermediate storage, no integrity checks (tar will fail if corrupted)
# ================================================================

set -euo pipefail

# ================================================================
# Configuration
# ================================================================

readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_INVALID_ARGS=1
readonly EXIT_FILE_NOT_FOUND=2
readonly EXIT_RESTORE_FAILED=3

# Arguments
CONTAINER_NAME=""
SPECIFIC_BACKUP=""
SKIP_CONFIRMATION=false

# ================================================================
# Helper Functions
# ================================================================

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS] CONTAINER_NAME [BACKUP_FILE]

Stream IGRA Orchestra backup directly from S3 to Docker volume.
No intermediate storage - downloads and extracts simultaneously.

ARGUMENTS:
    CONTAINER_NAME      Name of the container (required)
    BACKUP_FILE         Specific backup file to restore (optional, uses latest if not provided)

OPTIONS:
    --yes, -y          Skip confirmation prompt
    --help, -h         Show this help message

EXAMPLES:
    # Restore latest backup for viaduct
    $SCRIPT_NAME viaduct

    # Restore specific backup without confirmation
    $SCRIPT_NAME --yes viaduct igra-orchestra-testnet_viaduct_data_20250812_173649.tar.gz

ENVIRONMENT VARIABLES:
    S3_BACKUP_BUCKET        S3 bucket name (default: igralabs-viaduct-archival-data)
    S3_BACKUP_REGION        AWS region (default: eu-north-1)
    NETWORK                 Network identifier (default: testnet)
    FORCE_RESTORE_BACKUP    If "true", auto-confirms restore (default: false)
EOF
}

log_message() {
    echo "▶ $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo "▶ $(date '+%Y-%m-%d %H:%M:%S') - ERROR: $*" >&2
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --yes|-y)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --help|-h)
                show_usage
                exit $EXIT_SUCCESS
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit $EXIT_INVALID_ARGS
                ;;
            *)
                if [ -z "$CONTAINER_NAME" ]; then
                    CONTAINER_NAME="$1"
                else
                    SPECIFIC_BACKUP="$1"
                fi
                shift
                ;;
        esac
    done
}

# Load configuration from .env
load_configuration() {
    if [ -f "$SCRIPT_DIR/../../.env" ]; then
        log_message "Loading configuration from .env"
        while IFS='=' read -r key value; do
            if [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]]; then
                continue
            fi
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            case "$key" in
                S3_BACKUP_BUCKET|S3_BACKUP_REGION|NETWORK|FORCE_RESTORE_BACKUP)
                    export "$key=$value"
                    ;;
            esac
        done < "$SCRIPT_DIR/../../.env" 2>/dev/null || true
    fi
    
    # Set defaults
    S3_BACKUP_BUCKET="${S3_BACKUP_BUCKET:-igralabs-viaduct-archival-data}"
    S3_BACKUP_REGION="${S3_BACKUP_REGION:-eu-north-1}"
    NETWORK="${NETWORK:-testnet}"
    FORCE_RESTORE_BACKUP="${FORCE_RESTORE_BACKUP:-false}"
    
    # Auto-confirm if FORCE_RESTORE_BACKUP is true
    if [[ "$FORCE_RESTORE_BACKUP" == "true" ]]; then
        SKIP_CONFIRMATION=true
    fi
    
    S3_BASE_PATH="archival-data/igra-orchestra/${NETWORK}/"
    VOLUME_NAME="igra-orchestra-${NETWORK}-full_${CONTAINER_NAME}_data"
}

# List available backups from S3
list_s3_backups() {
    local s3_url="https://${S3_BACKUP_BUCKET}.s3.${S3_BACKUP_REGION}.amazonaws.com/?prefix=${S3_BASE_PATH}&list-type=2"
    
    local xml_response
    xml_response=$(curl -s "$s3_url")
    
    echo "$xml_response" | grep -oE "<Key>[^<]*${CONTAINER_NAME}[^<]*</Key>" | \
        sed 's/<Key>//g' | sed 's/<\/Key>//g' | \
        grep -E "\.tar\.gz$" | \
        while read -r key; do
            basename "$key"
        done | sort -r
}

# Get the latest backup file
get_latest_backup() {
    local backups
    backups=$(list_s3_backups)
    
    if [ -z "$backups" ]; then
        log_error "No backups found for container: $CONTAINER_NAME"
        exit $EXIT_FILE_NOT_FOUND
    fi
    
    echo "$backups" | head -1
}

# Check if container is running and stop it
stop_container_if_running() {
    log_message "[1/3] Checking container status..."
    
    if docker ps --filter "name=^${CONTAINER_NAME}$" --filter "status=running" --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_message "Stopping container: $CONTAINER_NAME"
        if ! docker stop "$CONTAINER_NAME" 2>/dev/null; then
            log_error "Failed to stop container: $CONTAINER_NAME"
            return 1
        fi
        log_message "Container stopped ✅"
    else
        log_message "Container not running ✅"
    fi
    
    return 0
}

# Stream backup from S3 directly to Docker volume
stream_restore() {
    local backup_file="$1"
    local s3_url="https://${S3_BACKUP_BUCKET}.s3.${S3_BACKUP_REGION}.amazonaws.com/${S3_BASE_PATH}${backup_file}"
    
    # Prepare volume
    log_message "[2/3] Preparing volume: $VOLUME_NAME"
    
    if ! docker volume inspect "$VOLUME_NAME" > /dev/null 2>&1; then
        if ! docker volume create "$VOLUME_NAME"; then
            log_error "Failed to create volume"
            return 1
        fi
    fi
    
    if ! docker run --rm -v "$VOLUME_NAME":/data alpine sh -c "rm -rf /data/* /data/.[!.]* 2>/dev/null || true" >/dev/null 2>&1; then
        log_error "Failed to clear volume"
        return 1
    fi
    log_message "Volume prepared ✅"
    
    # Verify S3 file
    log_message "[3/3] Verifying backup on S3..."
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" -I "$s3_url")
    
    if [ "$http_code" != "200" ]; then
        log_error "S3 file not accessible (HTTP $http_code)"
        [ "$http_code" = "403" ] && log_error "Access denied - bucket may not be public"
        [ "$http_code" = "404" ] && log_error "File not found: $backup_file"
        return 1
    fi
    
    # Get file size
    local file_size=$(curl -sI "$s3_url" | grep -i "content-length:" | awk '{print $2}' | tr -d '\r')
    if [ -n "$file_size" ]; then
        local size_mb=$((file_size / 1024 / 1024))
        log_message "Backup verified: ${size_mb} MB"
    else
        log_message "Backup verified ✅"
    fi
    
    # Stream and restore
    log_message "Streaming and extracting (typically 5-15 min for ~100GB)..."
    log_message "Progress: downloading ${size_mb}MB and extracting to volume..."
    
    local start_time=$(date +%s)
    
    # Create a simple progress indicator
    (
        while kill -0 $$ 2>/dev/null; do
            echo -n "."
            sleep 30
        done
    ) &
    local progress_pid=$!
    
    # Stream from S3 to Docker volume
    # Important: Don't redirect stderr to stdout as it corrupts the data stream
    local result=0
    if ! curl -f -L --silent --show-error "$s3_url" 2>/tmp/curl-error-$$.log | \
       docker run --rm -i -v "$VOLUME_NAME":/data alpine tar -xzf - -C /data 2>/tmp/tar-error-$$.log; then
        result=1
    fi
    
    # Stop progress indicator
    kill $progress_pid 2>/dev/null
    wait $progress_pid 2>/dev/null
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    echo ""
    
    if [ $result -eq 0 ]; then
        log_message "Restore completed in ${minutes}m ${seconds}s ✅"
        rm -f /tmp/curl-error-$$.log /tmp/tar-error-$$.log
        return 0
    else
        log_error "Restore failed after ${minutes}m ${seconds}s"
        
        # Show relevant errors
        if [ -s /tmp/curl-error-$$.log ]; then
            log_error "Curl errors:"
            cat /tmp/curl-error-$$.log >&2
        fi
        if [ -s /tmp/tar-error-$$.log ]; then
            log_error "Tar errors:"
            cat /tmp/tar-error-$$.log >&2
        fi
        
        rm -f /tmp/curl-error-$$.log /tmp/tar-error-$$.log
        return 1
    fi
}

# ================================================================
# Main Execution
# ================================================================

main() {
    # Parse arguments
    parse_arguments "$@"
    
    if [ -z "$CONTAINER_NAME" ]; then
        log_error "Container name is required"
        show_usage
        exit $EXIT_INVALID_ARGS
    fi
    
    # Load configuration
    load_configuration
    
    echo ""
    log_message "S3 Streaming Restore"
    log_message "Bucket: $S3_BACKUP_BUCKET | Region: $S3_BACKUP_REGION | Network: $NETWORK"
    echo ""
    
    # Check Docker
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running"
        exit $EXIT_INVALID_ARGS
    fi
    
    # Find backup to restore
    local backup_to_restore
    if [ -n "$SPECIFIC_BACKUP" ]; then
        backup_to_restore="$SPECIFIC_BACKUP"
    else
        log_message "Finding latest backup..."
        backup_to_restore=$(get_latest_backup)
        log_message "Latest: $backup_to_restore"
    fi
    echo ""
    
    # Confirmation prompt (unless skipped)
    if [ "$SKIP_CONFIRMATION" = false ]; then
        log_message "⚠️  WARNING: This will CLEAR volume '$VOLUME_NAME' and restore from backup"
        echo ""
        read -p "Continue? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_message "Cancelled"
            exit $EXIT_SUCCESS
        fi
        echo ""
    fi
    
    # Stop container if running
    if ! stop_container_if_running; then
        log_error "Failed to stop container"
        exit $EXIT_RESTORE_FAILED
    fi
    
    # Perform streaming restore
    if stream_restore "$backup_to_restore"; then
        echo ""
        log_message "✅ Restore completed successfully"
        log_message "Container: $CONTAINER_NAME | Volume: $VOLUME_NAME"
        echo ""
        exit $EXIT_SUCCESS
    else
        echo ""
        log_error "Restore failed. Check: internet connection, S3 access, disk space"
        exit $EXIT_RESTORE_FAILED
    fi
}

# Run main function
main "$@"

