#!/bin/bash
# Unified deployment script with automatic sync orchestration and RPC setup
# Handles the complete deployment process automatically with all features

set -e
set -o pipefail

# Error handler
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo ""; echo "▶ ERROR: Command failed with exit code $? at line $LINENO: $last_command"; echo ""' ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")" && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.full.yml"

# Global variable to store main repo branch for restoration
MAIN_REPO_BRANCH=""

# Function to restore main repository branch (called on exit)
restore_main_repo_branch() {
    # Use MAIN_REPO_DIR if set, otherwise try PROJECT_ROOT
    local restore_project_root="${MAIN_REPO_DIR:-$PROJECT_ROOT}"
    if [[ -z "$restore_project_root" ]]; then
        # Last resort: calculate from script location
        local script_path="${BASH_SOURCE[0]}"
        if [[ -n "$script_path" ]]; then
            restore_project_root="$(cd "$(dirname "$(dirname "$script_path")")" && pwd)" 2>/dev/null || return
        else
            return
        fi
    fi
    
    if [[ -n "$MAIN_REPO_BRANCH" ]] && [[ -n "$restore_project_root" ]] && git -C "$restore_project_root" rev-parse --git-dir >/dev/null 2>&1; then
        local current_branch=$(git -C "$restore_project_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [[ -z "$current_branch" ]] || [[ "$current_branch" == "HEAD" ]]; then
            current_branch=$(git -C "$restore_project_root" rev-parse HEAD 2>/dev/null || echo "")
        fi
        
        if [[ -n "$MAIN_REPO_BRANCH" ]] && [[ "$current_branch" != "$MAIN_REPO_BRANCH" ]]; then
            echo "" >&2
            echo "▶ Main repository branch changed from '$MAIN_REPO_BRANCH' to '$current_branch'" >&2
            echo "▶ Restoring main repository branch to: $MAIN_REPO_BRANCH" >&2
            if git -C "$restore_project_root" checkout "$MAIN_REPO_BRANCH" >/dev/null 2>&1; then
                echo "▶ ✅ Main repository restored to: $MAIN_REPO_BRANCH" >&2
            else
                echo "▶ ⚠️  WARNING: Failed to restore main repository branch" >&2
                echo "▶   Attempted: git checkout $MAIN_REPO_BRANCH in $restore_project_root" >&2
            fi
        fi
    fi
}

# Set trap to restore branch on exit (including errors)
# This MUST be set after PROJECT_ROOT is defined
trap restore_main_repo_branch EXIT

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
    
    # Safely set the variable using printf to avoid code injection
    printf -v "$var_name" '%s' "$user_input"
}

# Function to check if configuration exists
check_existing_config() {
    local env_file="$PROJECT_ROOT/.env"
    
    if [[ -f "$env_file" ]]; then
        log_message "Found existing configuration: $env_file"
        
        # Safely load existing values from .env file
        # Parse each line and export variables safely
        while IFS= read -r line; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
            # Skip lines without = sign
            [[ ! "$line" =~ = ]] && continue
            
            # Split on first = only (value may contain =)
            IFS='=' read -r key value <<< "$line"
            
            # Remove leading/trailing whitespace from key
            key=$(echo "$key" | xargs)
            
            # Only export if key is valid identifier
            if [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] && [[ -n "$value" ]]; then
                # Remove quotes if present
                value=$(echo "$value" | sed -e "s/^['\"]//" -e "s/['\"]$//")
                # Export safely using printf
                printf -v "$key" '%s' "$value"
                export "$key"
            fi
        done < "$env_file"
        
        echo ""
        echo "Current configuration:"
        echo "  Domain: ${IGRA_ORCHESTRA_DOMAIN}"
        echo "  Email: ${IGRA_ORCHESTRA_DOMAIN_EMAIL}"
        echo "  Node ID: ${NODE_ID}"
        echo "  RPC Read-Only: ${RPC_READ_ONLY}"
        echo "  Workers: ${NUM_WORKERS:-1}"
        echo ""
        
        # Ask if user wants to continue or reconfigure
        read -p "Use existing configuration? (y/n): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0  # Use existing config
        else
            return 1  # Get new config
        fi
    fi
    
    return 1  # No existing config
}

# Function to validate domain format
validate_domain() {
    local domain="$1"
    # Basic domain validation: should contain at least one dot and valid characters
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# Function to validate email format
validate_email() {
    local email="$1"
    # Basic email validation
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

# Function to get interactive configuration
get_interactive_config() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   IGRA ORCHESTRA - UNIFIED AUTOMATIC SETUP"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Required configuration with validation
    while true; do
        prompt_user_input "Enter your domain name (e.g., my-node.example.com)" "DOMAIN" ""
        if validate_domain "$DOMAIN"; then
            break
        else
            log_message "ERROR: Invalid domain format. Please enter a valid domain name (e.g., my-node.example.com)"
        fi
    done
    
    while true; do
        prompt_user_input "Enter your email for SSL certificates" "EMAIL" ""
        if validate_email "$EMAIL"; then
            break
        else
            log_message "ERROR: Invalid email format. Please enter a valid email address"
        fi
    done
    prompt_user_input "Enter your node ID (unique identifier for your node)" "NODE_ID" ""
    prompt_user_input "Enter your health check API key (get from IGRA Discord)" "HEALTH_API_KEY" ""
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   RPC CONFIGURATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # RPC configuration
    while true; do
        prompt_user_input "Number of workers (1-5, default: 1)" "NUM_WORKERS" "1"
        # Validate NUM_WORKERS before proceeding
        if [[ "$NUM_WORKERS" =~ ^[1-5]$ ]]; then
            break
        else
            log_message "ERROR: Number of workers must be between 1 and 5"
        fi
    done
    prompt_user_input "RPC read-only mode? (y/n, default: n)" "RPC_READONLY_INPUT" "n"
    
    # Convert read-only input
    if [[ "$RPC_READONLY_INPUT" =~ ^[Yy]$ ]]; then
        RPC_READ_ONLY="true"
    else
        RPC_READ_ONLY="false"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   HTTPS CONFIGURATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # HTTPS configuration
    prompt_user_input "Use HTTPS? (y/n, default: y)" "USE_HTTPS_INPUT" "y"
    
    if [[ "$USE_HTTPS_INPUT" =~ ^[Yy]$ ]]; then
        USE_HTTPS="true"
    else
        USE_HTTPS="false"
        DOMAIN="localhost"  # Use localhost for HTTP mode
        EMAIL="admin@localhost"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   WALLET CONFIGURATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Wallet configuration for each worker
    # Ensure NUM_WORKERS is set and valid before looping
    NUM_WORKERS="${NUM_WORKERS:-1}"
    if ! [[ "$NUM_WORKERS" =~ ^[1-5]$ ]]; then
        log_message "ERROR: Invalid NUM_WORKERS value: $NUM_WORKERS"
        exit 1
    fi
    for i in $(seq 0 $((NUM_WORKERS-1))); do
        if [[ $i -eq 0 ]]; then
            echo "Primary wallet (Worker 0):"
        else
            echo "Worker $i wallet:"
        fi
        
        prompt_user_input "  Wallet password (or press Enter for empty)" "W${i}_PASSWORD" "" "true"
    done
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   BACKUP CONFIGURATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Backup configuration
    prompt_user_input "Download S3 backup? (y/n, default: y)" "DOWNLOAD_BACKUP_INPUT" "y"
    if [[ "$DOWNLOAD_BACKUP_INPUT" =~ ^[Yy]$ ]]; then
        DOWNLOAD_BACKUP="true"
        echo ""
        echo "Restore will overwrite existing data if backup is newer."
        echo "Only use 'yes' if you want to restore from backup (even if local data exists)."
        prompt_user_input "Restore backup? (y/n, default: y)" "FORCE_RESTORE_INPUT" "y"
        if [[ "$FORCE_RESTORE_INPUT" =~ ^[Yy]$ ]]; then
            FORCE_RESTORE="true"
        else
            FORCE_RESTORE="false"
        fi
    else
        DOWNLOAD_BACKUP="false"
        FORCE_RESTORE="false"
    fi
    
    # Set defaults for other settings
    S3_BUCKET="igralabs-viaduct-archival-data"
    S3_REGION="eu-north-1"
    
    echo ""
}

# Function to generate RPC configuration
generate_rpc_config() {
    local rpc_file="$PROJECT_ROOT/.env.rpc"
    local env_file="$PROJECT_ROOT/.env"
    
    log_message "Generating configuration files..."
    
    # Ensure we're using absolute path for PROJECT_ROOT
    PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
    
    # Primary: try .env.backend-with-rpc.example (with dot prefix)
    local example_file="$PROJECT_ROOT/.env.backend-with-rpc.example"
    
    if [[ ! -f "$example_file" ]]; then
        # Fallback 1: try env.backend-with-rpc.example (without dot)
        example_file="$PROJECT_ROOT/env.backend-with-rpc.example"
        if [[ ! -f "$example_file" ]]; then
            # Fallback 2: try .env.backend.example (with dot prefix)
            example_file="$PROJECT_ROOT/.env.backend.example"
            if [[ ! -f "$example_file" ]]; then
                # Fallback 3: try env.backend.example (without dot)
                example_file="$PROJECT_ROOT/env.backend.example"
                if [[ ! -f "$example_file" ]]; then
                    log_message "ERROR: Could not find example configuration file!"
                    log_message "PROJECT_ROOT: $PROJECT_ROOT"
                    log_message "Searched for:"
                    log_message "  - $PROJECT_ROOT/.env.backend-with-rpc.example"
                    log_message "  - $PROJECT_ROOT/env.backend-with-rpc.example"
                    log_message "  - $PROJECT_ROOT/.env.backend.example"
                    log_message "  - $PROJECT_ROOT/env.backend.example"
                    log_message ""
                    log_message "Files in project root:"
                    ls -la "$PROJECT_ROOT"/.env*.example "$PROJECT_ROOT"/env*.example 2>/dev/null || log_message "  (no .example files found)"
                    exit 1
                else
                    log_message "Using env.backend.example..."
                fi
            else
                log_message "Using .env.backend.example..."
            fi
        else
            log_message "Using env.backend-with-rpc.example..."
        fi
    else
        log_message "Using .env.backend-with-rpc.example..."
    fi
    
    # Copy example file to .env
    log_message "Copying $(basename "$example_file") to .env..."
    cp "$example_file" "$env_file"
    
    # Replace user-specific fields
    log_message "Updating configuration with your settings..."
    
    # Detect sed -i syntax (macOS requires extension, Linux doesn't)
    if sed --version >/dev/null 2>&1; then
        # Linux/GNU sed
        SED_IN_PLACE="sed -i"
    else
        # macOS/BSD sed
        SED_IN_PLACE="sed -i ''"
    fi
    
    # Replace NODE_ID (preserve comment if present)
    if grep -q "^NODE_ID=<your-node-name>" "$env_file"; then
        $SED_IN_PLACE "s|^NODE_ID=<your-node-name>.*|NODE_ID=$NODE_ID|g" "$env_file"
    elif grep -q "^NODE_ID=" "$env_file"; then
        $SED_IN_PLACE "s|^NODE_ID=.*|NODE_ID=$NODE_ID|g" "$env_file"
    fi
    
    # Replace HEALTH_CHECK_API_KEY
    if grep -q "^HEALTH_CHECK_API_KEY=<your-api-key>" "$env_file"; then
        $SED_IN_PLACE "s|^HEALTH_CHECK_API_KEY=<your-api-key>.*|HEALTH_CHECK_API_KEY=$HEALTH_API_KEY|g" "$env_file"
    elif grep -q "^HEALTH_CHECK_API_KEY=" "$env_file"; then
        $SED_IN_PLACE "s|^HEALTH_CHECK_API_KEY=.*|HEALTH_CHECK_API_KEY=$HEALTH_API_KEY|g" "$env_file"
    fi
    
    # Add or update S3 Force Restore setting
    if grep -q "^FORCE_RESTORE_BACKUP=" "$env_file"; then
        $SED_IN_PLACE "s|^FORCE_RESTORE_BACKUP=.*|FORCE_RESTORE_BACKUP=$FORCE_RESTORE|g" "$env_file"
    else
        echo "FORCE_RESTORE_BACKUP=$FORCE_RESTORE" >> "$env_file"
    fi
    
    # Generate RPC tokens
    log_message "Generating RPC access tokens..."
    
    # Remove existing RPC config section if it exists (between BEGIN and END markers)
    # This also removes any domain/email that might be inside the RPC section
    if grep -q "# --- BEGIN RPC CONFIG ---" "$env_file"; then
        # Remove everything from BEGIN to END RPC CONFIG (including the markers)
        $SED_IN_PLACE '/# --- BEGIN RPC CONFIG ---/,/# --- END RPC CONFIG ---/d' "$env_file"
    fi
    
    # Generate new RPC config
    cat >> "$env_file" << EOF

# --- BEGIN RPC CONFIG ---
# IGRA Orchestra RPC Configuration
# Generated on $(date)
# 
# RPC Access Tokens - Use any of these tokens to access the RPC endpoint
# Example: https://your-domain.com:8545/{RPC_ACCESS_TOKEN_1}

EOF

    for i in $(seq 1 46); do
        token=$(openssl rand -hex 16)
        echo "RPC_ACCESS_TOKEN_$i=$token" >> "$env_file"
    done
    
    # Add RPC read-only setting
    echo "" >> "$env_file"
    echo "# RPC Configuration" >> "$env_file"
    echo "RPC_READ_ONLY=$RPC_READ_ONLY" >> "$env_file"
    
    # Add worker configuration
    echo "" >> "$env_file"
    echo "# Worker configuration" >> "$env_file"
    for i in $(seq 0 $((NUM_WORKERS-1))); do
        echo "W${i}_WALLET_TO_ADDRESS=auto" >> "$env_file"
        # Use eval to get the password variable value
        eval "password_var=\$W${i}_PASSWORD"
        echo "W${i}_KASWALLET_PASSWORD=$password_var" >> "$env_file"
    done
    echo "" >> "$env_file"
    echo "# --- END RPC CONFIG ---" >> "$env_file"
    
    # Add domain configuration AFTER RPC section is regenerated
    # This ensures domain/email are not removed when RPC section is regenerated
    if grep -q "^IGRA_ORCHESTRA_DOMAIN=" "$env_file"; then
        $SED_IN_PLACE "s|^IGRA_ORCHESTRA_DOMAIN=.*|IGRA_ORCHESTRA_DOMAIN=$DOMAIN|g" "$env_file"
    else
        echo "" >> "$env_file"
        echo "# --- Domain Configuration ---" >> "$env_file"
        echo "IGRA_ORCHESTRA_DOMAIN=$DOMAIN" >> "$env_file"
    fi
    
    if grep -q "^IGRA_ORCHESTRA_DOMAIN_EMAIL=" "$env_file"; then
        $SED_IN_PLACE "s|^IGRA_ORCHESTRA_DOMAIN_EMAIL=.*|IGRA_ORCHESTRA_DOMAIN_EMAIL=$EMAIL|g" "$env_file"
    else
        echo "IGRA_ORCHESTRA_DOMAIN_EMAIL=$EMAIL" >> "$env_file"
    fi
    
    # Validate that all 46 tokens were generated (check for tokens 1-46)
    local token_count=$(grep -cE "^RPC_ACCESS_TOKEN_[0-9]+=" "$env_file" || echo "0")
    if [[ $token_count -ne 46 ]]; then
        log_message "ERROR: Expected 46 RPC tokens but found $token_count"
        log_message "Please check the generated .env file"
        exit 1
    fi
    
    log_message "Configuration saved successfully ✅"
    log_message "Generated $token_count RPC access tokens ✅"
}

# Function to ensure domain and email are configured
ensure_domain_config() {
    local env_file="$PROJECT_ROOT/.env"
    local needs_update=false
    
    # Check if domain/email are missing
    if [[ -z "$IGRA_ORCHESTRA_DOMAIN" ]] || [[ -z "$IGRA_ORCHESTRA_DOMAIN_EMAIL" ]]; then
        log_message "Domain configuration is missing. Please provide:"
        echo ""
        
        # Prompt for domain if missing
        if [[ -z "$IGRA_ORCHESTRA_DOMAIN" ]]; then
            while true; do
                prompt_user_input "Enter your domain name (e.g., my-node.example.com)" "DOMAIN" ""
                if validate_domain "$DOMAIN"; then
                    IGRA_ORCHESTRA_DOMAIN="$DOMAIN"
                    export IGRA_ORCHESTRA_DOMAIN="$DOMAIN"
                    needs_update=true
                    break
                else
                    log_message "ERROR: Invalid domain format. Please enter a valid domain name (e.g., my-node.example.com)"
                fi
            done
        else
            DOMAIN="$IGRA_ORCHESTRA_DOMAIN"
        fi
        
        # Prompt for email if missing
        if [[ -z "$IGRA_ORCHESTRA_DOMAIN_EMAIL" ]]; then
            while true; do
                prompt_user_input "Enter your email for SSL certificates" "EMAIL" ""
                if validate_email "$EMAIL"; then
                    IGRA_ORCHESTRA_DOMAIN_EMAIL="$EMAIL"
                    export IGRA_ORCHESTRA_DOMAIN_EMAIL="$EMAIL"
                    needs_update=true
                    break
                else
                    log_message "ERROR: Invalid email format. Please enter a valid email address"
                fi
            done
        else
            EMAIL="$IGRA_ORCHESTRA_DOMAIN_EMAIL"
        fi
        
        # Update .env file if needed
        if [[ "$needs_update" == "true" ]]; then
            log_message "Updating .env file with domain configuration..."
            
            # Detect sed -i syntax
            if sed --version >/dev/null 2>&1; then
                SED_IN_PLACE="sed -i"
            else
                SED_IN_PLACE="sed -i ''"
            fi
            
            # Add or update domain configuration
            if grep -q "^IGRA_ORCHESTRA_DOMAIN=" "$env_file"; then
                $SED_IN_PLACE "s|^IGRA_ORCHESTRA_DOMAIN=.*|IGRA_ORCHESTRA_DOMAIN=$IGRA_ORCHESTRA_DOMAIN|g" "$env_file"
            else
                echo "" >> "$env_file"
                echo "# --- Domain Configuration ---" >> "$env_file"
                echo "IGRA_ORCHESTRA_DOMAIN=$IGRA_ORCHESTRA_DOMAIN" >> "$env_file"
            fi
            
            if grep -q "^IGRA_ORCHESTRA_DOMAIN_EMAIL=" "$env_file"; then
                $SED_IN_PLACE "s|^IGRA_ORCHESTRA_DOMAIN_EMAIL=.*|IGRA_ORCHESTRA_DOMAIN_EMAIL=$IGRA_ORCHESTRA_DOMAIN_EMAIL|g" "$env_file"
            else
                echo "IGRA_ORCHESTRA_DOMAIN_EMAIL=$IGRA_ORCHESTRA_DOMAIN_EMAIL" >> "$env_file"
            fi
            
            log_message "Domain configuration updated ✅"
        fi
    else
        # Set DOMAIN and EMAIL variables for consistency
        DOMAIN="$IGRA_ORCHESTRA_DOMAIN"
        EMAIL="$IGRA_ORCHESTRA_DOMAIN_EMAIL"
    fi
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
    
    # Validate number of workers
    if ! [[ "$NUM_WORKERS" =~ ^[1-5]$ ]]; then
        log_message "ERROR: Number of workers must be between 1 and 5"
        exit 1
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
    
    # Check if git is available for repository setup
    if ! command -v git >/dev/null 2>&1; then
        log_message "ERROR: git is not available (needed for repository setup)"
        exit 1
    fi
}

# Function to setup repositories
setup_repositories() {
    log_message "Setting up repositories..."
    
    # Only clone rusty-kaspa (needed for kaspad build)
    # All other services use prebuilt Docker images
    local kaspad_repo_dir="$PROJECT_ROOT/build/repos/rusty-kaspa"
    
    # Check for invalid git repo (directory exists but no .git)
    if [[ -d "$kaspad_repo_dir" ]] && [[ ! -d "$kaspad_repo_dir/.git" ]]; then
        log_message "WARNING: $kaspad_repo_dir exists but is not a valid git repository. Removing..."
        rm -rf "$kaspad_repo_dir"
    fi
    
    if [[ ! -d "$kaspad_repo_dir" ]]; then
        log_message "Cloning rusty-kaspa repository (needed for kaspad build)..."
        mkdir -p "$PROJECT_ROOT/build/repos"
        
        if ! git clone https://github.com/kaspanet/rusty-kaspa.git "$kaspad_repo_dir"; then
            log_message "ERROR: Failed to clone rusty-kaspa repository"
            exit 1
        fi
        
        log_message "Rusty-kaspa repository cloned ✅"
    else
        log_message "Rusty-kaspa repository already exists ✅"
    fi
    
    # Note: All other services (block-builder, viaduct, rpc-provider, kaswallet, execution-layer)
    # use prebuilt Docker images, so no need to clone their repositories
    
    log_message "Repository setup completed ✅"
}

# Function to generate JWT secret if needed
setup_jwt_secret() {
    local jwt_file="$PROJECT_ROOT/keys/jwt.hex"
    
    if [[ ! -f "$jwt_file" ]]; then
        log_message "Generating JWT secret..."
        mkdir -p "$PROJECT_ROOT/keys"
        if ! openssl rand -hex 32 > "$jwt_file"; then
            log_message "ERROR: Failed to generate JWT secret"
            exit 1
        fi
        log_message "JWT secret created ✅"
    fi
}

# Function to setup execution layer repository and script
# NOTE: This only switches branches in the CLONED execution-layer repository,
# NOT in the main igra-orchestra-public repository
setup_execution_layer() {
    log_message "Using prebuilt execution-layer image (skipping repository setup)..."
}

# Function to setup kaspad image
# NOTE: This only switches branches in the CLONED rusty-kaspa repository,
# NOT in the main igra-orchestra-public repository
setup_kaspad() {
    local kaspad_repo_dir="$PROJECT_ROOT/build/repos/rusty-kaspa"
    local kaspad_branch="${KASPAD_BRANCH:-master}"
    
    # Check if kaspad image already exists
    if docker image inspect kaspad >/dev/null 2>&1; then
        log_message "Kaspad image found ✅"
        return 0
    fi
    
    log_message "Kaspad image not found. Building from source..."
    echo ""
    log_message "Note: This is a one-time setup and takes ~10-15 minutes"
    echo ""
    
    # Repository should already be cloned by setup_repositories()
    if [[ ! -d "$kaspad_repo_dir" ]] || [[ ! -d "$kaspad_repo_dir/.git" ]]; then
        log_message "ERROR: Rusty-kaspa repository not found or invalid. This should have been cloned earlier."
        exit 1
    fi
    
    # Update repository to latest
    log_message "Updating rusty-kaspa repository..."
    (
        cd "$kaspad_repo_dir" || exit 1
        GIT_DIR="$kaspad_repo_dir/.git" GIT_WORK_TREE="$kaspad_repo_dir" git fetch >/dev/null 2>&1
        if GIT_DIR="$kaspad_repo_dir/.git" GIT_WORK_TREE="$kaspad_repo_dir" git checkout "$kaspad_branch" >/dev/null 2>&1; then
            log_message "Switched rusty-kaspa repository to branch: $kaspad_branch"
        else
            log_message "WARNING: Failed to checkout branch $kaspad_branch"
        fi
        GIT_DIR="$kaspad_repo_dir/.git" GIT_WORK_TREE="$kaspad_repo_dir" git pull >/dev/null 2>&1
    )
    log_message "Rusty-kaspa repository updated ✅"
    
    echo ""
    log_message "Building kaspad Docker image (this may take 10-15 minutes)..."
    echo ""
    
    (
        cd "$kaspad_repo_dir" || exit 1
        if ! docker build -t kaspad -f "$PROJECT_ROOT/build/Dockerfile.kaspad" .; then
            log_message "ERROR: Failed to build kaspad image"
            exit 1
        fi
    )
    
    echo ""
    log_message "Kaspad image built successfully ✅"
}

# Function to setup kaswallet (just pull the prebuilt image)
setup_kaswallet() {
    # Check if kaswallet image already exists
    if docker image inspect igranetwork/kaswallet:v0.2.1 >/dev/null 2>&1; then
        log_message "Kaswallet image found ✅"
        return 0
    fi
    
    log_message "Pulling kaswallet image..."
    
    if docker pull igranetwork/kaswallet:v0.2.1; then
        log_message "Kaswallet image pulled successfully ✅"
    else
        log_message "WARNING: Failed to pull kaswallet image"
        log_message "The image will be pulled automatically when starting services"
    fi
}

# Function to stream restore backup from S3 directly to Docker volume
stream_restore_backup() {
    if [[ "$DOWNLOAD_BACKUP" != "true" ]]; then
        return 0
    fi
    
    log_message "Restoring backup from S3 (streaming directly to Docker volume)..."
    echo ""
    
    # Ensure PROJECT_ROOT is absolute and set correctly
    PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
    local stream_restore_script="$PROJECT_ROOT/scripts/backup/stream-restore-from-s3.sh"
    
    # Debug: Check if script exists
    if [[ ! -f "$stream_restore_script" ]]; then
        log_message "⚠️  Restore script not found at: $stream_restore_script"
        log_message "PROJECT_ROOT: $PROJECT_ROOT"
        log_message "Current directory: $(pwd)"
        log_message "Checking alternative locations..."
        
        # Try relative path from script directory
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local alt_path="$script_dir/../scripts/backup/stream-restore-from-s3.sh"
        alt_path="$(cd "$(dirname "$alt_path")" && pwd)/$(basename "$alt_path")"
        
        if [[ -f "$alt_path" ]]; then
            log_message "Found script at alternative location: $alt_path"
            stream_restore_script="$alt_path"
        else
            log_message "⚠️  Restore script not found - viaduct will sync from scratch"
            echo ""
            return 1
        fi
    fi
    
    chmod +x "$stream_restore_script"
    # Use --yes flag to skip confirmation when FORCE_RESTORE is true
    if "$stream_restore_script" --yes viaduct; then
        echo ""
        log_message "Backup restored successfully ✅"
        echo ""
        return 0
    else
        echo ""
        log_message "⚠️  Backup restore failed - viaduct will sync from scratch (4-6 hours)"
        echo ""
        return 1
    fi
}

# Function to generate wallet if needed
generate_wallet_if_needed() {
    for i in $(seq 0 $((NUM_WORKERS-1))); do
        local wallet_key_file="$PROJECT_ROOT/keys/wallet-${i}/keys.json"
        
        # Check if wallet already exists
        if [[ -f "$wallet_key_file" ]]; then
            log_message "Wallet ${i} already exists ✅"
            continue
        fi
        
        log_message "Wallet ${i} needs to be created..."
        mkdir -p "$PROJECT_ROOT/keys/wallet-${i}"
        
        # Try to run it interactively if we have a TTY
        if [[ -t 0 ]]; then
            # We have a TTY, try to create wallet interactively
            log_message "Creating wallet ${i} interactively..."
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "   ⚠️  IMPORTANT - READ CAREFULLY"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "The wallet creation will display a MNEMONIC PHRASE."
            echo "This phrase is the ONLY way to recover your wallet!"
            echo ""
            echo "⚠️  WRITE DOWN THE MNEMONIC PHRASE AND STORE IT SAFELY!"
            echo "⚠️  DO NOT SHARE IT WITH ANYONE!"
            echo "⚠️  YOU CANNOT RECOVER YOUR WALLET WITHOUT IT!"
            echo ""
            echo "When prompted for password, press Enter for empty password."
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            read -p "Press Enter to continue with wallet ${i} creation..."
            echo ""
            
            local temp_log=$(mktemp)
            local wallet_created=false
            if docker run --rm -it -v "$PROJECT_ROOT/keys/wallet-${i}:/keys" \
                --entrypoint /app/kaswallet-create \
                igranetwork/kaswallet:v0.2.1 \
                --testnet -k /keys/keys.json 2>&1 | tee "$temp_log"; then
                
                if [[ -f "$wallet_key_file" ]]; then
                    wallet_created=true
                    # Try to extract wallet address
                    local wallet_addr=$(grep -oE "kaspatest:[a-zA-Z0-9]+" "$temp_log" | head -1)
                    rm -f "$temp_log"
                    
                    echo ""
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "   ⚠️  CONFIRMATION REQUIRED"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""
                    echo "Have you saved your mnemonic phrase for wallet ${i} in a safe place?"
                    echo "Without it, you CANNOT recover your wallet!"
                    echo ""
                    
                    # Loop until user confirms
                    while true; do
                        read -p "Type 'yes' to confirm you have saved your mnemonic: " confirmation
                        if [[ "$confirmation" == "yes" ]]; then
                            break
                        else
                            echo "Please type 'yes' to confirm (lowercase)"
                        fi
                    done
                    
                    log_message ""
                    log_message "Wallet ${i} created successfully ✅"
                    
                    echo ""
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo "   ✅ WALLET ${i} CREATED"
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""
                    echo "Keys saved to: $wallet_key_file"
                    echo ""
                    echo "Note: Wallet address will be retrieved and displayed"
                    echo "      after kaspad starts and kaswallet-${i} connects."
                    echo ""
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                    echo ""
                fi
            fi
            
            # Clean up temp log if wallet wasn't created
            if [[ "$wallet_created" != "true" ]] && [[ -f "$temp_log" ]]; then
                rm -f "$temp_log"
            fi
        else
            # If we get here, wallet wasn't created (no TTY or creation failed)
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "   WALLET ${i} CREATION REQUIRED"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            echo "Please run the following command to create wallet ${i}:"
            echo ""
            echo "  docker run --rm -it -v \"\$PWD/keys/wallet-${i}:/keys\" \\"
            echo "    --entrypoint /app/kaswallet-create \\"
            echo "    igranetwork/kaswallet:v0.2.1 \\"
            echo "    --testnet -k /keys/keys.json"
            echo ""
            echo "When prompted for password, press Enter for empty password."
            echo "IMPORTANT: Save the mnemonic phrase displayed!"
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            log_message "After creating wallet ${i}, run this script again."
            echo ""
            exit 1
        fi
    done
}

# Function to check deployment status
check_deployment_status() {
    local status="not_started"
    
    # Check if services are running
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^kaspad$"; then
        status="kaspad_running"
        
        # Check if kaspad is synced
        if docker exec kaspad /app/kaspad-healthcheck.sh >/dev/null 2>&1; then
            status="kaspad_synced"
            
            # Check if backend is running
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^execution-layer$"; then
                status="backend_running"
                
                # Check if RPC is running
                if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^rpc-provider-0$"; then
                    status="fully_deployed"
                fi
            fi
        fi
    fi
    
    echo "$status"
}

# Function to start the full deployment
start_deployment() {
    # Export variables for docker-compose
    export NETWORK="${NETWORK:-testnet}"
    export NUM_WORKERS="${NUM_WORKERS:-1}"
    
    log_message "Checking current deployment status..."
    
    # Check if docker-compose.full.yml exists
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_message "ERROR: docker-compose.full.yml not found at: $COMPOSE_FILE"
        log_message "Please ensure you're running from the correct directory"
        exit 1
    fi
    
    # IMPORTANT: Do NOT change directory to avoid git context issues
    # Use absolute paths for all operations instead
    # All git operations use git -C to avoid affecting main repo
    
    # Check current status
    local current_status=$(check_deployment_status)
    
    case "$current_status" in
        "not_started")
            log_message "No services running. Starting fresh deployment..."
            ;;
        "kaspad_running")
            log_message "Kaspad is already running and syncing ✅"
            log_message "Orchestrator will start backend automatically when sync completes"
            
            # Check if sync-orchestrator is running
            if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^sync-orchestrator$"; then
                log_message "Starting sync orchestrator..."
                if docker compose version >/dev/null 2>&1; then
                    docker compose -f "$COMPOSE_FILE" up -d sync-orchestrator
                else
                    docker-compose -f "$COMPOSE_FILE" up -d sync-orchestrator
                fi
            fi
            return 0
            ;;
        "kaspad_synced")
            log_message "Kaspad is synced! ✅"
            log_message "Backend should be starting..."
            return 0
            ;;
        "backend_running")
            log_message "Backend is running ✅"
            log_message "RPC services should be available soon..."
            return 0
            ;;
        "fully_deployed")
            log_message "Deployment is already complete! ✅"
            log_message "All services are running"
            echo ""
            log_message "Run './scripts/check-status.sh' to see details"
            return 0
            ;;
    esac
    
    log_message "Using compose file: $COMPOSE_FILE"
    log_message "Using prebuilt Docker images..."
    
    # Start the full deployment with sync orchestrator
    # Use absolute path for compose file to avoid needing to change directory
    if docker compose version >/dev/null 2>&1; then
        # Use new docker compose command
        log_message "Pulling prebuilt images (this may take a few minutes)..."
        
        # Pull other services (not kaspad)
        docker compose -f "$COMPOSE_FILE" pull kaswallet-0 traefik 2>/dev/null || true
        
        log_message "Starting services..."
        docker compose -f "$COMPOSE_FILE" up -d --remove-orphans kaspad traefik sync-orchestrator
        
        # Verify containers actually started
        sleep 3
        for container in kaspad traefik sync-orchestrator; do
            if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
                log_message "⚠️  $container failed to start, retrying..."
                docker rm -f "$container" >/dev/null 2>&1 || true
                docker compose -f "$COMPOSE_FILE" up -d --force-recreate "$container"
            fi
        done
    else
        # Use legacy docker-compose command
        log_message "Pulling prebuilt images (this may take a few minutes)..."
        
        # Pull other services (not kaspad)
        docker-compose -f "$COMPOSE_FILE" pull kaswallet-0 traefik 2>/dev/null || true
        
        log_message "Starting services..."
        docker-compose -f "$COMPOSE_FILE" up -d --remove-orphans kaspad traefik sync-orchestrator
        
        # Verify containers actually started
        sleep 3
        for container in kaspad traefik sync-orchestrator; do
            if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
                log_message "⚠️  $container failed to start, retrying..."
                docker rm -f "$container" >/dev/null 2>&1 || true
                docker-compose -f "$COMPOSE_FILE" up -d --force-recreate "$container"
            fi
        done
    fi
    
    # Wait a moment for services to initialize
    sleep 2
    
    log_message "Services started successfully ✅"
}

# Function to get wallet address from newly created wallet
get_wallet_address_from_new_wallet() {
    local wallet_key_file="$1"
    local wallet_index="$2"
    local wallet_addr=""
    
    # Determine network name - it's the compose project name with _igra-network suffix
    local network_name="igra-orchestra-${NETWORK}-full_igra-network"
    
    # Get actual network name from docker
    local actual_network=$(docker network ls --format '{{.Name}}' | grep "igra-orchestra.*full.*igra-network" | head -1)
    if [[ -n "$actual_network" ]]; then
        network_name="$actual_network"
        log_message "Using Docker network: $network_name" >&2
    fi
    
    log_message "Starting temporary wallet daemon to retrieve address for wallet ${wallet_index}..." >&2
    
    # Start wallet daemon in Docker network to connect to kaspad
    # Note: We use the default port 8082 since test_client expects it
    # Wallets are retrieved sequentially, so there's no port conflict
    if docker run --rm -d \
        -v "$PROJECT_ROOT/keys/wallet-${wallet_index}:/keys" \
        --network "$network_name" \
        -p "127.0.0.1:8082:8082" \
        --name "kaswallet-temp-addr-${wallet_index}" \
        igranetwork/kaswallet:v0.2.1 \
        --testnet \
        --keys /keys/keys.json \
        --server ws://kaspad:17210 \
        --listen 0.0.0.0:8082 2>&1 | tee "/tmp/kaswallet_start_${wallet_index}.log" >&2; then
        
        log_message "Wallet daemon starting, waiting for connection to kaspad..." >&2
        
        # Wait for wallet to connect to kaspad (up to 120 seconds)
        local wait_count=0
        local wallet_synced=false
        while [[ $wait_count -lt 120 ]]; do
            local logs=$(docker logs "kaswallet-temp-addr-${wallet_index}" 2>&1)
            
            # Check if finished initial sync
            if echo "$logs" | grep -q "Finished initial sync"; then
                wallet_synced=true
                log_message "Wallet finished initial sync! ✅" >&2
                sleep 2  # Give it a moment to stabilize
                break
            fi
            
            # Check if at least connected
            if echo "$logs" | grep -q "Connected to kaspa node successfully"; then
                # Show we're connected but still syncing
                if [[ $((wait_count % 20)) -eq 0 ]] && [[ $wait_count -gt 0 ]]; then
                    log_message "Wallet connected, waiting for initial sync... ($wait_count/120s)" >&2
                fi
            fi
            
            # Show progress every 10 seconds
            if [[ $((wait_count % 10)) -eq 0 ]] && [[ $wait_count -gt 0 ]]; then
                log_message "Still waiting for wallet to sync... ($wait_count/120s)" >&2
            fi
            
            sleep 2
            wait_count=$((wait_count + 2))
        done
        
        if [[ "$wallet_synced" == "true" ]]; then
            
            log_message "Retrieving wallet address using test_client..." >&2
            
            # Try to get address using test_client via host network
            # test_client connects to localhost:8082 by default
            # Since we bind each wallet to a unique port, we need to use the correct port
            # However, test_client doesn't support custom ports, so we'll use the default port
            # and ensure wallets are retrieved sequentially to avoid conflicts
            wallet_addr=$(docker run --rm \
                --network "host" \
                --entrypoint /app/test_client \
                igranetwork/kaswallet:v0.2.1 \
                2>&1 | tee "/tmp/test_client_${wallet_index}.log" | grep -oE "kaspatest:[a-zA-Z0-9]+" | head -1)
            
            if [[ -z "$wallet_addr" ]]; then
                log_message "Failed to retrieve address. Debug logs:" >&2
                log_message "Wallet logs:" >&2
                docker logs "kaswallet-temp-addr-${wallet_index}" 2>&1 | tail -20 >&2
                log_message "Test client output:" >&2
                cat "/tmp/test_client_${wallet_index}.log" >&2
            fi
        else
            log_message "Wallet failed to connect to kaspad. Logs:" >&2
            docker logs "kaswallet-temp-addr-${wallet_index}" 2>&1 | tail -20 >&2
        fi
        
        # Stop and remove temporary wallet
        docker stop "kaswallet-temp-addr-${wallet_index}" >/dev/null 2>&1
        docker rm "kaswallet-temp-addr-${wallet_index}" >/dev/null 2>&1
        rm -f "/tmp/kaswallet_start_${wallet_index}.log" "/tmp/test_client_${wallet_index}.log"
        
        if [[ -n "$wallet_addr" ]]; then
            echo "$wallet_addr"
            return 0
        fi
    else
        log_message "Failed to start temporary wallet daemon" >&2
        cat "/tmp/kaswallet_start_${wallet_index}.log" >&2
        rm -f "/tmp/kaswallet_start_${wallet_index}.log"
    fi
    
    return 1
}

# Function to retrieve and save wallet addresses to .env
retrieve_and_save_wallet_addresses() {
    local env_file="$PROJECT_ROOT/.env"
    
    # Export NETWORK variable for docker operations
    export NETWORK="${NETWORK:-testnet}"
    
    log_message "Waiting for kaspad to initialize..."
    
    # Wait for kaspad RPC to be available (up to 60 seconds)
    local wait_count=0
    local kaspad_ready=false
    
    while [[ $wait_count -lt 60 ]]; do
        # Check for WRPC Server starting (this is what kaswallet connects to)
        if docker logs kaspad 2>/dev/null | grep -q "WRPC Server starting on.*17210"; then
            kaspad_ready=true
            log_message "Kaspad WRPC server is ready ✅"
            break
        fi
        sleep 2
        wait_count=$((wait_count + 2))
        
        # Show progress every 10 seconds
        if [[ $((wait_count % 10)) -eq 0 ]]; then
            log_message "Still waiting for kaspad to initialize... ($wait_count/60s)"
        fi
    done
    
    if [[ "$kaspad_ready" == "true" ]]; then
        log_message "Retrieving wallet addresses..."
        
        # Retrieve addresses for all workers
        for i in $(seq 0 $((NUM_WORKERS-1))); do
            local wallet_key_file="$PROJECT_ROOT/keys/wallet-${i}/keys.json"
            
            # Check if wallet keys exist
            if [[ ! -f "$wallet_key_file" ]]; then
                log_message "No wallet keys found for wallet ${i}, skipping address retrieval"
                continue
            fi
            
            # Check if address is already set (not "auto")
            local current_addr=$(grep "^W${i}_WALLET_TO_ADDRESS=" "$env_file" 2>/dev/null | cut -d'=' -f2)
            
            if [[ -n "$current_addr" && "$current_addr" != "auto" ]]; then
                log_message "Wallet ${i} address already configured: $current_addr"
                continue
            fi
            
            # Try to get address using the helper function
            local wallet_addr=$(get_wallet_address_from_new_wallet "$wallet_key_file" "$i")
            
            if [[ -n "$wallet_addr" ]]; then
                # Update .env file
                if grep -q "^W${i}_WALLET_TO_ADDRESS=" "$env_file" 2>/dev/null; then
                    # Update existing value (use compatible sed syntax)
                    if sed --version >/dev/null 2>&1; then
                        sed -i "s|^W${i}_WALLET_TO_ADDRESS=.*|W${i}_WALLET_TO_ADDRESS=$wallet_addr|" "$env_file"
                    else
                        sed -i '' "s|^W${i}_WALLET_TO_ADDRESS=.*|W${i}_WALLET_TO_ADDRESS=$wallet_addr|" "$env_file"
                    fi
                    log_message "✅ Wallet ${i} address retrieved and saved to .env"
                    log_message "   Address: $wallet_addr"
                else
                    # Add new value
                    echo "" >> "$env_file"
                    echo "# Wallet ${i} address (auto-retrieved)" >> "$env_file"
                    echo "W${i}_WALLET_TO_ADDRESS=$wallet_addr" >> "$env_file"
                    log_message "✅ Wallet ${i} address retrieved and added to .env"
                    log_message "   Address: $wallet_addr"
                fi
                
                # Export for use in final status display
                eval "export WALLET_ADDRESS_${i}_RETRIEVED='$wallet_addr'"
            else
                log_message "Note: Could not retrieve wallet ${i} address"
                log_message "      It will be available after kaspad syncs"
            fi
        done
    else
        log_message "Note: Kaspad is still initializing"
        log_message "      Wallet addresses will be available in container logs"
    fi
}

# Function to show final status with wallet addresses
show_final_status() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   ✅ DEPLOYMENT STARTED SUCCESSFULLY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Wait a moment for services to initialize
    sleep 3
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "   📋 YOUR NODE INFORMATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Ensure NUM_WORKERS is set (load from .env if not already set)
    local env_file="$PROJECT_ROOT/.env"
    if [[ -z "$NUM_WORKERS" ]] && [[ -f "$env_file" ]]; then
        NUM_WORKERS=$(grep '^NUM_WORKERS=' "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "1")
    fi
    NUM_WORKERS="${NUM_WORKERS:-1}"
    
    # Load USE_HTTPS and DOMAIN from .env if not set
    if [[ -z "$USE_HTTPS" ]] && [[ -f "$env_file" ]]; then
        # Check if domain is localhost (indicates HTTP mode)
        local domain_from_env=$(grep '^IGRA_ORCHESTRA_DOMAIN=' "$env_file" 2>/dev/null | cut -d'=' -f2)
        if [[ "$domain_from_env" == "localhost" ]]; then
            USE_HTTPS="false"
        else
            USE_HTTPS="true"
        fi
    fi
    USE_HTTPS="${USE_HTTPS:-true}"
    
    if [[ -z "$DOMAIN" ]] && [[ -f "$env_file" ]]; then
        DOMAIN=$(grep '^IGRA_ORCHESTRA_DOMAIN=' "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "localhost")
    fi
    DOMAIN="${DOMAIN:-localhost}"
    
    # Load RPC_READ_ONLY from .env if not set
    if [[ -z "$RPC_READ_ONLY" ]] && [[ -f "$env_file" ]]; then
        RPC_READ_ONLY=$(grep '^RPC_READ_ONLY=' "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "false")
    fi
    RPC_READ_ONLY="${RPC_READ_ONLY:-false}"
    
    # Show wallet addresses
    echo "🔑 Wallet Addresses:"
    for i in $(seq 0 $((NUM_WORKERS-1))); do
        # Use eval to get the dynamically named variable
        eval "local wallet_address=\$WALLET_ADDRESS_${i}_RETRIEVED"
        
        if [[ -n "$wallet_address" ]]; then
            echo "   Worker ${i}: $wallet_address"
        else
            echo "   Worker ${i}: Address will be available after kaspad initializes"
        fi
    done
    echo ""
    
    # Show RPC endpoint
    echo "🌐 RPC Endpoint:"
    local rpc_token=$(grep 'RPC_ACCESS_TOKEN_1=' "$env_file" 2>/dev/null | cut -d'=' -f2)
    if [[ -n "$rpc_token" ]]; then
        if [[ "$USE_HTTPS" == "true" ]]; then
            echo "   https://$DOMAIN:8545/$rpc_token"
        else
            echo "   http://$DOMAIN:8545/$rpc_token"
        fi
    else
        echo "   Check .env file for RPC_ACCESS_TOKEN_1"
    fi
    echo ""
    
    # Show RPC configuration
    echo "⚙️  RPC Configuration:"
    echo "   Read-Only Mode: ${RPC_READ_ONLY}"
    echo "   Number of Workers: ${NUM_WORKERS}"
    echo "   HTTPS Enabled: ${USE_HTTPS}"
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
    echo "   🔍 MONITORING & TROUBLESHOOTING"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Check status:"
    echo "  ./scripts/check-status.sh"
    echo ""
    echo "Monitor sync progress:"
    echo "  docker compose -f docker-compose.full.yml logs -f sync-orchestrator"
    echo ""
    echo "View service logs:"
    echo "  docker compose -f docker-compose.full.yml logs -f kaspad"
    echo "  docker compose -f docker-compose.full.yml logs -f execution-layer"
    echo "  docker compose -f docker-compose.full.yml logs -f rpc-provider-0"
    echo ""
    echo "Test RPC endpoint:"
    echo "  curl -X POST https://$DOMAIN:8545/$rpc_token \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
    echo ""
    
    if [[ "$RPC_READ_ONLY" == "false" ]]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "   💰 ENTRY TRANSACTIONS"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "To send entry transactions (bridge KAS from L1 to L2):"
        echo ""
        echo "1. Fund your worker wallets with KAS tokens"
        echo "2. Use the entry transaction sender:"
        echo ""
        echo "   export WALLET_TO_ADDRESS='kaspatest:[your-worker-0-address]'"
        echo "   export WALLET_DAEMON_URI='http://kaswallet-0:8082'"
        echo "   export KASWALLET_PASSWORD=''"
        echo ""
        echo "   docker run --rm \\"
        echo "     -e WALLET_TO_ADDRESS \\"
        echo "     -e WALLET_DAEMON_URI \\"
        echo "     -e KASWALLET_PASSWORD \\"
        echo "     --network host \\"
        echo "     --entrypoint /app/entry_transaction_sender \\"
        echo "     igranetwork/rpc-provider:latest \\"
        echo "     --recipient kaspatest:qprjv0e4a2l2t56870d6jwkvf9dnjnynhzr0a3kf4spndpz9f6hmxy0ux9yte \\"
        echo "     --amount 1.5 \\"
        echo "     --l2-address 0x5E1DC98169b3F5D055A18cb359B60F0B576Ab335"
        echo ""
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main execution
main() {
    # Ensure PROJECT_ROOT is absolute path
    PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
    
    # Save the current branch of the main repository to restore it later
    # This prevents the script from accidentally switching branches in the main repo
    # Store in global variable so trap can access it
    MAIN_REPO_BRANCH=""
    if git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        # Get current branch - try multiple methods to be sure
        MAIN_REPO_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [[ -z "$MAIN_REPO_BRANCH" ]] || [[ "$MAIN_REPO_BRANCH" == "HEAD" ]]; then
            # We might be in detached HEAD state, get the commit instead
            MAIN_REPO_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "")
        fi
        
        # Also save the current working directory to ensure we restore in the right place
        export MAIN_REPO_DIR="$PROJECT_ROOT"
        
        if [[ -n "$MAIN_REPO_BRANCH" ]]; then
            log_message "Main repository is on branch/commit: $MAIN_REPO_BRANCH (will be restored on exit)"
            # Verify we can actually checkout this branch (to catch issues early)
            if ! git -C "$PROJECT_ROOT" rev-parse --verify "$MAIN_REPO_BRANCH" >/dev/null 2>&1; then
                log_message "WARNING: Cannot verify branch '$MAIN_REPO_BRANCH' exists - restore may fail"
            fi
        else
            log_message "WARNING: Could not determine main repository branch"
        fi
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Check if we have existing configuration
    if check_existing_config; then
        log_message "Using existing configuration ✅"
        # Ensure NETWORK is set from .env
        export NETWORK="${NETWORK:-testnet}"
        # Ensure NUM_WORKERS is set from .env and validate it
        export NUM_WORKERS="${NUM_WORKERS:-1}"
        if ! [[ "$NUM_WORKERS" =~ ^[1-5]$ ]]; then
            log_message "ERROR: Invalid NUM_WORKERS value in .env: $NUM_WORKERS"
            log_message "NUM_WORKERS must be between 1 and 5"
            exit 1
        fi
        
        # Ensure domain/email are configured (prompt if missing)
        ensure_domain_config
    else
        # Get interactive configuration
        get_interactive_config
        
        # Validate configuration
        validate_configuration
        
        # Generate RPC configuration
        generate_rpc_config
        
        # Export variables for docker-compose
        export NETWORK="${NETWORK:-testnet}"
        export NUM_WORKERS="${NUM_WORKERS:-1}"
    fi
    
    # Setup required files and repositories
    setup_repositories
    setup_jwt_secret
    setup_execution_layer
    
    # Setup kaspad image (builds if needed)
    setup_kaspad
    
    # Setup kaswallet image (builds if needed)
    setup_kaswallet
    
    # Generate wallets if needed
    generate_wallet_if_needed
    
    # Stream restore backup from S3 if requested
    # Note: This happens BEFORE starting any services, so the backup data is ready when viaduct starts
    # Streams directly from S3 to Docker volume (no intermediate storage, no integrity checks)
    if [[ "$DOWNLOAD_BACKUP" == "true" ]]; then
        log_message "Preparing to restore backup from S3..."
        stream_restore_backup
    fi
    
    # Start deployment (idempotent - will detect current state)
    start_deployment
    
    # Retrieve and save wallet addresses
    retrieve_and_save_wallet_addresses
    
    # Check current status and show appropriate message
    local current_status=$(check_deployment_status)
    
    if [[ "$current_status" == "fully_deployed" ]]; then
        log_message ""
        log_message "✅ All services are already running!"
        log_message "Run './scripts/check-status.sh' for detailed status"
    else
        # Show final status
        show_final_status
    fi
    
    # Always restore the original branch of the main repository
    # This ensures the main repo stays on the branch it started with
    # Note: The EXIT trap will also restore, but we do it here for logging
    if [[ -n "$MAIN_REPO_BRANCH" ]] && git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        local current_branch=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        # Check if we're in detached HEAD (commit hash instead of branch name)
        if [[ -z "$current_branch" ]] || [[ "$current_branch" == "HEAD" ]]; then
            current_branch=$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "")
        fi
        
        # Always restore if branch changed
        if [[ -n "$MAIN_REPO_BRANCH" ]] && [[ "$current_branch" != "$MAIN_REPO_BRANCH" ]]; then
            log_message "⚠️  Main repository branch changed from '$MAIN_REPO_BRANCH' to '$current_branch'"
            log_message "Restoring main repository to original branch/commit: $MAIN_REPO_BRANCH"
            if git -C "$PROJECT_ROOT" checkout "$MAIN_REPO_BRANCH" >/dev/null 2>&1; then
                log_message "✅ Main repository restored to: $MAIN_REPO_BRANCH"
            else
                log_message "⚠️  WARNING: Failed to restore main repository branch"
            fi
        else
            log_message "✅ Main repository still on original branch: $MAIN_REPO_BRANCH"
        fi
    fi
    
    # Clear the global variable so trap doesn't restore again (already done above)
    MAIN_REPO_BRANCH=""
}

# Run main function
main "$@"
