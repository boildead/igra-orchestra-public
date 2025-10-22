#!/bin/bash
# Full deployment script with automatic sync orchestration
# Handles the complete deployment process automatically

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.full.yml"

# Function to log messages
log_message() {
    echo "▶ $1"
}

# Function to prompt for user input
prompt_user_input() {
    local prompt="$1"
    local var_name="$2"
    local default_value="$3"
    local is_password="$4"
    
    if [[ "$is_password" == "true" ]]; then
        echo -n "$prompt"
        if [[ -n "$default_value" ]]; then
            echo -n " (default: $default_value)"
        fi
        echo -n ": "
        read -s user_input
        echo
    else
        echo -n "$prompt"
        if [[ -n "$default_value" ]]; then
            echo -n " (default: $default_value)"
        fi
        echo -n ": "
        read user_input
    fi
    
    if [[ -z "$user_input" && -n "$default_value" ]]; then
        user_input="$default_value"
    fi
    
    eval "$var_name='$user_input'"
}

# Function to get interactive configuration
get_interactive_config() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   IGRA ORCHESTRA - AUTOMATIC SETUP"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Required configuration only
    prompt_user_input "Enter your domain name (e.g., my-node.example.com)" "DOMAIN" ""
    prompt_user_input "Enter your email for SSL certificates" "EMAIL" ""
    prompt_user_input "Enter your node ID (unique identifier for your node)" "NODE_ID" ""
    prompt_user_input "Enter your health check API key (get from IGRA Discord)" "HEALTH_API_KEY" ""
    
    echo ""
    
    # Primary wallet configuration only
    prompt_user_input "Enter wallet password (or press Enter for empty password)" "W0_PASSWORD" "" "true"
    
    # Set defaults for optional settings
    S3_BUCKET="igralabs-viaduct-archival-data"
    S3_REGION="eu-north-1"
    FORCE_RESTORE="false"
    W0_ADDRESS="auto"
    
    echo ""
}

# Function to generate RPC configuration
generate_rpc_config() {
    local rpc_file="$PROJECT_ROOT/.env.rpc"
    local env_file="$PROJECT_ROOT/.env"
    
    log_message "Generating configuration files..."
    
    # Generate 46 RPC tokens
    cat > "$rpc_file" << EOF
# IGRA Orchestra RPC Configuration
# Generated on $(date)
# 
# RPC Access Tokens - Use any of these tokens to access the RPC endpoint
# Example: https://your-domain.com:8545/{RPC_ACCESS_TOKEN_1}

EOF

    for i in $(seq 1 46); do
        token=$(openssl rand -hex 16)
        echo "RPC_ACCESS_TOKEN_$i=$token" >> "$rpc_file"
    done
    
    # Create .env file with user inputs
    log_message "Creating .env file with your configuration..."
    cat > "$env_file" << EOF
# IGRA Orchestra Configuration
# Generated on $(date)

# Network Configuration
NETWORK=testnet
NODE_ID=$NODE_ID

# Health Check Configuration
HEALTH_CHECK_API_KEY=$HEALTH_API_KEY

# Domain Configuration
IGRA_ORCHESTRA_DOMAIN=$DOMAIN
IGRA_ORCHESTRA_DOMAIN_EMAIL=$EMAIL

# Kaspad Configuration
KASPAD_HOST=kaspad
KASPAD_BORSH_PORT=17210

# Logging Configuration
RUST_LOG=info
REPLAY_ON_ERROR=false
SYNC_THREADS=4

# Execution Layer Configuration
L1_REFERENCE_TIMESTAMP=1700000000
L1_REFERENCE_DAA_SCORE=0
IGRA_CHAIN_ID=12345
EL_ONE_TIME_ADDRESS=0x0000000000000000000000000000000000000000
IGRA_LAUNCH_DAA_SCORE=0
GENESIS_BLOCK_HASH=0x0000000000000000000000000000000000000000000000000000000000000000
ENABLE_PERF_DIAGNOSTICS=false

# Optional Configuration
MAGIC_SPK=
DELAY_WINDOWS=

# RPC Configuration
RPC_READ_ONLY=false
MIN_PROTOCOL_FEE_PER_GAS_GWEI=1

# S3 Backup Configuration
S3_BACKUP_BUCKET=$S3_BUCKET
S3_BACKUP_REGION=$S3_REGION
FORCE_RESTORE_BACKUP=$FORCE_RESTORE

# Wallet Configuration
W0_WALLET_TO_ADDRESS=$W0_ADDRESS
W0_KASWALLET_PASSWORD=$W0_PASSWORD

EOF

    # Additional workers are disabled for automatic install
    # Only primary wallet (W0) is configured
    
    # Append RPC tokens to .env
    cat "$rpc_file" >> "$env_file"
    
    log_message "Configuration saved successfully ✅"
}

# Function to validate configuration
validate_configuration() {
    # Check required environment variables
    local missing_vars=()
    
    if [[ -z "$HEALTH_API_KEY" ]]; then
        missing_vars+=("HEALTH_CHECK_API_KEY")
    fi
    
    if [[ -z "$DOMAIN" ]]; then
        missing_vars+=("IGRA_ORCHESTRA_DOMAIN")
    fi
    
    if [[ -z "$EMAIL" ]]; then
        missing_vars+=("IGRA_ORCHESTRA_DOMAIN_EMAIL")
    fi
    
    if [[ -z "$NODE_ID" ]]; then
        missing_vars+=("NODE_ID")
    fi
    
    if [[ -z "$W0_PASSWORD" ]]; then
        missing_vars+=("W0_KASWALLET_PASSWORD")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_message "ERROR: Missing required configuration:"
        for var in "${missing_vars[@]}"; do
            case "$var" in
                "HEALTH_CHECK_API_KEY")
                    log_message "  - Health check API key is required"
                    ;;
                "IGRA_ORCHESTRA_DOMAIN")
                    log_message "  - Domain name is required"
                    ;;
                "IGRA_ORCHESTRA_DOMAIN_EMAIL")
                    log_message "  - Email for SSL certificates is required"
                    ;;
                "NODE_ID")
                    log_message "  - Node ID is required"
                    ;;
                "W0_KASWALLET_PASSWORD")
                    log_message "  - Wallet 0 password is required"
                    ;;
            esac
        done
        log_message ""
        log_message "Please run the script again and provide all required information"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_message "ERROR: Docker is not running or not accessible"
        exit 1
    fi
    
    # Check if docker-compose is available
    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        log_message "ERROR: docker-compose or docker compose is not available"
        exit 1
    fi
    
    # Check if openssl is available for token generation
    if ! command -v openssl >/dev/null 2>&1; then
        log_message "ERROR: openssl is not available (needed for RPC token generation)"
        exit 1
    fi
}

# Function to generate JWT secret if needed
setup_jwt_secret() {
    local jwt_file="$PROJECT_ROOT/keys/jwt.hex"
    
    if [[ ! -f "$jwt_file" ]]; then
        log_message "Generating JWT secret..."
        mkdir -p "$PROJECT_ROOT/keys"
        openssl rand -hex 32 > "$jwt_file"
        log_message "JWT secret created ✅"
    fi
}

# Function to setup execution layer script
setup_execution_layer() {
    local script_file="$PROJECT_ROOT/build/repos/execution-layer/run-igra-dev-el.sh"
    
    if [[ -f "$script_file" ]]; then
        chmod +x "$script_file"
    fi
}

# Function to start the full deployment
start_deployment() {
    log_message "Starting deployment..."
    
    # Change to project root directory
    cd "$PROJECT_ROOT"
    
    # Start the full deployment with sync orchestrator
    if docker compose version >/dev/null 2>&1; then
        # Use new docker compose command
        docker compose -f docker-compose.full.yml up -d kaspad kaswallet-0 traefik sync-orchestrator >/dev/null 2>&1
    else
        # Use legacy docker-compose command
        docker-compose -f docker-compose.full.yml up -d kaspad kaswallet-0 traefik sync-orchestrator >/dev/null 2>&1
    fi
    
    # Wait a moment for services to initialize
    sleep 2
    
    log_message "Services started successfully ✅"
}

# Function to get wallet address
get_wallet_address() {
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        local wallet_address=$(docker compose -f docker-compose.full.yml logs kaswallet-0 2>/dev/null | grep -oE "kaspatest:[a-zA-Z0-9]+" | head -1)
        if [[ -n "$wallet_address" ]]; then
            echo "$wallet_address"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    
    echo "Generating..."
    return 1
}

# Function to show final status with wallet address
show_final_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   ✅ DEPLOYMENT STARTED SUCCESSFULLY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Wait a moment for services to initialize
    sleep 3
    
    # Get wallet address
    log_message "Waiting for wallet generation..."
    local wallet_address=$(get_wallet_address)
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   📋 YOUR NODE INFORMATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🔑 Wallet Address:"
    echo "   $wallet_address"
    echo ""
    echo "🌐 RPC Endpoint:"
    local rpc_token=$(grep 'RPC_ACCESS_TOKEN_1=' .env 2>/dev/null | cut -d'=' -f2)
    if [[ -n "$rpc_token" ]]; then
        echo "   https://$DOMAIN:8545/$rpc_token"
    else
        echo "   Check .env file for RPC_ACCESS_TOKEN_1"
    fi
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   📊 WHAT'S HAPPENING NOW"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  1. ⏳ Kaspad is syncing (this takes 4-6 hours)"
    echo "  2. 🔄 Backend will start automatically after sync"
    echo "  3. ✅ RPC will be available once backend is ready"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   🔍 MONITORING"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Check status:"
    echo "  ./scripts/check-status.sh"
    echo ""
    echo "Monitor sync progress:"
    echo "  docker compose -f docker-compose.full.yml logs -f sync-orchestrator"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main execution
main() {
    # Check prerequisites
    check_prerequisites
    
    # Get interactive configuration
    get_interactive_config
    
    # Validate configuration
    validate_configuration
    
    # Generate RPC configuration
    generate_rpc_config
    
    # Setup required files
    setup_jwt_secret
    setup_execution_layer
    
    # Start deployment
    start_deployment
    
    # Show final status
    show_final_status
}

# Run main function
main "$@"
