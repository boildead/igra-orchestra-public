#!/bin/bash
# IGRA Orchestra Status Check Script
# Monitors deployment progress and displays current status

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.full.yml"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if a container is running
is_running() {
    local container="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"
}

# Function to check if a container is healthy
is_healthy() {
    local container="$1"
    local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    [[ "$health" == "healthy" ]]
}

# Function to get kaspad sync progress
get_kaspad_sync_status() {
    if ! is_running "kaspad"; then
        echo "Not started"
        return 1
    fi
    
    # Check if kaspad is synced using healthcheck
    if docker exec kaspad /app/kaspad-healthcheck.sh >/dev/null 2>&1; then
        echo "✅ Synced"
        return 0
    else
        # Try to get DAA score to show progress
        local response=$(docker exec kaspad curl -s http://localhost:18210 \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"getBlockDagInfo","params":[],"id":1}' 2>/dev/null || echo "")
        
        if [[ -n "$response" ]]; then
            local daa_score=$(echo "$response" | grep -o '"virtualDaaScore":[^,}]*' | cut -d':' -f2 | tr -d ' "' || echo "0")
            if [[ -n "$daa_score" && "$daa_score" -gt 0 ]]; then
                echo "⏳ Syncing (DAA: $daa_score)"
                return 1
            fi
        fi
        
        echo "⏳ Starting"
        return 1
    fi
}

# Function to get wallet address
get_wallet_address() {
    if ! is_running "kaswallet-0"; then
        echo "Wallet not started"
        return 1
    fi
    
    local wallet_address=$(docker logs kaswallet-0 2>/dev/null | grep -oE "kaspatest:[a-zA-Z0-9]+" | head -1)
    if [[ -n "$wallet_address" ]]; then
        echo "$wallet_address"
        return 0
    else
        echo "Generating..."
        return 1
    fi
}

# Function to get RPC endpoint
get_rpc_endpoint() {
    local env_file="$PROJECT_ROOT/.env"
    if [[ ! -f "$env_file" ]]; then
        echo "Not configured"
        return 1
    fi
    
    local domain=$(grep '^IGRA_ORCHESTRA_DOMAIN=' "$env_file" 2>/dev/null | cut -d'=' -f2)
    local token=$(grep '^RPC_ACCESS_TOKEN_1=' "$env_file" 2>/dev/null | cut -d'=' -f2)
    
    if [[ -n "$domain" && -n "$token" ]]; then
        echo "https://${domain}:8545/${token}"
        return 0
    else
        echo "Not configured"
        return 1
    fi
}

# Function to get service status icon
get_status_icon() {
    local container="$1"
    
    if ! is_running "$container"; then
        echo "⭕"
        return 1
    fi
    
    if is_healthy "$container"; then
        echo "✅"
        return 0
    fi
    
    # Check if container has health check
    local has_health=$(docker inspect --format='{{.State.Health}}' "$container" 2>/dev/null || echo "<nil>")
    if [[ "$has_health" == "<nil>" ]]; then
        # No health check, just check if running
        echo "✅"
        return 0
    fi
    
    echo "⏳"
    return 1
}

# Function to display header
display_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   IGRA ORCHESTRA - DEPLOYMENT STATUS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Function to display service status
display_service_status() {
    echo "📊 SERVICE STATUS:"
    echo ""
    
    # Core infrastructure
    echo "  Infrastructure:"
    printf "    Kaspad:          %s\n" "$(get_status_icon kaspad)"
    printf "    Traefik:         %s\n" "$(get_status_icon traefik)"
    printf "    Orchestrator:    %s\n" "$(get_status_icon sync-orchestrator)"
    
    echo ""
    echo "  Wallet:"
    printf "    Kaswallet-0:     %s\n" "$(get_status_icon kaswallet-0)"
    
    echo ""
    echo "  Backend Services:"
    printf "    Execution Layer: %s\n" "$(get_status_icon execution-layer)"
    printf "    Block Builder:   %s\n" "$(get_status_icon block-builder)"
    printf "    Viaduct:         %s\n" "$(get_status_icon viaduct)"
    
    echo ""
    echo "  RPC Services:"
    printf "    RPC Provider:    %s\n" "$(get_status_icon rpc-provider-0)"
    
    echo ""
}

# Function to display sync status
display_sync_status() {
    echo "⏱️  SYNC STATUS:"
    echo ""
    
    local kaspad_status=$(get_kaspad_sync_status)
    printf "  Kaspad: %s\n" "$kaspad_status"
    
    echo ""
}

# Function to display node information
display_node_info() {
    echo "📋 NODE INFORMATION:"
    echo ""
    
    # Wallet address
    local wallet_address=$(get_wallet_address)
    printf "  🔑 Wallet Address:\n     %s\n\n" "$wallet_address"
    
    # RPC endpoint
    local rpc_endpoint=$(get_rpc_endpoint)
    printf "  🌐 RPC Endpoint:\n     %s\n\n" "$rpc_endpoint"
}

# Function to display overall status
display_overall_status() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Determine overall status
    if is_running "rpc-provider-0" && is_healthy "rpc-provider-0"; then
        echo "  🎉 Status: FULLY OPERATIONAL"
        echo ""
        echo "  Your node is fully deployed and ready to use!"
    elif is_running "kaspad"; then
        local kaspad_synced=false
        docker exec kaspad /app/kaspad-healthcheck.sh >/dev/null 2>&1 && kaspad_synced=true
        
        if $kaspad_synced; then
            echo "  🔄 Status: DEPLOYING BACKEND"
            echo ""
            echo "  Kaspad is synced. Backend services starting..."
        else
            echo "  ⏳ Status: SYNCING"
            echo ""
            echo "  Kaspad is syncing. This takes 4-6 hours."
            echo "  Backend will start automatically after sync."
        fi
    else
        echo "  ⭕ Status: NOT STARTED"
        echo ""
        echo "  Run ./scripts/start-full-deployment.sh to begin"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Function to display monitoring commands
display_monitoring_commands() {
    echo "🔍 MONITORING COMMANDS:"
    echo ""
    echo "  View orchestrator logs:"
    echo "    docker compose -f docker-compose.full.yml logs -f sync-orchestrator"
    echo ""
    echo "  View kaspad logs:"
    echo "    docker compose -f docker-compose.full.yml logs -f kaspad"
    echo ""
    echo "  View all service status:"
    echo "    docker compose -f docker-compose.full.yml ps"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main execution
main() {
    cd "$PROJECT_ROOT"
    
    display_header
    display_service_status
    display_sync_status
    display_node_info
    display_overall_status
    display_monitoring_commands
    
    echo "✅ Status check complete"
    echo ""
}

# Run main function
main "$@"

