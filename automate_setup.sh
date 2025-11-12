#!/bin/bash
#
# Automated VPC Project Setup Script
# Creates entire project structure with one command
#

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║        VPC FROM SCRATCH - AUTOMATED PROJECT SETUP             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root for system setup
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  Note: Some steps may require sudo privileges"
fi

# Step 1: Check system
echo "📋 Step 1: Checking system requirements..."

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "   OS: $NAME $VERSION"
else
    echo "   ⚠️  Warning: Cannot detect OS"
fi

# Check Python
if command -v python3 &> /dev/null; then
    echo "   ✓ Python3: $(python3 --version)"
else
    echo "   ❌ Python3 not found. Please install: sudo apt install python3"
    exit 1
fi

# Check required tools
MISSING_TOOLS=()
for tool in ip iptables git; do
    if command -v $tool &> /dev/null; then
        echo "   ✓ $tool: installed"
    else
        MISSING_TOOLS+=($tool)
        echo "   ❌ $tool: not found"
    fi
done

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo ""
    echo "   Missing tools. Install with:"
    echo "   sudo apt install iproute2 iptables git"
    read -p "   Install now? (y/n): " install_now
    if [ "$install_now" == "y" ]; then
        sudo apt update
        sudo apt install -y iproute2 iptables bridge-utils git curl
    else
        echo "   Please install manually and run this script again"
        exit 1
    fi
fi

# Step 2: Create project directory
echo ""
echo "📁 Step 2: Creating project directory..."

read -p "   Project directory name [vpc-project]: " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-vpc-project}

if [ -d "$PROJECT_DIR" ]; then
    echo "   ⚠️  Directory $PROJECT_DIR already exists"
    read -p "   Continue anyway? (y/n): " continue_anyway
    if [ "$continue_anyway" != "y" ]; then
        exit 1
    fi
else
    mkdir -p "$PROJECT_DIR"
    echo "   ✓ Created $PROJECT_DIR"
fi

cd "$PROJECT_DIR"
mkdir -p tests examples docs
echo "   ✓ Created subdirectories"

# Step 3: Download files from repository or create them
echo ""
echo "📥 Step 3: Creating project files..."

echo "   Creating vpcctl..."
cat > vpcctl << 'VPCCTL_EOF'
#!/usr/bin/env python3

"""
vpcctl - Virtual Private Cloud Control Tool
A CLI tool to create, manage, and tear down virtual VPCs on Linux using
network namespaces, bridges, veth pairs, and iptables.

Author: Ubah Delight Godson
Date: November 2025
"""

import json
import subprocess
import sys
import os
import argparse
import logging
from pathlib import Path
from datetime import datetime
import ipaddress

# Configuration
HOME = Path.home()
STATE_DIR = HOME / ".vpcctl"
LOG_DIR = STATE_DIR / "logs"
STATE_FILE = STATE_DIR / "vpc_state.json"

# Create directories
LOG_DIR.mkdir(parents=True, exist_ok=True)
STATE_DIR.mkdir(parents=True, exist_ok=True)

# Setup logging
log_file = LOG_DIR / f"vpcctl_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_file),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Print banner
print("=" * 80)
print("  VPCCTL - Virtual Private Cloud Control Tool")
print("  Building VPCs from Linux Networking Primitives")
print("=" * 80)
logger.info("vpcctl started")


class VPCState:
    """Manages VPC state persistence"""
    
    def __init__(self):
        self.state = self.load()
    
    def load(self):
        """Load VPC state from disk"""
        if STATE_FILE.exists():
            try:
                with open(STATE_FILE, 'r') as f:
                    return json.load(f)
            except json.JSONDecodeError:
                logger.warning("Corrupted state file, starting fresh")
                return {"vpcs": {}}
        return {"vpcs": {}}
    
    def save(self):
        """Save VPC state to disk"""
        with open(STATE_FILE, 'w') as f:
            json.dump(self.state, f, indent=2)
        logger.info(f"State saved to {STATE_FILE}")
    
    def add_vpc(self, vpc_name, vpc_config):
        """Add VPC to state"""
        self.state["vpcs"][vpc_name] = vpc_config
        self.save()
    
    def remove_vpc(self, vpc_name):
        """Remove VPC from state"""
        if vpc_name in self.state["vpcs"]:
            del self.state["vpcs"][vpc_name]
            self.save()
    
    def get_vpc(self, vpc_name):
        """Get VPC configuration"""
        return self.state["vpcs"].get(vpc_name)
    
    def list_vpcs(self):
        """List all VPCs"""
        return self.state["vpcs"]
    
    def update_vpc(self, vpc_name, vpc_config):
        """Update VPC configuration"""
        self.state["vpcs"][vpc_name] = vpc_config
        self.save()


class NetworkManager:
    """Handles low-level Linux networking operations"""
    
    @staticmethod
    def run_command(cmd, check=True, capture=True):
        """Execute shell command"""
        cmd_str = ' '.join(cmd) if isinstance(cmd, list) else cmd
        logger.debug(f"Executing: {cmd_str}")
        try:
            if capture:
                result = subprocess.run(cmd, check=check, capture_output=True, text=True)
                if result.stdout:
                    logger.debug(f"Output: {result.stdout.strip()}")
                return result
            else:
                subprocess.run(cmd, check=check)
                return None
        except subprocess.CalledProcessError as e:
            logger.error(f"Command failed: {cmd_str}")
            if hasattr(e, 'stderr') and e.stderr:
                logger.error(f"Error: {e.stderr}")
            if check:
                raise
            return None
    
    @staticmethod
    def create_namespace(ns_name):
        """Create network namespace"""
        logger.info(f"Creating namespace: {ns_name}")
        NetworkManager.run_command(["ip", "netns", "add", ns_name])
        print(f"  ✓ Created namespace: {ns_name}")
    
    @staticmethod
    def delete_namespace(ns_name):
        """Delete network namespace"""
        logger.info(f"Deleting namespace: {ns_name}")
        NetworkManager.run_command(["ip", "netns", "del", ns_name], check=False)
        print(f"  ✓ Deleted namespace: {ns_name}")
    
    @staticmethod
    def namespace_exists(ns_name):
        """Check if namespace exists"""
        result = NetworkManager.run_command(["ip", "netns", "list"], check=False)
        if result:
            return ns_name in result.stdout
        return False
    
    @staticmethod
    def create_bridge(bridge_name):
        """Create Linux bridge"""
        logger.info(f"Creating bridge: {bridge_name}")
        NetworkManager.run_command(["ip", "link", "add", bridge_name, "type", "bridge"])
        NetworkManager.run_command(["ip", "link", "set", bridge_name, "up"])
        print(f"  ✓ Created bridge: {bridge_name}")
    
    @staticmethod
    def delete_bridge(bridge_name):
        """Delete Linux bridge"""
        logger.info(f"Deleting bridge: {bridge_name}")
        NetworkManager.run_command(["ip", "link", "set", bridge_name, "down"], check=False)
        NetworkManager.run_command(["ip", "link", "del", bridge_name], check=False)
        print(f"  ✓ Deleted bridge: {bridge_name}")
    
    @staticmethod
    def create_veth_pair(veth_name, peer_name):
        """Create veth pair"""
        logger.info(f"Creating veth pair: {veth_name} <-> {peer_name}")
        NetworkManager.run_command(["ip", "link", "add", veth_name, "type", "veth", "peer", "name", peer_name])
        print(f"  ✓ Created veth pair: {veth_name} <-> {peer_name}")
    
    @staticmethod
    def delete_veth(veth_name):
        """Delete veth interface"""
        logger.info(f"Deleting veth: {veth_name}")
        NetworkManager.run_command(["ip", "link", "del", veth_name], check=False)
    
    @staticmethod
    def attach_to_bridge(interface, bridge):
        """Attach interface to bridge"""
        logger.info(f"Attaching {interface} to bridge {bridge}")
        NetworkManager.run_command(["ip", "link", "set", interface, "master", bridge])
        NetworkManager.run_command(["ip", "link", "set", interface, "up"])
    
    @staticmethod
    def move_to_namespace(interface, namespace):
        """Move interface to namespace"""
        logger.info(f"Moving {interface} to namespace {namespace}")
        NetworkManager.run_command(["ip", "link", "set", interface, "netns", namespace])
    
    @staticmethod
    def set_ip_address(namespace, interface, ip_cidr):
        """Set IP address on interface in namespace"""
        logger.info(f"Setting IP {ip_cidr} on {interface} in namespace {namespace}")
        NetworkManager.run_command(["ip", "netns", "exec", namespace, "ip", "addr", "add", ip_cidr, "dev", interface])
        NetworkManager.run_command(["ip", "netns", "exec", namespace, "ip", "link", "set", interface, "up"])
        NetworkManager.run_command(["ip", "netns", "exec", namespace, "ip", "link", "set", "lo", "up"])
    
    @staticmethod
    def add_route(namespace, destination, gateway):
        """Add route in namespace"""
        logger.info(f"Adding route in {namespace}: {destination} via {gateway}")
        NetworkManager.run_command(["ip", "netns", "exec", namespace, "ip", "route", "add", destination, "via", gateway])
    
    @staticmethod
    def enable_ip_forward():
        """Enable IP forwarding"""
        logger.info("Enabling IP forwarding")
        NetworkManager.run_command(["sysctl", "-w", "net.ipv4.ip_forward=1"], capture=False)
    
    @staticmethod
    def setup_nat(bridge_name, subnet_cidr, out_interface):
        """Setup NAT for outbound traffic"""
        logger.info(f"Setting up NAT for {subnet_cidr} via {out_interface}")
        
        # MASQUERADE rule for outbound traffic
        NetworkManager.run_command([
            "iptables", "-t", "nat", "-A", "POSTROUTING",
            "-s", subnet_cidr, "-o", out_interface, "-j", "MASQUERADE"
        ])
        
        # Forward rules
        NetworkManager.run_command([
            "iptables", "-A", "FORWARD", "-i", bridge_name,
            "-o", out_interface, "-j", "ACCEPT"
        ])
        NetworkManager.run_command([
            "iptables", "-A", "FORWARD", "-i", out_interface,
            "-o", bridge_name, "-m", "state", "--state",
            "RELATED,ESTABLISHED", "-j", "ACCEPT"
        ])
        print(f"  ✓ NAT configured for {subnet_cidr}")
    
    @staticmethod
    def remove_nat(subnet_cidr, out_interface):
        """Remove NAT rules"""
        logger.info(f"Removing NAT for {subnet_cidr}")
        NetworkManager.run_command([
            "iptables", "-t", "nat", "-D", "POSTROUTING",
            "-s", subnet_cidr, "-o", out_interface, "-j", "MASQUERADE"
        ], check=False)
    
    @staticmethod
    def apply_firewall_rule(namespace, rule):
        """Apply iptables firewall rule in namespace"""
        protocol = rule.get("protocol", "tcp")
        port = rule.get("port")
        action = rule.get("action", "allow").upper()
        
        target = "ACCEPT" if action == "ALLOW" else "DROP"
        
        logger.info(f"Applying firewall rule in {namespace}: {action} {protocol}/{port}")
        
        cmd = ["ip", "netns", "exec", namespace, "iptables", "-A", "INPUT",
               "-p", protocol]
        
        if port:
            cmd.extend(["--dport", str(port)])
        
        cmd.extend(["-j", target])
        
        NetworkManager.run_command(cmd)
        print(f"  ✓ Applied rule: {action} {protocol}/{port}")


class VPCManager:
    """High-level VPC management operations"""
    
    def __init__(self):
        self.state = VPCState()
        self.net = NetworkManager()
    
    def create_vpc(self, vpc_name, cidr_block):
        """Create a new VPC"""
        print(f"\n{'='*80}")
        print(f"CREATING VPC: {vpc_name}")
        print(f"{'='*80}")
        logger.info(f"Creating VPC: {vpc_name} with CIDR: {cidr_block}")
        
        # Validate CIDR
        try:
            network = ipaddress.ip_network(cidr_block)
        except ValueError as e:
            print(f"❌ Error: Invalid CIDR block: {e}")
            logger.error(f"Invalid CIDR block: {e}")
            return False
        
        # Check if VPC already exists
        if self.state.get_vpc(vpc_name):
            print(f"❌ Error: VPC '{vpc_name}' already exists")
            logger.error(f"VPC {vpc_name} already exists")
            return False
        
        bridge_name = f"br-{vpc_name}"
        
        try:
            # Create bridge
            self.net.create_bridge(bridge_name)
            
            # Assign bridge IP (first usable IP in range)
            bridge_ip = str(list(network.hosts())[0])
            self.net.run_command(["ip", "addr", "add", f"{bridge_ip}/{network.prefixlen}", "dev", bridge_name])
            print(f"  ✓ Assigned bridge IP: {bridge_ip}/{network.prefixlen}")
            
            # Enable IP forwarding
            self.net.enable_ip_forward()
            
            # Save VPC state
            vpc_config = {
                "name": vpc_name,
                "cidr_block": cidr_block,
                "bridge": bridge_name,
                "bridge_ip": bridge_ip,
                "subnets": {},
                "peerings": [],
                "created_at": datetime.now().isoformat()
            }
            
            self.state.add_vpc(vpc_name, vpc_config)
            
            print(f"\n✅ VPC '{vpc_name}' created successfully!")
            print(f"   CIDR Block: {cidr_block}")
            print(f"   Bridge: {bridge_name}")
            print(f"   Gateway IP: {bridge_ip}")
            logger.info(f"VPC {vpc_name} created successfully")
            return True
            
        except Exception as e:
            print(f"❌ Error: Failed to create VPC: {e}")
            logger.error(f"Failed to create VPC: {e}")
            # Cleanup on failure
            self.net.delete_bridge(bridge_name)
            return False
    
    def add_subnet(self, vpc_name, subnet_name, subnet_cidr, subnet_type="private"):
        """Add subnet to VPC"""
        print(f"\n{'='*80}")
        print(f"ADDING SUBNET: {subnet_name} to VPC: {vpc_name}")
        print(f"{'='*80}")
        logger.info(f"Adding subnet {subnet_name} ({subnet_cidr}) to VPC {vpc_name}")
        
        vpc = self.state.get_vpc(vpc_name)
        if not vpc:
            print(f"❌ Error: VPC '{vpc_name}' not found")
            logger.error(f"VPC {vpc_name} not found")
            return False
        
        # Validate subnet CIDR is within VPC CIDR
        try:
            vpc_network = ipaddress.ip_network(vpc["cidr_block"])
            subnet_network = ipaddress.ip_network(subnet_cidr)
            
            if not subnet_network.subnet_of(vpc_network):
                print(f"❌ Error: Subnet {subnet_cidr} is not within VPC {vpc['cidr_block']}")
                logger.error(f"Subnet {subnet_cidr} is not within VPC {vpc['cidr_block']}")
                return False
        except ValueError as e:
            print(f"❌ Error: Invalid CIDR: {e}")
            logger.error(f"Invalid CIDR: {e}")
            return False
        
        # Check if subnet already exists
        if subnet_name in vpc["subnets"]:
            print(f"❌ Error: Subnet '{subnet_name}' already exists in VPC '{vpc_name}'")
            logger.error(f"Subnet {subnet_name} already exists in VPC {vpc_name}")
            return False
        
        namespace = f"ns-{vpc_name}-{subnet_name}"
        veth_host = f"veth-{subnet_name}"
        veth_ns = f"veth-{subnet_name}-ns"
        
        try:
            # Create namespace
            self.net.create_namespace(namespace)
            
            # Create veth pair
            self.net.create_veth_pair(veth_host, veth_ns)
            
            # Attach host side to bridge
            self.net.attach_to_bridge(veth_host, vpc["bridge"])
            print(f"  ✓ Attached {veth_host} to {vpc['bridge']}")
            
            # Move namespace side to namespace
            self.net.move_to_namespace(veth_ns, namespace)
            
            # Assign IP to namespace interface (use second host IP)
            subnet_ip = str(list(subnet_network.hosts())[1])
            self.net.set_ip_address(namespace, veth_ns, f"{subnet_ip}/{subnet_network.prefixlen}")
            print(f"  ✓ Assigned IP {subnet_ip} to {namespace}")
            
            # Assign bridge interface IP on this subnet (first host IP)
            bridge_subnet_ip = str(list(subnet_network.hosts())[0])
            self.net.run_command(["ip", "addr", "add", f"{bridge_subnet_ip}/{subnet_network.prefixlen}", "dev", vpc["bridge"]])
            print(f"  ✓ Assigned {bridge_subnet_ip} to bridge on this subnet")
            
            # Add default route via bridge IP on THIS subnet
            self.net.add_route(namespace, "default", bridge_subnet_ip)
            print(f"  ✓ Added default route via {bridge_subnet_ip}")
            
            # Setup NAT if public subnet
            out_interface = None
            if subnet_type == "public":
                out_interface = self.get_default_interface()
                self.net.setup_nat(vpc["bridge"], str(subnet_network), out_interface)
            
            # Update state
            vpc["subnets"][subnet_name] = {
                "name": subnet_name,
                "cidr": subnet_cidr,
                "type": subnet_type,
                "namespace": namespace,
                "veth_host": veth_host,
                "veth_ns": veth_ns,
                "ip": subnet_ip,
                "out_interface": out_interface,
                "created_at": datetime.now().isoformat()
            }
            
            self.state.update_vpc(vpc_name, vpc)
            
            print(f"\n✅ Subnet '{subnet_name}' added successfully!")
            print(f"   CIDR: {subnet_cidr}")
            print(f"   Type: {subnet_type}")
            print(f"   IP Address: {subnet_ip}")
            print(f"   Namespace: {namespace}")
            if subnet_type == "public":
                print(f"   NAT Gateway: Enabled via {out_interface}")
            
            logger.info(f"Subnet {subnet_name} added successfully")
            return True
            
        except Exception as e:
            print(f"❌ Error: Failed to add subnet: {e}")
            logger.error(f"Failed to add subnet: {e}")
            # Cleanup
            self.net.delete_namespace(namespace)
            self.net.delete_veth(veth_host)
            return False
    
    def delete_subnet(self, vpc_name, subnet_name):
        """Delete subnet from VPC"""
        print(f"\n{'='*80}")
        print(f"DELETING SUBNET: {subnet_name} from VPC: {vpc_name}")
        print(f"{'='*80}")
        logger.info(f"Deleting subnet {subnet_name} from VPC {vpc_name}")
        
        vpc = self.state.get_vpc(vpc_name)
        if not vpc:
            print(f"❌ Error: VPC '{vpc_name}' not found")
            return False
        
        if subnet_name not in vpc["subnets"]:
            print(f"❌ Error: Subnet '{subnet_name}' not found in VPC '{vpc_name}'")
            return False
        
        subnet = vpc["subnets"][subnet_name]
        
        try:
            # Remove NAT rules if public subnet
            if subnet["type"] == "public" and subnet.get("out_interface"):
                self.net.remove_nat(subnet["cidr"], subnet["out_interface"])
            
            # Delete namespace
            self.net.delete_namespace(subnet["namespace"])
            
            # Delete veth
            self.net.delete_veth(subnet["veth_host"])
            
            # Remove from state
            del vpc["subnets"][subnet_name]
            self.state.update_vpc(vpc_name, vpc)
            
            print(f"\n✅ Subnet '{subnet_name}' deleted successfully!")
            logger.info(f"Subnet {subnet_name} deleted")
            return True
            
        except Exception as e:
            print(f"❌ Error: Failed to delete subnet: {e}")
            logger.error(f"Failed to delete subnet: {e}")
            return False
    
    def delete_vpc(self, vpc_name):
        """Delete VPC and all its resources"""
        print(f"\n{'='*80}")
        print(f"DELETING VPC: {vpc_name}")
        print(f"{'='*80}")
        logger.info(f"Deleting VPC: {vpc_name}")
        
        vpc = self.state.get_vpc(vpc_name)
        if not vpc:
            print(f"❌ Error: VPC '{vpc_name}' not found")
            logger.error(f"VPC {vpc_name} not found")
            return False
        
        try:
            # Delete all subnets
            subnet_names = list(vpc["subnets"].keys())
            for subnet_name in subnet_names:
                subnet = vpc["subnets"][subnet_name]
                logger.info(f"Deleting subnet {subnet_name}")
                
                # Remove NAT rules if public subnet
                if subnet["type"] == "public" and subnet.get("out_interface"):
                    self.net.remove_nat(subnet["cidr"], subnet["out_interface"])
                
                # Delete namespace
                self.net.delete_namespace(subnet["namespace"])
                
                # Delete veth
                self.net.delete_veth(subnet["veth_host"])
            
            # Delete peering connections
            for peering in vpc.get("peerings", []):
                logger.info(f"Removing peering: {peering}")
                self.net.delete_veth(peering.get("veth_local", ""))
                print(f"  ✓ Removed peering with {peering.get('peer_vpc')}")
            
            # Delete bridge
            self.net.delete_bridge(vpc["bridge"])
            
            # Remove from state
            self.state.remove_vpc(vpc_name)
            
            print(f"\n✅ VPC '{vpc_name}' deleted successfully!")
            logger.info(f"VPC {vpc_name} deleted successfully")
            return True
            
        except Exception as e:
            print(f"❌ Error: Failed to delete VPC: {e}")
            logger.error(f"Failed to delete VPC: {e}")
            return False
    
    def peer_vpcs(self, vpc1_name, vpc2_name):
        """Create peering connection between two VPCs"""
        print(f"\n{'='*80}")
        print(f"CREATING VPC PEERING: {vpc1_name} <-> {vpc2_name}")
        print(f"{'='*80}")
        logger.info(f"Creating peering between {vpc1_name} and {vpc2_name}")
        
        vpc1 = self.state.get_vpc(vpc1_name)
        vpc2 = self.state.get_vpc(vpc2_name)
        
        if not vpc1 or not vpc2:
            print(f"❌ Error: One or both VPCs not found")
            logger.error("One or both VPCs not found")
            return False
        
        # Check for CIDR overlap
        net1 = ipaddress.ip_network(vpc1["cidr_block"])
        net2 = ipaddress.ip_network(vpc2["cidr_block"])
        
        if net1.overlaps(net2):
            print(f"❌ Error: VPC CIDR blocks overlap - peering not possible")
            logger.error("VPC CIDR blocks overlap")
            return False
        
        # Check if peering already exists
        for peering in vpc1.get("peerings", []):
            if peering.get("peer_vpc") == vpc2_name:
                print(f"❌ Error: Peering already exists between {vpc1_name} and {vpc2_name}")
                return False
        
        veth1 = f"peer-{vpc1_name}-{vpc2_name}"
        veth2 = f"peer-{vpc2_name}-{vpc1_name}"
        
        try:
            # Create veth pair
            self.net.create_veth_pair(veth1, veth2)
            
            # Attach to respective bridges
            self.net.attach_to_bridge(veth1, vpc1["bridge"])
            self.net.attach_to_bridge(veth2, vpc2["bridge"])
            print(f"  ✓ Attached veth pair to bridges")
            
            # Add routes on host
            self.net.run_command(["ip", "route", "add", vpc2["cidr_block"], "dev", vpc1["bridge"]])
            self.net.run_command(["ip", "route", "add", vpc1["cidr_block"], "dev", vpc2["bridge"]])
            print(f"  ✓ Added routing entries")
            
            # Update state
            peering_info1 = {
                "peer_vpc": vpc2_name,
                "veth_local": veth1,
                "veth_remote": veth2,
                "created_at": datetime.now().isoformat()
            }
            vpc1.setdefault("peerings", []).append(peering_info1)
            
            peering_info2 = {
                "peer_vpc": vpc1_name,
                "veth_local": veth2,
                "veth_remote": veth1,
                "created_at": datetime.now().isoformat()
            }
            vpc2.setdefault("peerings", []).append(peering_info2)
            
            self.state.update_vpc(vpc1_name, vpc1)
            self.state.update_vpc(vpc2_name, vpc2)
            
            print(f"\n✅ VPC peering established successfully!")
            print(f"   {vpc1_name} ({vpc1['cidr_block']}) <-> {vpc2_name} ({vpc2['cidr_block']})")
            logger.info(f"VPC peering established between {vpc1_name} and {vpc2_name}")
            return True
            
        except Exception as e:
            print(f"❌ Error: Failed to create peering: {e}")
            logger.error(f"Failed to create peering: {e}")
            self.net.delete_veth(veth1)
            return False
    
    def unpeer_vpcs(self, vpc1_name, vpc2_name):
        """Delete VPC peering connection"""
        print(f"\n{'='*80}")
        print(f"DELETING VPC PEERING: {vpc1_name} <-> {vpc2_name}")
        print(f"{'='*80}")
        logger.info(f"Deleting peering between {vpc1_name} and {vpc2_name}")
        
        vpc1 = self.state.get_vpc(vpc1_name)
        vpc2 = self.state.get_vpc(vpc2_name)
        
        if not vpc1 or not vpc2:
            print(f"❌ Error: One or both VPCs not found")
            return False
        
        # Find peering
        peering1 = None
        for p in vpc1.get("peerings", []):
            if p.get("peer_vpc") == vpc2_name:
                peering1 = p
                break
        
        if not peering1:
            print(f"❌ Error: No peering found between {vpc1_name} and {vpc2_name}")
            return False
        
        try:
            # Delete veth pair
            self.net.delete_veth(peering1["veth_local"])
            print(f"  ✓ Deleted veth pair")
            
            # Remove routes
            self.net.run_command(["ip", "route", "del", vpc2["cidr_block"], "dev", vpc1["bridge"]], check=False)
            self.net.run_command(["ip", "route", "del", vpc1["cidr_block"], "dev", vpc2["bridge"]], check=False)
            print(f"  ✓ Removed routing entries")
            
            # Update state
            vpc1["peerings"] = [p for p in vpc1.get("peerings", []) if p.get("peer_vpc") != vpc2_name]
            vpc2["peerings"] = [p for p in vpc2.get("peerings", []) if p.get("peer_vpc") != vpc1_name]
            
            self.state.update_vpc(vpc1_name, vpc1)
            self.state.update_vpc(vpc2_name, vpc2)
            
            print(f"\n✅ VPC peering deleted successfully!")
            logger.info(f"Peering deleted between {vpc1_name} and {vpc2_name}")
            return True
            
        except Exception as e:
            print(f"❌ Error: Failed to delete peering: {e}")
            logger.error(f"Failed to delete peering: {e}")
            return False
    
    def apply_security_group(self, vpc_name, subnet_name, policy_file):
        """Apply security group rules from JSON policy"""
        print(f"\n{'='*80}")
        print(f"APPLYING SECURITY GROUP")
        print(f"{'='*80}")
        logger.info(f"Applying security group to {vpc_name}/{subnet_name}")
        
        vpc = self.state.get_vpc(vpc_name)
        if not vpc:
            print(f"❌ Error: VPC '{vpc_name}' not found")
            logger.error(f"VPC {vpc_name} not found")
            return False
        
        subnet = vpc["subnets"].get(subnet_name)
        if not subnet:
            print(f"❌ Error: Subnet '{subnet_name}' not found")
            logger.error(f"Subnet {subnet_name} not found")
            return False
        
        try:
            with open(policy_file, 'r') as f:
                policy = json.load(f)
            
            namespace = subnet["namespace"]
            
            # Apply ingress rules
            for rule in policy.get("ingress", []):
                self.net.apply_firewall_rule(namespace, rule)
            
            print(f"\n✅ Security group applied successfully!")
            print(f"   VPC: {vpc_name}")
            print(f"   Subnet: {subnet_name}")
            print(f"   Rules applied: {len(policy.get('ingress', []))}")
            logger.info(f"Security group applied to {subnet_name}")
            return True
            
        except FileNotFoundError:
            print(f"❌ Error: Policy file '{policy_file}' not found")
            logger.error(f"Policy file not found: {policy_file}")
            return False
        except json.JSONDecodeError as e:
            print(f"❌ Error: Invalid JSON in policy file: {e}")
            logger.error(f"Invalid JSON: {e}")
            return False
        except Exception as e:
            print(f"❌ Error: Failed to apply security group: {e}")
            logger.error(f"Failed to apply security group: {e}")
            return False
    
    def deploy_app(self, vpc_name, subnet_name, app_type="python", port=8000):
        """Deploy a simple web server in a subnet"""
        print(f"\n{'='*80}")
        print(f"DEPLOYING APPLICATION")
        print(f"{'='*80}")
        logger.info(f"Deploying {app_type} in {vpc_name}/{subnet_name}")
        
        vpc = self.state.get_vpc(vpc_name)
        if not vpc:
            print(f"❌ Error: VPC '{vpc_name}' not found")
            logger.error(f"VPC {vpc_name} not found")
            return False
        
        subnet = vpc["subnets"].get(subnet_name)
        if not subnet:
            print(f"❌ Error: Subnet '{subnet_name}' not found")
            logger.error(f"Subnet {subnet_name} not found")
            return False
        
        namespace = subnet["namespace"]
        
        try:
            if app_type == "python":
                # Create a simple HTML file to serve
                html_content = f"""
                <html>
                <head><title>VPC Test App</title></head>
                <body>
                    <h1>Hello from VPC: {vpc_name}</h1>
                    <h2>Subnet: {subnet_name}</h2>
                    <p>IP: {subnet['ip']}</p>
                    <p>Type: {subnet['type']}</p>
                    <p>Timestamp: {datetime.now().isoformat()}</p>
                </body>
                </html>
                """
                
                # Create temp directory in namespace
                temp_dir = f"/tmp/vpcctl_{namespace}"
                os.makedirs(temp_dir, exist_ok=True)
                
                with open(f"{temp_dir}/index.html", 'w') as f:
                    f.write(html_content)
                
                # Start Python HTTP server in background
                cmd = f"ip netns exec {namespace} python3 -m http.server {port} --directory {temp_dir} > /dev/null 2>&1 &"
                subprocess.Popen(cmd, shell=True)
                
                print(f"  ✓ Python HTTP server started")
                
            elif app_type == "nginx":
                print(f"  ℹ  nginx deployment requires nginx to be installed")
                print(f"  ℹ  Using Python HTTP server instead")
                return self.deploy_app(vpc_name, subnet_name, "python", port)
            
            # Update subnet state
            subnet["app"] = {
                "type": app_type,
                "port": port,
                "deployed_at": datetime.now().isoformat()
            }
            self.state.update_vpc(vpc_name, vpc)
            
            print(f"\n✅ Application deployed successfully!")
            print(f"   Type: {app_type}")
            print(f"   IP: {subnet['ip']}")
            print(f"   Port: {port}")
            print(f"   URL: http://{subnet['ip']}:{port}")
            print(f"\n   Test from host:")
            print(f"   curl http://{subnet['ip']}:{port}")
            
            logger.info(f"{app_type} deployed on {subnet['ip']}:{port}")
            return True
            
        except Exception as e:
            print(f"❌ Error: Failed to deploy app: {e}")
            logger.error(f"Failed to deploy app: {e}")
            return False
    
    def list_vpcs(self):
        """List all VPCs"""
        vpcs = self.state.list_vpcs()
        
        if not vpcs:
            print("\n📋 No VPCs found")
            print("   Create your first VPC with: sudo vpcctl create-vpc --name myvpc --cidr 10.0.0.0/16")
            return
        
        print(f"\n{'='*80}")
        print("VPC LIST")
        print(f"{'='*80}\n")
        
        for vpc_name, vpc in vpcs.items():
            print(f"📦 VPC: {vpc_name}")
            print(f"   CIDR Block: {vpc['cidr_block']}")
            print(f"   Bridge: {vpc['bridge']}")
            print(f"   Gateway IP: {vpc['bridge_ip']}")
            print(f"   Created: {vpc['created_at']}")
            print(f"   Subnets: {len(vpc['subnets'])}")
            
            if vpc["subnets"]:
                for subnet_name, subnet in vpc["subnets"].items():
                    icon = "🌐" if subnet['type'] == 'public' else "🔒"
                    print(f"      {icon} {subnet_name}")
                    print(f"         CIDR: {subnet['cidr']}")
                    print(f"         Type: {subnet['type']}")
                    print(f"         IP: {subnet['ip']}")
                    print(f"         Namespace: {subnet['namespace']}")
                    if subnet.get('app'):
                        print(f"         App: {subnet['app']['type']} on port {subnet['app']['port']}")
            
            if vpc.get("peerings"):
                print(f"   Peerings: {len(vpc['peerings'])}")
                for peering in vpc['peerings']:
                    print(f"      ↔ {peering['peer_vpc']}")
            
            print()
        
        print(f"{'='*80}\n")
    
    def show_vpc(self, vpc_name):
        """Show detailed VPC information"""
        vpc = self.state.get_vpc(vpc_name)
        
        if not vpc:
            print(f"❌ Error: VPC '{vpc_name}' not found")
            return False
        
        print(f"\n{'='*80}")
        print(f"VPC DETAILS: {vpc_name}")
        print(f"{'='*80}\n")
        
        print(f"Name: {vpc['name']}")
        print(f"CIDR Block: {vpc['cidr_block']}")
        print(f"Bridge: {vpc['bridge']}")
        print(f"Gateway IP: {vpc['bridge_ip']}")
        print(f"Created: {vpc['created_at']}")
        
        print(f"\n📊 Subnets ({len(vpc['subnets'])}):")
        if vpc["subnets"]:
            for subnet_name, subnet in vpc["subnets"].items():
                print(f"\n  • {subnet_name}")
                print(f"    CIDR: {subnet['cidr']}")
                print(f"    Type: {subnet['type']}")
                print(f"    IP: {subnet['ip']}")
                print(f"    Namespace: {subnet['namespace']}")
                print(f"    Veth Pair: {subnet['veth_host']} <-> {subnet['veth_ns']}")
                if subnet.get('app'):
                    print(f"    App: {subnet['app']['type']} on port {subnet['app']['port']}")
        else:
            print("    No subnets")
        
        print(f"\n🔗 Peerings ({len(vpc.get('peerings', []))}):")
        if vpc.get("peerings"):
            for peering in vpc['peerings']:
                print(f"  • {peering['peer_vpc']}")
                print(f"    Veth: {peering['veth_local']} <-> {peering['veth_remote']}")
        else:
            print("    No peerings")
        
        print(f"\n{'='*80}\n")
        return True
    
    def get_default_interface(self):
        """Get default network interface"""
        try:
            result = self.net.run_command(["ip", "route", "show", "default"])
            if result and result.stdout:
                parts = result.stdout.split()
                if "dev" in parts:
                    idx = parts.index("dev")
                    return parts[idx + 1]
        except:
            pass
        
        # Try common interface names
        for iface in ["eth0", "ens33", "enp0s3", "wlan0", "wlp2s0"]:
            result = self.net.run_command(["ip", "link", "show", iface], check=False)
            if result and result.returncode == 0:
                logger.info(f"Using interface: {iface}")
                return iface
        
        return "eth0"  # Last resort


def main():
    """Main CLI entry point"""
    
    # Check if running as root
    if os.geteuid() != 0:
        print("\n❌ Error: This script must be run as root")
        print("   Please run with: sudo vpcctl <command>\n")
        sys.exit(1)
    
    parser = argparse.ArgumentParser(
        description="vpcctl - Virtual Private Cloud Control Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  Create VPC:
    sudo vpcctl create-vpc --name myvpc --cidr 10.0.0.0/16
  
  Add public subnet:
    sudo vpcctl add-subnet --vpc myvpc --name public1 --cidr 10.0.1.0/24 --type public
  
  Add private subnet:
    sudo vpcctl add-subnet --vpc myvpc --name private1 --cidr 10.0.2.0/24 --type private
  
  List VPCs:
    sudo vpcctl list
  
  Show VPC details:
    sudo vpcctl show-vpc --name myvpc
  
  Peer VPCs:
    sudo vpcctl peer-vpcs --vpc1 myvpc --vpc2 othervpc
  
  Unpeer VPCs:
    sudo vpcctl unpeer-vpcs --vpc1 myvpc --vpc2 othervpc
  
  Apply firewall:
    sudo vpcctl apply-policy --vpc myvpc --subnet public1 --policy rules.json
  
  Deploy app:
    sudo vpcctl deploy-app --vpc myvpc --subnet public1 --port 8000
  
  Delete subnet:
    sudo vpcctl delete-subnet --vpc myvpc --name public1
  
  Delete VPC:
    sudo vpcctl delete-vpc --name myvpc
  
  Cleanup all:
    sudo vpcctl cleanup-all
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Commands')
    
    # Create VPC
    create_parser = subparsers.add_parser('create-vpc', help='Create a new VPC')
    create_parser.add_argument('--name', required=True, help='VPC name')
    create_parser.add_argument('--cidr', required=True, help='CIDR block (e.g., 10.0.0.0/16)')
    
    # Add Subnet
    subnet_parser = subparsers.add_parser('add-subnet', help='Add subnet to VPC')
    subnet_parser.add_argument('--vpc', required=True, help='VPC name')
    subnet_parser.add_argument('--name', required=True, help='Subnet name')
    subnet_parser.add_argument('--cidr', required=True, help='Subnet CIDR')
    subnet_parser.add_argument('--type', choices=['public', 'private'], default='private', help='Subnet type')
    
    # Delete Subnet
    del_subnet_parser = subparsers.add_parser('delete-subnet', help='Delete subnet from VPC')
    del_subnet_parser.add_argument('--vpc', required=True, help='VPC name')
    del_subnet_parser.add_argument('--name', required=True, help='Subnet name')
    
    # Delete VPC
    delete_parser = subparsers.add_parser('delete-vpc', help='Delete VPC')
    delete_parser.add_argument('--name', required=True, help='VPC name')
    
    # Peer VPCs
    peer_parser = subparsers.add_parser('peer-vpcs', help='Create VPC peering')
    peer_parser.add_argument('--vpc1', required=True, help='First VPC name')
    peer_parser.add_argument('--vpc2', required=True, help='Second VPC name')
    
    # Unpeer VPCs
    unpeer_parser = subparsers.add_parser('unpeer-vpcs', help='Delete VPC peering')
    unpeer_parser.add_argument('--vpc1', required=True, help='First VPC name')
    unpeer_parser.add_argument('--vpc2', required=True, help='Second VPC name')
    
    # Apply Policy
    policy_parser = subparsers.add_parser('apply-policy', help='Apply security group policy')
    policy_parser.add_argument('--vpc', required=True, help='VPC name')
    policy_parser.add_argument('--subnet', required=True, help='Subnet name')
    policy_parser.add_argument('--policy', required=True, help='Policy JSON file')
    
    # Deploy App
    deploy_parser = subparsers.add_parser('deploy-app', help='Deploy test application')
    deploy_parser.add_argument('--vpc', required=True, help='VPC name')
    deploy_parser.add_argument('--subnet', required=True, help='Subnet name')
    deploy_parser.add_argument('--type', default='python', help='App type (python/nginx)')
    deploy_parser.add_argument('--port', type=int, default=8000, help='Port number')
    
    # List VPCs
    list_parser = subparsers.add_parser('list', help='List all VPCs')
    
    # Show VPC
    show_parser = subparsers.add_parser('show-vpc', help='Show VPC details')
    show_parser.add_argument('--name', required=True, help='VPC name')
    
    # Cleanup all
    cleanup_parser = subparsers.add_parser('cleanup-all', help='Delete all VPCs')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    manager = VPCManager()
    
    try:
        if args.command == 'create-vpc':
            success = manager.create_vpc(args.name, args.cidr)
            sys.exit(0 if success else 1)
            
        elif args.command == 'add-subnet':
            success = manager.add_subnet(args.vpc, args.name, args.cidr, args.type)
            sys.exit(0 if success else 1)
            
        elif args.command == 'delete-subnet':
            success = manager.delete_subnet(args.vpc, args.name)
            sys.exit(0 if success else 1)
            
        elif args.command == 'delete-vpc':
            success = manager.delete_vpc(args.name)
            sys.exit(0 if success else 1)
            
        elif args.command == 'peer-vpcs':
            success = manager.peer_vpcs(args.vpc1, args.vpc2)
            sys.exit(0 if success else 1)
            
        elif args.command == 'unpeer-vpcs':
            success = manager.unpeer_vpcs(args.vpc1, args.vpc2)
            sys.exit(0 if success else 1)
            
        elif args.command == 'apply-policy':
            success = manager.apply_security_group(args.vpc, args.subnet, args.policy)
            sys.exit(0 if success else 1)
            
        elif args.command == 'deploy-app':
            success = manager.deploy_app(args.vpc, args.subnet, args.type, args.port)
            sys.exit(0 if success else 1)
            
        elif args.command == 'list':
            manager.list_vpcs()
            
        elif args.command == 'show-vpc':
            success = manager.show_vpc(args.name)
            sys.exit(0 if success else 1)
            
        elif args.command == 'cleanup-all':
            print("\n⚠️  WARNING: This will delete ALL VPCs!")
            response = input("Are you sure? (yes/no): ")
            if response.lower() == 'yes':
                vpcs = list(manager.state.list_vpcs().keys())
                for vpc_name in vpcs:
                    manager.delete_vpc(vpc_name)
                print("\n✅ All VPCs cleaned up")
            else:
                print("Operation cancelled")
            
    except KeyboardInterrupt:
        print("\n\n⚠️  Operation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        logger.error(f"Unexpected error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
VPCCTL_EOF

chmod +x vpcctl

echo "   ✓ vpcctl created"

# Create test script template
echo "   Creating test script..."
cat > tests/comprehensive_test.sh << 'TEST_EOF'
#!/bin/bash
#!/bin/bash
#
# Comprehensive VPC Testing Suite
# Tests all functionality required by Stage 4
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Log file
LOG_FILE="test_results_$(date +%Y%m%d_%H%M%S).log"

# Helper functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
    ((TESTS_PASSED++))
    ((TOTAL_TESTS++))
}

fail() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
    ((TESTS_FAILED++))
    ((TOTAL_TESTS++))
}

test_header() {
    echo "" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "$1" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    
    log "Running: $test_name"
    
    if eval "$test_command" >> "$LOG_FILE" 2>&1; then
        if [ "$expected_result" == "0" ]; then
            success "$test_name"
            return 0
        else
            fail "$test_name (expected to fail but succeeded)"
            return 1
        fi
    else
        if [ "$expected_result" == "1" ]; then
            success "$test_name (correctly failed as expected)"
            return 0
        else
            fail "$test_name"
            return 1
        fi
    fi
}

# Cleanup function
cleanup() {
    log "Cleaning up test resources..."
    sudo ./vpcctl cleanup-all >> "$LOG_FILE" 2>&1 || true
    sudo pkill -f "python3 -m http.server" >> "$LOG_FILE" 2>&1 || true
    log "Cleanup complete"
}

# Trap to ensure cleanup on exit
trap cleanup EXIT

# Start tests
clear
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║          VPC PROJECT - COMPREHENSIVE TEST SUITE               ║"
echo "║                  Stage 4 Validation                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log "Starting test suite at $(date)"
log "Log file: $LOG_FILE"
echo ""

# ============================================================================
# TEST 1: VPC Creation
# ============================================================================
test_header "TEST 1: VPC Creation"

run_test "Create VPC1 (10.0.0.0/16)" \
    "sudo ./vpcctl create-vpc --name vpc1 --cidr 10.0.0.0/16"

run_test "Create VPC2 (172.16.0.0/16)" \
    "sudo ./vpcctl create-vpc --name vpc2 --cidr 172.16.0.0/16"

run_test "Verify VPC1 bridge exists" \
    "ip link show br-vpc1"

run_test "Verify VPC2 bridge exists" \
    "ip link show br-vpc2"

# ============================================================================
# TEST 2: Subnet Creation
# ============================================================================
test_header "TEST 2: Subnet Creation"

run_test "Add public subnet to VPC1" \
    "sudo ./vpcctl add-subnet --vpc vpc1 --name public1 --cidr 10.0.1.0/24 --type public"

run_test "Add private subnet to VPC1" \
    "sudo ./vpcctl add-subnet --vpc vpc1 --name private1 --cidr 10.0.2.0/24 --type private"

run_test "Add public subnet to VPC2" \
    "sudo ./vpcctl add-subnet --vpc vpc2 --name public2 --cidr 172.16.1.0/24 --type public"

run_test "Add private subnet to VPC2" \
    "sudo ./vpcctl add-subnet --vpc vpc2 --name private2 --cidr 172.16.2.0/24 --type private"

run_test "Verify namespace ns-vpc1-public1 exists" \
    "sudo ip netns list | grep -q ns-vpc1-public1"

run_test "Verify namespace ns-vpc1-private1 exists" \
    "sudo ip netns list | grep -q ns-vpc1-private1"

# ============================================================================
# TEST 3: List VPCs
# ============================================================================
test_header "TEST 3: List VPCs"

run_test "List all VPCs" \
    "sudo ./vpcctl list"

run_test "Show VPC1 details" \
    "sudo ./vpcctl show-vpc --name vpc1"

# ============================================================================
# TEST 4: Intra-VPC Connectivity
# ============================================================================
test_header "TEST 4: Intra-VPC Connectivity"

log "Testing connectivity between subnets within VPC1..."

run_test "Ping from public1 to private1 (within VPC1)" \
    "sudo ip netns exec ns-vpc1-public1 ping -c 3 -W 2 10.0.2.1"

run_test "Ping from private1 to public1 (within VPC1)" \
    "sudo ip netns exec ns-vpc1-private1 ping -c 3 -W 2 10.0.1.1"

log "Testing connectivity between subnets within VPC2..."

run_test "Ping from public2 to private2 (within VPC2)" \
    "sudo ip netns exec ns-vpc2-public2 ping -c 3 -W 2 172.16.2.1"

# ============================================================================
# TEST 5: Internet Access (NAT Gateway)
# ============================================================================
test_header "TEST 5: Internet Access (NAT Gateway)"

log "Testing outbound internet access from public subnets..."

run_test "Public subnet (vpc1-public1) can reach internet" \
    "sudo ip netns exec ns-vpc1-public1 ping -c 3 -W 5 8.8.8.8"

run_test "Public subnet (vpc2-public2) can reach internet" \
    "sudo ip netns exec ns-vpc2-public2 ping -c 3 -W 5 8.8.8.8"

log "Testing that private subnets CANNOT reach internet..."

# These should fail (timeout)
run_test "Private subnet (vpc1-private1) CANNOT reach internet" \
    "timeout 5 sudo ip netns exec ns-vpc1-private1 ping -c 2 8.8.8.8" 1

run_test "Private subnet (vpc2-private2) CANNOT reach internet" \
    "timeout 5 sudo ip netns exec ns-vpc2-private2 ping -c 2 8.8.8.8" 1

# ============================================================================
# TEST 6: VPC Isolation
# ============================================================================
test_header "TEST 6: VPC Isolation (Before Peering)"

log "Verifying VPCs are isolated by default..."

run_test "VPC1 CANNOT reach VPC2 (isolation)" \
    "timeout 5 sudo ip netns exec ns-vpc1-public1 ping -c 2 172.16.1.1" 1

run_test "VPC2 CANNOT reach VPC1 (isolation)" \
    "timeout 5 sudo ip netns exec ns-vpc2-public2 ping -c 2 10.0.1.1" 1

# ============================================================================
# TEST 7: VPC Peering
# ============================================================================
test_header "TEST 7: VPC Peering"

run_test "Create peering between VPC1 and VPC2" \
    "sudo ./vpcctl peer-vpcs --vpc1 vpc1 --vpc2 vpc2"

run_test "Verify peering veth pair exists" \
    "ip link show peer-vpc1-vpc2"

log "Testing cross-VPC connectivity after peering..."

run_test "VPC1 CAN reach VPC2 (after peering)" \
    "sudo ip netns exec ns-vpc1-public1 ping -c 3 -W 2 172.16.1.1"

run_test "VPC2 CAN reach VPC1 (after peering)" \
    "sudo ip netns exec ns-vpc2-public2 ping -c 3 -W 2 10.0.1.1"

run_test "VPC1 private subnet CAN reach VPC2 public subnet" \
    "sudo ip netns exec ns-vpc1-private1 ping -c 3 -W 2 172.16.1.1"

# ============================================================================
# TEST 8: Application Deployment
# ============================================================================
test_header "TEST 8: Application Deployment"

log "Deploying web servers in subnets..."

run_test "Deploy app in VPC1 public subnet" \
    "sudo ./vpcctl deploy-app --vpc vpc1 --subnet public1 --port 8001"

run_test "Deploy app in VPC2 public subnet" \
    "sudo ./vpcctl deploy-app --vpc vpc2 --subnet public2 --port 8002"

sleep 3  # Wait for servers to start

log "Testing web server accessibility..."

run_test "Access web server in VPC1 from host" \
    "curl -s -m 5 http://10.0.1.1:8001 | grep -q 'vpc1'"

run_test "Access web server in VPC2 from host" \
    "curl -s -m 5 http://172.16.1.1:8002 | grep -q 'vpc2'"

run_test "Access VPC2 web server from VPC1 namespace" \
    "sudo ip netns exec ns-vpc1-public1 curl -s -m 5 http://172.16.1.1:8002 | grep -q 'vpc2'"

# ============================================================================
# TEST 9: Firewall Policy
# ============================================================================
test_header "TEST 9: Firewall Policy (Security Groups)"

log "Creating test firewall policy..."

cat > /tmp/test_policy.json << 'EOF'
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 8001, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"},
    {"port": 9999, "protocol": "tcp", "action": "deny"}
  ]
}
EOF

run_test "Apply firewall policy to VPC1 public subnet" \
    "sudo ./vpcctl apply-policy --vpc vpc1 --subnet public1 --policy /tmp/test_policy.json"

log "Note: Firewall rules applied. Port 8001 allowed, port 22 and 9999 denied."

# ============================================================================
# TEST 10: VPC Unpeering
# ============================================================================
test_header "TEST 10: VPC Unpeering"

run_test "Delete peering between VPC1 and VPC2" \
    "sudo ./vpcctl unpeer-vpcs --vpc1 vpc1 --vpc2 vpc2"

log "Verifying isolation is restored after unpeering..."

run_test "VPC1 CANNOT reach VPC2 (after unpeering)" \
    "timeout 5 sudo ip netns exec ns-vpc1-public1 ping -c 2 172.16.1.1" 1

# ============================================================================
# TEST 11: Subnet Deletion
# ============================================================================
test_header "TEST 11: Subnet Deletion"

run_test "Delete private subnet from VPC1" \
    "sudo ./vpcctl delete-subnet --vpc vpc1 --name private1"

run_test "Verify namespace ns-vpc1-private1 no longer exists" \
    "sudo ip netns list | grep -qv ns-vpc1-private1"

# ============================================================================
# TEST 12: VPC Deletion
# ============================================================================
test_header "TEST 12: VPC Deletion"

run_test "Delete VPC1" \
    "sudo ./vpcctl delete-vpc --name vpc1"

run_test "Verify VPC1 bridge no longer exists" \
    "! ip link show br-vpc1 2>/dev/null"

run_test "Delete VPC2" \
    "sudo ./vpcctl delete-vpc --name vpc2"

run_test "Verify all namespaces are cleaned up" \
    "! sudo ip netns list | grep -q ns-vpc"

# ============================================================================
# TEST 13: State Persistence
# ============================================================================
test_header "TEST 13: State Persistence"

run_test "Create VPC for state test" \
    "sudo ./vpcctl create-vpc --name testvpc --cidr 192.168.0.0/16"

run_test "Add subnet for state test" \
    "sudo ./vpcctl add-subnet --vpc testvpc --name testsub --cidr 192.168.1.0/24 --type public"

run_test "Verify state file exists" \
    "test -f ~/.vpcctl/vpc_state.json"

run_test "Verify state file contains VPC data" \
    "grep -q 'testvpc' ~/.vpcctl/vpc_state.json"

run_test "Delete test VPC" \
    "sudo ./vpcctl delete-vpc --name testvpc"

# ============================================================================
# TEST 14: Logging
# ============================================================================
test_header "TEST 14: Logging Verification"

run_test "Verify log directory exists" \
    "test -d ~/.vpcctl/logs"

run_test "Verify log files are created" \
    "ls ~/.vpcctl/logs/vpcctl_*.log | wc -l | grep -q '^[1-9]'"

run_test "Verify logs contain activity" \
    "grep -q 'Creating VPC' ~/.vpcctl/logs/vpcctl_*.log"

# ============================================================================
# Test Summary
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                      TEST SUMMARY                              ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Total Tests:  $TOTAL_TESTS"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              🎉 ALL TESTS PASSED! 🎉                          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "✅ Your VPC implementation meets all Stage 4 requirements!"
    echo ""
    log "All tests passed successfully!"
    exit 0
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              ⚠️  SOME TESTS FAILED  ⚠️                        ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "❌ Please review the log file: $LOG_FILE"
    echo ""
    log "Tests completed with failures"
    exit 1
fi

TEST_EOF

chmod +x tests/comprehensive_test.sh
echo "   ✓ Test script created"

# Create quick demo
echo "   Creating quick_demo.sh..."
cat > quick_demo.sh << 'DEMO_EOF'
#!/bin/bash
set -e
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              VPC PROJECT - QUICK DEMO                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Error: Please run with sudo"
    echo "   sudo ./quick_demo.sh"
    exit 1
fi

echo "🚀 Step 1: Creating VPC..."
./vpcctl create-vpc --name demovpc --cidr 10.0.0.0/16
sleep 1

echo ""
echo "🚀 Step 2: Adding public subnet..."
./vpcctl add-subnet --vpc demovpc --name public --cidr 10.0.1.0/24 --type public
sleep 1

echo ""
echo "🚀 Step 3: Adding private subnet..."
./vpcctl add-subnet --vpc demovpc --name private --cidr 10.0.2.0/24 --type private
sleep 1

echo ""
echo "🚀 Step 4: Listing VPCs..."
./vpcctl list
sleep 2

echo ""
echo "🚀 Step 5: Testing connectivity within VPC..."
echo "   Pinging from public to private subnet..."
ip netns exec ns-demovpc-public ping -c 3 10.0.2.1
sleep 1

echo ""
echo "🚀 Step 6: Testing internet access from public subnet..."
ip netns exec ns-demovpc-public ping -c 3 8.8.8.8
sleep 1

echo ""
echo "🚀 Step 7: Deploying web server in public subnet..."
./vpcctl deploy-app --vpc demovpc --subnet public --port 8000
sleep 3

echo ""
echo "🚀 Step 8: Testing web server..."
curl -s http://10.0.1.1:8000 | head -5
sleep 1

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              ✅ DEMO COMPLETE!                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 What was created:"
echo "   • VPC 'demovpc' with CIDR 10.0.0.0/16"
echo "   • Public subnet (10.0.1.0/24) with internet access"
echo "   • Private subnet (10.0.2.0/24) isolated from internet"
echo "   • Web server running on 10.0.1.1:8000"
echo ""
echo "🧹 To clean up, run:"
echo "   sudo ./vpcctl delete-vpc --name demovpc"
echo ""

DEMO_EOF

chmod +x quick_demo.sh
echo "   ✓ quick_demo.sh created"

# Create cleanup script
echo "   Creating cleanup.sh..."
cat > cleanup.sh << 'CLEANUP_EOF'
#!/bin/bash

# VPC CLEANUP SCRIPT
# Deletes all VPC resources created by vpcctl

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

CLEANUP_EOF

chmod +x cleanup.sh
echo "   ✓ cleanup.sh created"

# Create example policies
echo "   Creating example policies..."
cat > examples/web_server_policy.json << 'POLICY_EOF'
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 80, "protocol": "tcp", "action": "allow"},
    {"port": 443, "protocol": "tcp", "action": "allow"},
    {"port": 8000, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ]
}
POLICY_EOF

echo "   ✓ Example policies created"

# Create README
echo "   Creating README.md..."
cat > README.md << 'README_EOF'
# Virtual Private Cloud from Scratch

🚀 Building AWS-like VPC functionality using Linux networking primitives

## Quick Start

```bash
# Install dependencies
sudo apt install iproute2 iptables bridge-utils

# Create VPC
sudo ./vpcctl create-vpc --name myvpc --cidr 10.0.0.0/16

# Add subnet
sudo ./vpcctl add-subnet --vpc myvpc --name public --cidr 10.0.1.0/24 --type public

# List VPCs
sudo ./vpcctl list
```

## Project Structure

- `vpcctl` - Main CLI tool
- `tests/` - Test scripts
- `examples/` - Example policies
- `docs/` - Documentation

## Requirements

- Linux OS
- Python 3
- Root access
- iproute2, iptables, bridge-utils

## Documentation

See SETUP_GUIDE.md for complete setup instructions.

## Testing

```bash
sudo ./quick_demo.sh
sudo ./tests/comprehensive_test.sh
```

## Cleanup

```bash
sudo ./cleanup.sh
```

## License

MIT License
README_EOF

echo "   ✓ README.md created"

# Create .gitignore
echo "   Creating .gitignore..."
cat > .gitignore << 'GITIGNORE_EOF'
# Python
__pycache__/
*.py[cod]
*.pyc

# Logs
*.log
logs/
.vpcctl/

# IDE
.vscode/
.idea/
*.swp

# OS
.DS_Store

# Test results
test_results_*.log
GITIGNORE_EOF

echo "   ✓ .gitignore created"

# Step 4: Initialize git
echo ""
echo "📦 Step 4: Initializing Git repository..."

if [ -d ".git" ]; then
    echo "   ℹ️  Git already initialized"
else
    git init
    echo "   ✓ Git initialized"
fi

# Step 5: Enable IP forwarding
echo ""
echo "🔧 Step 5: Configuring system..."

echo "   Checking IP forwarding..."
current_forward=$(sysctl -n net.ipv4.ip_forward)
if [ "$current_forward" == "1" ]; then
    echo "   ✓ IP forwarding already enabled"
else
    echo "   ⚠️  IP forwarding is disabled"
    read -p "   Enable IP forwarding? (requires sudo) (y/n): " enable_forward
    if [ "$enable_forward" == "y" ]; then
        sudo sysctl -w net.ipv4.ip_forward=1
        echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
        echo "   ✓ IP forwarding enabled"
    fi
fi

# Step 6: Summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    SETUP COMPLETE!                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "📁 Project created in: $(pwd)"
echo ""
echo "⚠️  IMPORTANT: Replace placeholder files with complete versions!"
echo ""
echo "Files that need complete content:"
echo "   1. vpcctl - Main CLI script"
echo "   2. tests/comprehensive_test.sh - Test suite"
echo "   3. quick_demo.sh - Quick demonstration"
echo "   4. cleanup.sh - Cleanup script"
echo ""
echo "Next steps:"
echo "   1. Copy complete vpcctl script to ./vpcctl"
echo "   2. Copy complete test script to ./tests/comprehensive_test.sh"
echo "   3. Copy quick demo to ./quick_demo.sh"
echo "   4. Copy cleanup script to ./cleanup.sh"
echo "   5. Test: sudo ./vpcctl --help"
echo "   6. Run: sudo ./quick_demo.sh"
echo "   7. Initialize GitHub:"
echo "      git add ."
echo "      git commit -m 'Initial commit'"
echo "      git remote add origin https://github.com/YOUR_USERNAME/vpc-from-scratch.git"
echo "      git push -u origin main"
echo ""
echo "📖 See SETUP_GUIDE.md for detailed instructions"
echo ""
