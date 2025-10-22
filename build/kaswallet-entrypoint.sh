#!/bin/bash
# Kaswallet entrypoint script with automatic wallet generation
# Generates wallet with empty password if keys don't exist

set -e

# Configuration
WALLET_KEY_FILE="/app/keys.json"
NETWORK="${NETWORK:-testnet}"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] KASWALLET: $1"
}

# Function to extract wallet address from kaswallet-create output
extract_wallet_address() {
    local output="$1"
    # Look for address pattern like kaspatest:xxxxx
    echo "$output" | grep -oE "kaspatest:[a-zA-Z0-9]+" | head -1
}

# Function to save wallet address to shared volume for RPC provider
save_wallet_address() {
    local wallet_address="$1"
    local wallet_file="/shared/wallet_address_0.txt"
    
    if [[ -n "$wallet_address" ]]; then
        # Ensure shared directory exists
        mkdir -p /shared
        echo "$wallet_address" > "$wallet_file"
        log_message "Wallet address saved to shared volume: $wallet_address"
    fi
}

# Function to generate wallet if needed
generate_wallet_if_needed() {
    if [[ -f "$WALLET_KEY_FILE" ]]; then
        log_message "Wallet key file already exists: $WALLET_KEY_FILE"
        return 0
    fi
    
    log_message "Wallet key file not found, generating new wallet..."
    
    # Generate wallet with empty password
    local output
    output=$(echo -e "\n" | /app/kaswallet-create --"$NETWORK" -k "$WALLET_KEY_FILE" 2>&1 || {
        log_message "ERROR: Failed to generate wallet"
        return 1
    })
    
    # Extract wallet address from output
    local wallet_address
    wallet_address=$(extract_wallet_address "$output")
    
    if [[ -n "$wallet_address" ]]; then
        log_message "================================================"
        log_message "WALLET GENERATED SUCCESSFULLY"
        log_message "================================================"
        log_message "Wallet Address: $wallet_address"
        log_message "Key File: $WALLET_KEY_FILE"
        log_message "Password: (empty)"
        log_message "================================================"
        log_message "Wallet address automatically configured for RPC!"
        log_message "No manual configuration needed."
        log_message "================================================"
        
        # Save wallet address to shared volume for RPC provider
        save_wallet_address "$wallet_address"
    else
        log_message "WARNING: Could not extract wallet address from output"
        log_message "Wallet generation output: $output"
    fi
    
    return 0
}

# Function to verify wallet file
verify_wallet_file() {
    if [[ ! -f "$WALLET_KEY_FILE" ]]; then
        log_message "ERROR: Wallet key file not found after generation: $WALLET_KEY_FILE"
        return 1
    fi
    
    if [[ ! -s "$WALLET_KEY_FILE" ]]; then
        log_message "ERROR: Wallet key file is empty: $WALLET_KEY_FILE"
        return 1
    fi
    
    log_message "Wallet key file verified: $WALLET_KEY_FILE"
    return 0
}

# Main execution
main() {
    log_message "Starting kaswallet entrypoint..."
    
    # Generate wallet if needed
    if ! generate_wallet_if_needed; then
        log_message "ERROR: Failed to generate wallet, exiting"
        exit 1
    fi
    
    # Verify wallet file
    if ! verify_wallet_file; then
        log_message "ERROR: Wallet verification failed, exiting"
        exit 1
    fi
    
    log_message "Starting kaswallet daemon with args: $*"
    
    # Start kaswallet with original arguments
    exec /app/kaswallet "$@"
}

# Run main function
main "$@"

