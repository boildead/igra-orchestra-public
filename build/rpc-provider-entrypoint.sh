#!/bin/bash
# RPC Provider entrypoint script with automatic wallet address configuration
# Reads wallet address from shared volume and generates RPC tokens if needed

set -e

# Configuration
SHARED_VOLUME="/shared"
WALLET_ADDRESS_FILE="$SHARED_VOLUME/wallet_address_0.txt"
RPC_TOKENS_FILE="$SHARED_VOLUME/rpc_tokens.txt"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RPC-PROVIDER: $1"
}

# Function to generate RPC access tokens
generate_rpc_tokens() {
    local tokens_file="$1"
    
    log_message "Generating RPC access tokens..."
    
    # Generate 46 tokens
    for i in {1..46}; do
        token=$(openssl rand -hex 16)
        echo "RPC_ACCESS_TOKEN_$i=$token" >> "$tokens_file"
    done
    
    log_message "Generated 46 RPC access tokens"
}

# Function to read wallet address from shared volume
read_wallet_address() {
    local max_attempts=60  # Wait up to 5 minutes (5 seconds * 60)
    local attempt=0
    
    log_message "Waiting for wallet address to be generated..."
    
    while [[ $attempt -lt $max_attempts ]]; do
        if [[ -f "$WALLET_ADDRESS_FILE" ]]; then
            local wallet_address
            wallet_address=$(cat "$WALLET_ADDRESS_FILE" 2>/dev/null || echo "")
            
            if [[ -n "$wallet_address" ]]; then
                log_message "Found wallet address: $wallet_address"
                echo "$wallet_address"
                return 0
            fi
        fi
        
        log_message "Waiting for wallet address... (attempt $((attempt + 1))/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    log_message "WARNING: Could not read wallet address after $max_attempts attempts"
    return 1
}

# Function to setup RPC configuration
setup_rpc_configuration() {
    log_message "Setting up RPC configuration..."
    
    # Ensure shared directory exists
    mkdir -p "$SHARED_VOLUME"
    
    # Generate RPC tokens if not exists
    if [[ ! -f "$RPC_TOKENS_FILE" ]]; then
        generate_rpc_tokens "$RPC_TOKENS_FILE"
    else
        log_message "RPC tokens already exist, using existing tokens"
    fi
    
    # Read wallet address
    local wallet_address
    wallet_address=$(read_wallet_address)
    
    if [[ -n "$wallet_address" ]]; then
        # Export wallet address for the RPC provider
        export WALLET_TO_ADDRESS="$wallet_address"
        export KASWALLET_PASSWORD=""
        
        log_message "================================================"
        log_message "RPC PROVIDER CONFIGURED AUTOMATICALLY"
        log_message "================================================"
        log_message "Wallet Address: $wallet_address"
        log_message "RPC Tokens: Generated automatically"
        log_message "================================================"
        log_message "RPC endpoint will be available at:"
        log_message "https://your-domain.com:8545/{RPC_ACCESS_TOKEN_1}"
        log_message "================================================"
        
        return 0
    else
        log_message "ERROR: Failed to configure wallet address"
        return 1
    fi
}

# Main execution
main() {
    log_message "Starting RPC provider entrypoint..."
    
    # Setup RPC configuration
    if ! setup_rpc_configuration; then
        log_message "ERROR: Failed to setup RPC configuration"
        exit 1
    fi
    
    log_message "Starting RPC provider daemon with args: $*"
    
    # Start RPC provider with original arguments
    exec /app/igra-rpc-provider "$@"
}

# Run main function
main "$@"
