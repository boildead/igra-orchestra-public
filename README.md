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

# Generate RPC tokens automatically
./scripts/generate-rpc-config.sh

# Start everything with automatic sync orchestration (recommended)
./scripts/start-full-deployment.sh

# OR manually step by step:
# docker compose --profile kaspad up -d
# # Wait for sync (4-6 hours), then:
# docker compose --profile backend up -d
# docker compose --profile frontend-w1 up -d
```

### FluxCloud Deployment
[![Deploy on FluxCloud](https://img.shields.io/badge/Deploy%20on-FluxCloud-blue)](https://home.runonflux.io)

See [`doc/quick-setup-unified.md`](doc/quick-setup-unified.md) for complete setup instructions.

## Setup Requirements

- **Docker Engine 23.0+** and **Docker Compose V2+**
- **16GB+ RAM** (recommended for optimal performance)
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
