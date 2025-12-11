#!/bin/bash
# Kaswallet entrypoint script with automatic wallet generation
# Generates wallet with empty password if keys don't exist

set -e

# Configuration - support both /keys and /app/keys mount points
if [ -d "/keys" ]; then
    WALLET_KEY_DIR="/keys"
elif [ -d "/app/keys" ]; then
    WALLET_KEY_DIR="/app/keys"
else
    # Default to /keys if neither exists
    WALLET_KEY_DIR="/keys"
fi

WALLET_KEY_FILE="$WALLET_KEY_DIR/keys.json"
NETWORK="${NETWORK:-testnet}"

# Ensure keys directory exists
mkdir -p "$WALLET_KEY_DIR"

# Function to log messages
log_message() {
    echo "▶ WALLET: $1"
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
    fi
}

# Function to generate wallet if needed
generate_wallet_if_needed() {
    if [[ -f "$WALLET_KEY_FILE" ]]; then
        return 0
    fi
    
    log_message "Generating new wallet..."
    
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
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "   ✅ WALLET GENERATED"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Wallet Address: $wallet_address"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # Save wallet address to shared volume for RPC provider
        save_wallet_address "$wallet_address"
    fi
    
    return 0
}

# Function to verify wallet file
verify_wallet_file() {
    if [[ ! -f "$WALLET_KEY_FILE" ]]; then
        log_message "ERROR: Wallet key file not found"
        return 1
    fi
    
    if [[ ! -s "$WALLET_KEY_FILE" ]]; then
        log_message "ERROR: Wallet key file is empty"
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    # Generate wallet if needed
    if ! generate_wallet_if_needed; then
        log_message "ERROR: Failed to generate wallet"
        exit 1
    fi
    
    # Verify wallet file
    if ! verify_wallet_file; then
        log_message "ERROR: Wallet verification failed"
        exit 1
    fi
    
    log_message "Wallet ready ✅"
    log_message "Starting wallet daemon..."
    
    # Start kaswallet (daemon) with original arguments
    # The prebuilt image may have either 'kaswallet' or 'kaswallet-daemon'
    if [[ -f /app/kaswallet ]]; then
        exec /app/kaswallet "$@"
    elif [[ -f /app/kaswallet-daemon ]]; then
        exec /app/kaswallet-daemon "$@"
    else
        log_message "ERROR: kaswallet binary not found"
        exit 1
    fi
}

# Run main function
main "$@"

