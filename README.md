# IGRA Orchestra Devnet

A unified Docker Compose-based development environment for IGRA Orchestra components that works seamlessly on both local machines and FluxCloud.

## Features

- 🚀 **Unified Setup**: Single configuration for local and FluxCloud deployment
- 🔄 **Automated Wallet Generation**: Wallets created automatically with empty passwords
- 📦 **Backup Restoration**: Automatic S3 backup download and restoration
- 🔍 **Sync Healthcheck**: Kaspad sync status monitoring via RPC API
- 🌐 **FluxCloud Compatible**: Ready for deployment on FluxCloud

## Setup Requirements

- **Docker Engine 23.0+** and **Docker Compose V2+**
- **16GB+ RAM** (recommended for optimal performance)
- **20GB+ Disk Space** (logs auto-rotate at 100MB per container, max 200MB total)
- **AMD64 or ARM64** architecture
- **Git** access (for local builds)
- **Domain name** (for HTTPS RPC access)
- **OpenSSL** (for generating RPC keys)

## Quick Start

### Automatic Deployment (Recommended)
One command handles everything - builds kaspad from source (first time only) and uses prebuilt images for other services.

```bash
git clone https://github.com/your-org/igra-orchestra-public.git
cd igra-orchestra-public

# One-command deployment (handles everything automatically)
chmod +x scripts/start-full-deployment.sh
./scripts/start-full-deployment.sh
```

**Note:** First run will build kaspad from source (~10-15 minutes). Subsequent runs skip this step.

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

## Documentation Cover

- [`doc/quick-setup-unified.md`](doc/quick-setup-unified.md) - **Unified setup for local**
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
