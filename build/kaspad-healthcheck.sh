#!/bin/bash
# Kaspad sync status healthcheck script
# Queries kaspad WRPC JSON endpoint to check if node is fully synced

set -e

# Configuration
KASPAD_JSON_RPC_URL="http://localhost:18210"
TIMEOUT=10

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HEALTHCHECK: $1"
}

# Function to check if kaspad JSON RPC is responding
check_rpc_available() {
    local response
    response=$(curl -s --max-time $TIMEOUT "$KASPAD_JSON_RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"getInfo","params":[],"id":1}' 2>/dev/null || echo "ERROR")
    
    if [[ "$response" == "ERROR" ]]; then
        log_message "JSON RPC not responding"
        return 1
    fi
    
    # Check if response contains error
    if echo "$response" | grep -q '"error"'; then
        log_message "JSON RPC returned error: $response"
        return 1
    fi
    
    return 0
}

# Function to check sync status
check_sync_status() {
    local response
    response=$(curl -s --max-time $TIMEOUT "$KASPAD_JSON_RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"getInfo","params":[],"id":1}' 2>/dev/null || echo "ERROR")
    
    if [[ "$response" == "ERROR" ]]; then
        log_message "Failed to query getInfo"
        return 1
    fi
    
    # Extract isSynced field
    local is_synced
    is_synced=$(echo "$response" | grep -o '"isSynced":[^,}]*' | cut -d':' -f2 | tr -d ' "')
    
    if [[ "$is_synced" == "true" ]]; then
        log_message "Node is fully synced"
        return 0
    elif [[ "$is_synced" == "false" ]]; then
        log_message "Node is still syncing"
        return 1
    else
        # Fallback: try to get DAA score and compare with network
        log_message "isSynced field not found, checking DAA score"
        check_daa_score
    fi
}

# Function to check DAA score as fallback
check_daa_score() {
    local response
    response=$(curl -s --max-time $TIMEOUT "$KASPAD_JSON_RPC_URL" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"getBlockDagInfo","params":[],"id":1}' 2>/dev/null || echo "ERROR")
    
    if [[ "$response" == "ERROR" ]]; then
        log_message "Failed to query getBlockDagInfo"
        return 1
    fi
    
    # Extract virtualDaaScore
    local virtual_daa_score
    virtual_daa_score=$(echo "$response" | grep -o '"virtualDaaScore":[^,}]*' | cut -d':' -f2 | tr -d ' "')
    
    if [[ -n "$virtual_daa_score" && "$virtual_daa_score" -gt 0 ]]; then
        log_message "Virtual DAA Score: $virtual_daa_score (checking if synced...)"
        # For testnet, if we have a reasonable DAA score, consider it synced
        # This is a heuristic - in production you might want to check against known network tip
        if [[ "$virtual_daa_score" -gt 1000 ]]; then
            log_message "DAA score indicates node is likely synced"
            return 0
        else
            log_message "DAA score too low, still syncing"
            return 1
        fi
    else
        log_message "Could not determine DAA score"
        return 1
    fi
}

# Main execution
main() {
    log_message "Checking kaspad sync status..."
    
    # First check if RPC is available
    if ! check_rpc_available; then
        exit 1
    fi
    
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

