#!/bin/bash
# Generate RPC configuration script
# Creates environment variables for RPC access tokens

set -e

# Configuration
OUTPUT_FILE=".env.rpc"
TOKEN_COUNT=46

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RPC-CONFIG: $1"
}

# Function to generate RPC tokens
generate_rpc_tokens() {
    log_message "Generating $TOKEN_COUNT RPC access tokens..."
    
    # Create output file
    cat > "$OUTPUT_FILE" << EOF
# IGRA Orchestra RPC Configuration
# Generated on $(date)
# 
# RPC Access Tokens - Use any of these tokens to access the RPC endpoint
# Example: https://your-domain.com:8545/{RPC_ACCESS_TOKEN_1}

EOF

    # Generate tokens
    for i in $(seq 1 $TOKEN_COUNT); do
        token=$(openssl rand -hex 16)
        echo "RPC_ACCESS_TOKEN_$i=$token" >> "$OUTPUT_FILE"
    done
    
    log_message "Generated RPC configuration file: $OUTPUT_FILE"
}

# Function to display usage information
display_usage() {
    log_message "================================================"
    log_message "RPC CONFIGURATION GENERATED"
    log_message "================================================"
    log_message "Configuration file: $OUTPUT_FILE"
    log_message "RPC Endpoint format:"
    log_message "  https://your-domain.com:8545/{RPC_ACCESS_TOKEN}"
    log_message ""
    log_message "To use with docker-compose:"
    log_message "  cat $OUTPUT_FILE >> .env"
    log_message ""
    log_message "First few tokens:"
    head -n 10 "$OUTPUT_FILE" | grep "RPC_ACCESS_TOKEN" | head -3
    log_message "================================================"
}

# Main execution
main() {
    log_message "Starting RPC configuration generation..."
    
    # Generate tokens
    generate_rpc_tokens
    
    # Display usage information
    display_usage
    
    log_message "RPC configuration generation completed!"
}

# Run main function
main "$@"
