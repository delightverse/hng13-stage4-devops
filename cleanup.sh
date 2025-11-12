#!/bin/bash
#
# Complete Cleanup Script
# Removes all VPC resources and resets the system
#

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              VPC CLEANUP SCRIPT                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: Please run with sudo"
    echo "   sudo ./cleanup.sh"
    exit 1
fi

echo "⚠️  WARNING: This will delete ALL VPC resources!"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cleanup cancelled"
    exit 0
fi

echo ""
echo "🧹 Starting cleanup..."
echo ""

# Step 1: Use vpcctl to delete all VPCs
echo "📦 Deleting all VPCs via vpcctl..."
if [ -f "./vpcctl" ]; then
    ./vpcctl cleanup-all 2>/dev/null || true
fi

# Step 2: Kill any running web servers
echo "🔌 Stopping web servers..."
pkill -f "python3 -m http.server" 2>/dev/null || true

# Step 3: Manual cleanup of any remaining namespaces
echo "🗑️  Cleaning up namespaces..."
for ns in $(ip netns list 2>/dev/null | grep "ns-" | awk '{print $1}'); do
    echo "  Deleting namespace: $ns"
    ip netns del "$ns" 2>/dev/null || true
done

# Step 4: Clean up bridges
echo "🌉 Cleaning up bridges..."
for br in $(ip link show type bridge 2>/dev/null | grep "br-" | awk -F: '{print $2}' | tr -d ' '); do
    echo "  Deleting bridge: $br"
    ip link set "$br" down 2>/dev/null || true
    ip link del "$br" 2>/dev/null || true
done

# Step 5: Clean up veth pairs
echo "🔗 Cleaning up veth pairs..."
for veth in $(ip link show type veth 2>/dev/null | grep -E "(veth-|peer-)" | awk -F: '{print $2}' | tr -d ' '); do
    echo "  Deleting veth: $veth"
    ip link del "$veth" 2>/dev/null || true
done

# Step 6: Clean up iptables NAT rules
echo "🔥 Cleaning up iptables NAT rules..."
# Flush NAT table
iptables -t nat -F 2>/dev/null || true
# Flush FORWARD chain
iptables -F FORWARD 2>/dev/null || true
# Set default FORWARD policy to ACCEPT
iptables -P FORWARD ACCEPT 2>/dev/null || true

# Step 7: Clean up state and log files
echo "📁 Cleaning up state files..."
if [ -d "$HOME/.vpcctl" ]; then
    echo "  Removing state directory: $HOME/.vpcctl"
    rm -rf "$HOME/.vpcctl/vpc_state.json"
fi

# Step 8: Remove temporary files
echo "🗂️  Cleaning up temporary files..."
rm -rf /tmp/vpcctl_* 2>/dev/null || true
rm -f /tmp/test_policy.json 2>/dev/null || true

# Step 9: Verify cleanup
echo ""
echo "✅ Verifying cleanup..."

remaining_ns=$(ip netns list 2>/dev/null | grep -c "ns-" || echo "0")
remaining_br=$(ip link show type bridge 2>/dev/null | grep -c "br-" || echo "0")
remaining_veth=$(ip link show type veth 2>/dev/null | grep -cE "(veth-|peer-)" || echo "0")

echo "  Remaining namespaces: $remaining_ns"
echo "  Remaining bridges: $remaining_br"
echo "  Remaining veth pairs: $remaining_veth"

echo ""
if [ "$remaining_ns" == "0" ] && [ "$remaining_br" == "0" ] && [ "$remaining_veth" == "0" ]; then
    echo "✅ Cleanup complete! System is clean."
else
    echo "⚠️  Some resources may still exist. Manual cleanup may be needed."
    if [ "$remaining_ns" != "0" ]; then
        echo "  Namespaces:"
        ip netns list | grep "ns-"
    fi
    if [ "$remaining_br" != "0" ]; then
        echo "  Bridges:"
        ip link show type bridge | grep "br-"
    fi
    if [ "$remaining_veth" != "0" ]; then
        echo "  Veth pairs:"
        ip link show type veth | grep -E "(veth-|peer-)"
    fi
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              🎉 CLEANUP FINISHED                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
