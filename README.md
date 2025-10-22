# IGRA Orchestra Devnet

A unified Docker Compose-based development environment for IGRA Orchestra components that works seamlessly on both local machines and FluxCloud.

## Features

- 🚀 **Unified Setup**: Single configuration for local and FluxCloud deployment
- 🔄 **Automated Wallet Generation**: Wallets created automatically with empty passwords
- 📦 **Backup Restoration**: Automatic S3 backup download and restoration
- 🔍 **Sync Healthcheck**: Kaspad sync status monitoring via RPC API
- 🌐 **FluxCloud Compatible**: Ready for deployment on FluxCloud

## Quick Start

### Local Deployment
```bash
git clone https://github.com/your-org/igra-orchestra-public.git
cd igra-orchestra-public

# One-command deployment (handles everything automatically)
./scripts/start-full-deployment.sh
```

**Interactive Setup:**
The script will guide you through configuration with prompts for:
- Domain name (for HTTPS RPC access)
- Email (for SSL certificates)
- Node ID (unique identifier for your node)
- Health check API key (from IGRA Discord)
- Wallet password (primary wallet only)

**What gets auto-generated:**
- ✅ RPC access tokens (46 tokens)
- ✅ JWT secrets
- ✅ Wallet address
- ✅ All configuration with sensible defaults
- ✅ No manual file editing required!

**Monitor Progress:**
```bash
# Check deployment status
./scripts/check-status.sh

# View orchestrator logs
docker compose -f docker-compose.full.yml logs -f sync-orchestrator
```

See [`doc/quick-setup-unified.md`](doc/quick-setup-unified.md) for complete setup instructions.

## Setup Requirements

- **Docker Engine 23.0+** and **Docker Compose V2+**
- **16GB+ RAM** (recommended for optimal performance)
- **20GB+ Disk Space** (logs auto-rotate at 100MB per container, max 200MB total)
- **AMD64 or ARM64** architecture
- **Git** access (for local builds)
- **Domain name** (for HTTPS RPC access)

## Documentation Cover

- [`doc/quick-setup-unified.md`](doc/quick-setup-unified.md) - **Unified setup for local and FluxCloud**
- [`doc/quick-setup-prebuilt.md`](doc/quick-setup-prebuilt.md) - Legacy prebuilt setup
- [`doc/quick-setup-rpc.md`](doc/quick-setup-rpc.md) - RPC configuration details

## Architecture

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

**Startup Flow**: Kaspad syncs → Backend services start → RPC services start
