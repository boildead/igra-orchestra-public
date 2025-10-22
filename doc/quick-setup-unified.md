# IGRA Orchestra Unified Setup — Quick Start

A unified Docker Compose setup that works seamlessly on both local machines and FluxCloud, with automated wallet creation, kaspad sync healthcheck, and backup restoration.

## Prerequisites

- **Docker Engine 23.0+** and **Docker Compose V2+**
- **16GB+ RAM** (recommended for optimal performance)
- **AMD64 or ARM64** architecture
- **Git** access to github.com (for local builds)
- **Domain name** with A record pointing to your server IP (for HTTPS RPC access)

## Quick Start

### 1. Clone and Configure

```bash
git clone https://github.com/your-org/igra-orchestra-public.git
cd igra-orchestra-public
```

### 2. Environment Setup

Create your environment configuration:

```bash
# Generate RPC access tokens automatically
chmod +x scripts/generate-rpc-config.sh
./scripts/generate-rpc-config.sh

# Create basic environment file
cat > .env << EOF
# Network Configuration
NETWORK=testnet
NODE_ID=your-node-name

# Health Check (get from IGRA Discord)
HEALTH_CHECK_API_KEY=your-api-key

# Domain Configuration (for HTTPS)
IGRA_ORCHESTRA_DOMAIN=your-domain.com
IGRA_ORCHESTRA_DOMAIN_EMAIL=your-email@domain.com

# RPC Configuration
RPC_READ_ONLY=false
MIN_PROTOCOL_FEE_PER_GAS_GWEI=1

# Add generated RPC tokens
EOF

# Append generated RPC tokens to .env
cat .env.rpc >> .env
```

**Environment Variables (with defaults):**

All configuration has sensible defaults for testnet demo deployment. Only these are required:

```bash
# Required for demo
NODE_ID=your-node-name
HEALTH_CHECK_API_KEY=your-api-key  # Get from IGRA Discord

# Optional (has defaults)
NETWORK=testnet
S3_BACKUP_BUCKET=igralabs-viaduct-archival-data
S3_BACKUP_REGION=eu-north-1
FORCE_RESTORE_BACKUP=false
RPC_READ_ONLY=false
MIN_PROTOCOL_FEE_PER_GAS_GWEI=1

# Auto-generated (no manual configuration needed)
W0_WALLET_TO_ADDRESS=auto  # Generated automatically
W0_KASWALLET_PASSWORD=     # Empty password (auto-generated)
RPC_ACCESS_TOKEN_1=...     # Generated automatically
RPC_ACCESS_TOKEN_2=...     # Generated automatically
# ... (46 tokens total)
```

### 3. Deploy Everything Automatically 🚀

**Option A: Fully Automated Deployment (Recommended)**

```bash
# One-command deployment with automatic sync orchestration
chmod +x scripts/start-full-deployment.sh
./scripts/start-full-deployment.sh
```

This will:
- ✅ Start kaspad and wait for sync automatically
- ✅ Start backend services when sync completes
- ✅ Start RPC services when backend is ready
- ✅ Generate wallets and configure everything automatically
- ✅ Handle the entire 4-6 hour sync process without manual intervention

**Option B: Manual Step-by-Step Deployment**

#### For Local Development:

```bash
# Initialize repositories (if building from source)
chmod +x setup-repos.sh
./setup-repos.sh --dev

# Generate JWT secret
mkdir -p keys
openssl rand -hex 32 > keys/jwt.hex

# Start Kaspa node and wait for sync
docker compose --profile kaspad up -d

# Monitor sync progress
docker compose logs -f kaspad
# Wait until you see: "Node is fully synced"
```

#### For FluxCloud Deployment:

```bash
# Use pre-built images (no local build required)
export USE_PREBUILT_IMAGES=true

# Start Kaspa node
docker compose --profile kaspad up -d

# Monitor sync progress
docker compose logs -f kaspad
```

### 4. Start Backend Services (Manual Option Only)

After kaspad is fully synced (healthcheck passes):

```bash
# Start backend services
docker compose --profile backend up -d --pull always

# Monitor startup
docker compose logs -f execution-layer block-builder viaduct
```

### 5. Start RPC Services (Manual Option Only)

```bash
# Start RPC with single worker (recommended for demo)
docker compose --profile frontend-w1 up -d --pull always

# Monitor RPC services
docker compose logs -f rpc-provider-0 kaswallet-0
```

## Service Startup Flow

The setup follows a specific startup sequence to ensure proper synchronization:

### Phase 1: Parallel Setup (during kaspad sync)
1. **Kaspad** starts syncing (4-6 hours)
2. **Viaduct** container starts, restores backup from S3, then waits
3. **Kaswallet** containers start, generate wallets if needed, log addresses

### Phase 2: Sequential Backend (after kaspad sync)
4. **Kaspad** healthcheck passes (`isSynced = true`)
5. **Execution-layer** starts (depends on kaspad)
6. **Block-builder** starts (depends on execution-layer)
7. **Viaduct** daemon starts processing (depends on block-builder)

### Phase 3: RPC Services (after backend ready)
8. **RPC-provider** services start (depends on execution-layer + kaswallet)

## Wallet Management

### Automatic Wallet Generation ✅

**Everything is fully automated!** No manual wallet configuration needed:

1. **Wallets generate automatically** when containers start
2. **Wallet addresses are automatically passed** to RPC providers
3. **RPC tokens are generated automatically** 
4. **No manual configuration required**

**Check logs to see generated wallet:**
```bash
docker compose logs kaswallet-0 | grep "Wallet Address"
```

**Example output:**
```
================================================
WALLET GENERATED SUCCESSFULLY
================================================
Wallet Address: kaspatest:qqfrt9vlrpl98m8gwsrw45ynvpgxcrl87x3h2337k8ft4eyhacyqumc0t9vng
Key File: /app/keys.json
Password: (empty)
================================================
Wallet address automatically configured for RPC!
No manual configuration needed.
================================================
```

### Manual Wallet Management (Optional)

Only if you want to use existing wallets:

1. **Generate wallet manually**:
   ```bash
   docker run --rm -v $(pwd)/keys:/keys --entrypoint /app/kaswallet-create \
     igranetwork/kaswallet:latest --testnet -k /keys/keys.kaswallet-0.json
   ```

2. **Set in .env file**:
   ```bash
   W0_WALLET_TO_ADDRESS=kaspatest:your-existing-address
   W0_KASWALLET_PASSWORD=your-password
   ```

## Backup Restoration

Backup restoration happens automatically when viaduct starts:

- **Automatic**: Downloads latest backup from S3 if storage is empty
- **Force**: Set `FORCE_RESTORE_BACKUP=true` to always restore
- **Manual**: Backup is downloaded and extracted before viaduct daemon starts

## RPC Access

### Automatic RPC Configuration ✅

**RPC tokens are generated automatically!** No manual token generation needed:

1. **Run the setup script** (generates tokens automatically)
2. **RPC endpoint becomes available** after services start
3. **Use any of the 46 generated tokens** to access RPC

### Endpoint Format

```bash
# With HTTPS (recommended):
https://your-domain.com:8545/{RPC_ACCESS_TOKEN}

# Without HTTPS:
http://your-server-ip:8545/{RPC_ACCESS_TOKEN}
```

### Get Your RPC Tokens

**Tokens are generated automatically during setup:**
```bash
# View generated tokens
cat .env.rpc

# Or view in .env file
grep "RPC_ACCESS_TOKEN" .env
```

### Test RPC Connection

```bash
# Get a token from .env file
TOKEN=$(grep "RPC_ACCESS_TOKEN_1" .env | cut -d'=' -f2)

# Test connection
curl -X POST https://your-domain.com:8545/$TOKEN \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

## Monitoring and Troubleshooting

### Check Service Health

```bash
# View all services
docker compose ps

# Check sync status
docker compose logs kaspad | grep -E "(synced|IDB:|DAA)"

# Monitor specific service
docker compose logs -f execution-layer
```

### Common Issues

#### Kaspad Not Syncing
```bash
# Check if kaspad is running
docker compose ps kaspad

# Check sync progress
docker compose logs kaspad | tail -20

# Restart if needed
docker compose restart kaspad
```

#### Wallet Generation Failed
```bash
# Check kaswallet logs
docker compose logs kaswallet-0

# Restart kaswallet
docker compose restart kaswallet-0
```

#### Backup Restoration Failed
```bash
# Check viaduct logs
docker compose logs viaduct

# Force backup restoration
FORCE_RESTORE_BACKUP=true docker compose restart viaduct
```

#### RPC Not Responding
```bash
# Check RPC provider logs
docker compose logs rpc-provider-0

# Verify dependencies
docker compose ps execution-layer kaswallet-0
```

## FluxCloud Deployment

### FluxCloud-Specific Configuration

1. **Use pre-built images**:
   ```bash
   export USE_PREBUILT_IMAGES=true
   ```

2. **Set resource limits** (optional):
   ```yaml
   deploy:
     resources:
       limits:
         memory: 8G
         cpus: '4.0'
   ```

3. **Configure domain**:
   ```bash
   IGRA_ORCHESTRA_DOMAIN=your-flux-domain.com
   IGRA_ORCHESTRA_DOMAIN_EMAIL=your-email@domain.com
   ```

4. **Deploy to FluxCloud**:
   - Upload your `docker-compose.yml` to FluxCloud
   - Set environment variables in FluxCloud dashboard
   - Start deployment

### FluxCloud Considerations

- **No local file dependencies**: All keys and scripts are embedded in images
- **Named volumes**: Used for persistent data storage
- **Resource limits**: Configured for optimal FluxCloud performance
- **Network access**: All services use internal Docker networking

## Multiple Workers

To run multiple RPC workers:

```bash
# Start with 3 workers
docker compose --profile frontend-w3 up -d

# Each worker needs its own wallet (auto-generated)
# Check logs for all wallet addresses:
docker compose logs kaswallet-0 kaswallet-1 kaswallet-2 | grep "Wallet Address"
```

## Security Notes

⚠️ **Testnet Only**: This setup is configured for testnet with minimal security considerations:

- Empty wallet passwords
- Testnet network configuration
- Demo/marketing purposes only

For production use, additional security measures would be required.

## Support

- **Discord**: Join IGRA Discord for support and API keys
- **Documentation**: Check `doc/` directory for additional guides
- **Issues**: Report issues on GitHub repository

## Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kaspad        │    │   Viaduct        │    │  Kaswallet-0    │
│   (Sync 4-6h)   │    │   (Backup Restore)│    │  (Auto Generate)│
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                        │
         ▼                        ▼                        ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Execution Layer │◄───┤   Block Builder  │    │   RPC Provider  │
│                 │    │                  │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

**Startup Order**: Kaspad syncs → Backend services start → RPC services start

