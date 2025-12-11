#!/bin/bash
# Cleanup script - removes all IGRA Orchestra deployment artifacts
# Use this to start fresh

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   🧹 IGRA ORCHESTRA - CLEANUP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  This will remove:"
echo "  - All running containers"
echo "  - All Docker volumes (kaspad data, wallet keys, etc.)"
echo "  - Local Docker images (kaspad, kaswallet, viaduct)"
echo "  - Generated configuration files (.env, keys/)"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo "▶ Stopping and removing containers..."
if docker compose -f docker-compose.full.yml down --remove-orphans 2>/dev/null; then
    echo "  ✅ Containers stopped and removed"
else
    echo "  ℹ️  No containers to remove"
fi

echo ""
echo "▶ Removing Docker volumes..."
docker volume ls | grep 'igra-orchestra-public\|kaswallet\|kaspad\|execution-layer\|viaduct\|block-builder' | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true
echo "  ✅ Volumes removed"

echo ""
echo "▶ Removing local Docker images..."
docker rmi kaspad 2>/dev/null || true
docker rmi kaswallet:latest 2>/dev/null || true
docker rmi viaduct:latest 2>/dev/null || true
echo "  ✅ Local images removed"

echo ""
echo "▶ Removing generated configuration..."
if [[ -f ".env" ]]; then
    rm .env
    echo "  ✅ .env removed"
fi

if [[ -d "keys" ]]; then
    rm -rf keys
    echo "  ✅ keys/ directory removed"
fi

if [[ -d "build/repos/rusty-kaspa" ]]; then
    rm -rf build/repos/rusty-kaspa
    echo "  ✅ rusty-kaspa repository removed"
fi

if [[ -d "build/repos/kaswallet" ]]; then
    rm -rf build/repos/kaswallet
    echo "  ✅ kaswallet repository removed"
fi

if [[ -d "build/repos/viaduct" ]]; then
    rm -rf build/repos/viaduct
    echo "  ✅ viaduct repository removed"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   ✅ CLEANUP COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "You can now start fresh with:"
echo "  ./scripts/start-full-deployment.sh"
echo ""

