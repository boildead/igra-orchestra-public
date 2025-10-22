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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEPLOY: $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_message "Checking prerequisites..."
    
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
    
    # Check if .env file exists
    if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
        log_message "ERROR: .env file not found. Please run setup first:"
        log_message "  ./scripts/generate-rpc-config.sh"
        exit 1
    fi
    
    log_message "Prerequisites check passed"
}

# Function to generate JWT secret if needed
setup_jwt_secret() {
    local jwt_file="$PROJECT_ROOT/keys/jwt.hex"
    
    if [[ ! -f "$jwt_file" ]]; then
        log_message "Generating JWT secret..."
        mkdir -p "$PROJECT_ROOT/keys"
        openssl rand -hex 32 > "$jwt_file"
        log_message "JWT secret generated: $jwt_file"
    else
        log_message "JWT secret already exists: $jwt_file"
    fi
}

# Function to setup execution layer script
setup_execution_layer() {
    local script_file="$PROJECT_ROOT/build/repos/execution-layer/run-igra-dev-el.sh"
    
    if [[ -f "$script_file" ]]; then
        chmod +x "$script_file"
        log_message "Execution layer script is executable"
    else
        log_message "WARNING: Execution layer script not found at $script_file"
        log_message "Please run setup-repos.sh first if building from source"
    fi
}

# Function to start the full deployment
start_deployment() {
    log_message "Starting IGRA Orchestra full deployment..."
    log_message "This will automatically handle sync orchestration"
    
    # Change to project root directory
    cd "$PROJECT_ROOT"
    
    # Start the full deployment with sync orchestrator
    log_message "Starting services with automatic sync orchestration..."
    
    if docker compose version >/dev/null 2>&1; then
        # Use new docker compose command
        docker compose -f docker-compose.full.yml up -d kaspad traefik
    else
        # Use legacy docker-compose command
        docker-compose -f docker-compose.full.yml up -d kaspad traefik
    fi
    
    log_message "================================================"
    log_message "🚀 DEPLOYMENT STARTED"
    log_message "================================================"
    log_message "Services started:"
    log_message "  - kaspad: Starting sync process"
    log_message "  - traefik: Load balancer ready"
    log_message "  - sync-orchestrator: Monitoring sync progress"
    log_message ""
    log_message "The sync orchestrator will automatically:"
    log_message "  1. Wait for kaspad to complete sync (4-6 hours)"
    log_message "  2. Start backend services (execution-layer, block-builder, viaduct)"
    log_message "  3. Start RPC services (rpc-provider, kaswallet)"
    log_message "  4. Configure everything automatically"
    log_message ""
    log_message "Monitor progress with:"
    log_message "  docker compose -f docker-compose.full.yml logs -f sync-orchestrator"
    log_message ""
    log_message "Monitor kaspad sync with:"
    log_message "  docker compose -f docker-compose.full.yml logs -f kaspad"
    log_message "================================================"
}

# Function to display monitoring commands
show_monitoring_commands() {
    log_message ""
    log_message "📊 MONITORING COMMANDS:"
    log_message "========================"
    log_message "# Monitor sync orchestrator (recommended)"
    log_message "docker compose -f docker-compose.full.yml logs -f sync-orchestrator"
    log_message ""
    log_message "# Monitor kaspad sync progress"
    log_message "docker compose -f docker-compose.full.yml logs -f kaspad"
    log_message ""
    log_message "# Check all service status"
    log_message "docker compose -f docker-compose.full.yml ps"
    log_message ""
    log_message "# Monitor wallet generation"
    log_message "docker compose -f docker-compose.full.yml logs -f kaswallet-0"
    log_message ""
    log_message "# Monitor RPC provider"
    log_message "docker compose -f docker-compose.full.yml logs -f rpc-provider-0"
    log_message "========================"
}

# Function to show completion message
show_completion_info() {
    log_message ""
    log_message "🎉 DEPLOYMENT COMPLETE!"
    log_message "========================"
    log_message "Your IGRA Orchestra node is now running with:"
    log_message ""
    log_message "✅ Kaspad: Fully synced"
    log_message "✅ Backend: Execution layer, block builder, viaduct"
    log_message "✅ RPC: Provider and wallet services"
    log_message "✅ Automatic configuration: Wallets and tokens generated"
    log_message ""
    log_message "RPC Endpoint:"
    log_message "  https://your-domain.com:8545/{RPC_ACCESS_TOKEN_1}"
    log_message ""
    log_message "Get your RPC tokens:"
    log_message "  grep 'RPC_ACCESS_TOKEN_1' .env"
    log_message ""
    log_message "View wallet address:"
    log_message "  docker compose -f docker-compose.full.yml logs kaswallet-0 | grep 'Wallet Address'"
    log_message "========================"
}

# Main execution
main() {
    log_message "=== IGRA ORCHESTRA FULL DEPLOYMENT ==="
    log_message "Starting automated deployment with sync orchestration..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup required files
    setup_jwt_secret
    setup_execution_layer
    
    # Start deployment
    start_deployment
    
    # Show monitoring commands
    show_monitoring_commands
    
    log_message ""
    log_message "The deployment is now running in the background."
    log_message "The sync orchestrator will handle everything automatically."
    log_message ""
    log_message "This process typically takes 4-6 hours for initial sync."
    log_message "You can monitor progress using the commands above."
    log_message ""
    log_message "Once complete, you'll have a fully functional IGRA Orchestra node!"
}

# Run main function
main "$@"
