# Virtual Private Cloud from Scratch

🚀 **Building AWS-like VPC functionality using Linux networking primitives**


## 📋 Project Overview

This project implements a fully functional Virtual Private Cloud (VPC) system on Linux using native networking tools. No third-party virtualization software required - just pure Linux primitives!

### What's a VPC?

A Virtual Private Cloud is an isolated virtual network environment where you can launch resources with complete control over networking. This project recreates what cloud providers like AWS do under the hood.

### Technologies Used

- **Network Namespaces**: Isolated network environments (subnets)
- **Linux Bridges**: Virtual switches for routing traffic
- **veth Pairs**: Virtual ethernet cables connecting components
- **iptables**: Firewall and NAT configuration
- **Python 3**: CLI tool implementation

## ✨ Features

✅ **Multiple VPC Support** - Create isolated virtual networks  
✅ **Public & Private Subnets** - Control internet access  
✅ **NAT Gateway** - Enable outbound internet for public subnets  
✅ **VPC Peering** - Connect VPCs for controlled communication  
✅ **Security Groups** - Firewall rules via iptables  
✅ **Application Deployment** - Run web servers in subnets  
✅ **Complete CLI Tool** - Simple command-line interface  
✅ **State Persistence** - VPC configurations saved to disk  
✅ **Comprehensive Logging** - All operations logged  

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     HOST MACHINE (Linux)                      │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              VPC 1 (10.0.0.0/16)                    │    │
│  │                                                      │    │
│  │   ┌──────────────────┐       ┌──────────────────┐  │    │
│  │   │  Public Subnet   │       │  Private Subnet  │  │    │
│  │   │  (10.0.1.0/24)   │       │  (10.0.2.0/24)   │  │    │
│  │   │                  │       │                  │  │    │
│  │   │  ns-vpc1-public1 │       │ ns-vpc1-private1 │  │    │
│  │   │  IP: 10.0.1.1    │       │  IP: 10.0.2.1    │  │    │
│  │   └────────┬─────────┘       └────────┬─────────┘  │    │
│  │            │ veth pair                │ veth pair   │    │
│  │            └─────────┐     ┌──────────┘            │    │
│  │                      ▼     ▼                        │    │
│  │               ┌──────────────────┐                  │    │
│  │               │  br-vpc1         │                  │    │
│  │               │  (Linux Bridge)  │                  │    │
│  │               │  GW: 10.0.0.1    │                  │    │
│  │               └────────┬─────────┘                  │    │
│  └────────────────────────┼──────────────────────────  │    │
│                           │                                 │
│                           │ NAT (iptables MASQUERADE)       │
│                           ▼                                 │
│                  ┌──────────────────┐                       │
│                  │  eth0 (Internet) │                       │
│                  └──────────────────┘                       │
└──────────────────────────────────────────────────────────────┘
```

### How It Works

1. **VPC Creation**: Creates a Linux bridge that acts as the VPC router
2. **Subnet Creation**: Creates network namespaces (isolated environments)
3. **veth Pairs**: Virtual cables connect namespaces to the bridge
4. **Routing**: Automatic routing configuration for inter-subnet communication
5. **NAT Gateway**: iptables rules provide internet access for public subnets
6. **VPC Peering**: veth pairs connect different VPC bridges

## 🚀 Quick Start

### Prerequisites

- Linux OS (Ubuntu 20.04+ recommended)
- Root/sudo access
- Python 3.7+
- Required packages: `iproute2`, `iptables`, `bridge-utils`

### Installation

```bash
# Clone the repository
git clone https://github.com/delightverse/hng13-stage4-devops
cd vpc-from-scratch

# Install dependencies (Ubuntu/Debian)
sudo apt update
sudo apt install -y iproute2 iptables bridge-utils python3

# Make scripts executable
chmod +x vpcctl quick_demo.sh cleanup.sh
chmod +x tests/comprehensive_test.sh

# Create symlink for easy access (optional)
sudo ln -s $(pwd)/vpcctl /usr/local/bin/vpcctl
```

### Basic Usage

```bash

- note: vpc naming convention has a max character of 15 so ensure you use names withing the specified limit. Any failure may likely be related to the naming convention or improper ip addressing!

# Create a VPC
sudo ./vpcctl create-vpc --name myvpc --cidr 10.0.0.0/16

# Add a public subnet (with internet access)
sudo ./vpcctl add-subnet --vpc myvpc --name public --cidr 10.0.1.0/24 --type public

# Add a private subnet (no internet access)
sudo ./vpcctl add-subnet --vpc myvpc --name private --cidr 10.0.2.0/24 --type private

# List all VPCs
sudo ./vpcctl list

# Show VPC details
sudo ./vpcctl show-vpc --name myvpc

# Delete VPC (removes all resources)
sudo ./vpcctl delete-vpc --name myvpc
```

## 📖 Complete CLI Reference

### VPC Management

```bash
# Create VPC
sudo ./vpcctl create-vpc --name <vpc-name> --cidr <cidr-block>

# Delete VPC
sudo ./vpcctl delete-vpc --name <vpc-name>

# List all VPCs
sudo ./vpcctl list

# Show VPC details
sudo ./vpcctl show-vpc --name <vpc-name>

# Delete all VPCs
sudo ./vpcctl cleanup-all
```

### Subnet Management

```bash
# Add subnet
sudo ./vpcctl add-subnet --vpc <vpc-name> --name <subnet-name> --cidr <cidr> --type <public|private>

# Delete subnet
sudo ./vpcctl delete-subnet --vpc <vpc-name> --name <subnet-name>
```

### VPC Peering

```bash
# Create peering
sudo ./vpcctl peer-vpcs --vpc1 <vpc1-name> --vpc2 <vpc2-name>

# Delete peering
sudo ./vpcctl unpeer-vpcs --vpc1 <vpc1-name> --vpc2 <vpc2-name>
```

### Security & Applications

```bash
# Apply firewall policy
sudo ./vpcctl apply-policy --vpc <vpc-name> --subnet <subnet-name> --policy <policy-file.json>

# Deploy test application
sudo ./vpcctl deploy-app --vpc <vpc-name> --subnet <subnet-name> --port <port>
```

## 🧪 Testing

### Run Quick Demo

```bash
# 2-minute demonstration of core functionality
sudo ./quick_demo.sh
```

### Run Comprehensive Tests

```bash
# Complete test suite (all Stage 4 requirements)
cd tests
sudo ./comprehensive_test.sh
```

### Manual Testing

```bash
# Test connectivity between subnets
sudo ip netns exec ns-<vpc>-<subnet> ping <target-ip>

# Test internet access
sudo ip netns exec ns-<vpc>-<subnet> ping 8.8.8.8

# Test web server
curl http://<subnet-ip>:<port>

# Execute commands in namespace
sudo ip netns exec ns-<vpc>-<subnet> <command>
```

## 🔥 Example Workflows

### Example 1: Simple VPC with Web Server

```bash
# Create VPC
sudo ./vpcctl create-vpc --name webvpc --cidr 10.0.0.0/16

# Add public subnet
sudo ./vpcctl add-subnet --vpc webvpc --name public --cidr 10.0.1.0/24 --type public

# Deploy web server
sudo ./vpcctl deploy-app --vpc webvpc --subnet public --port 8000

# Test
curl http://10.0.1.1:8000
```

### Example 2: Multi-VPC with Peering

```bash
# Create two VPCs
sudo ./vpcctl create-vpc --name vpc1 --cidr 10.0.0.0/16
sudo ./vpcctl create-vpc --name vpc2 --cidr 172.16.0.0/16

# Add subnets
sudo ./vpcctl add-subnet --vpc vpc1 --name sub1 --cidr 10.0.1.0/24 --type public
sudo ./vpcctl add-subnet --vpc vpc2 --name sub2 --cidr 172.16.1.0/24 --type public

# Test isolation (should fail)
sudo ip netns exec ns-vpc1-sub1 ping -c 2 172.16.1.1

# Create peering
sudo ./vpcctl peer-vpcs --vpc1 vpc1 --vpc2 vpc2

# Test connectivity (should work)
sudo ip netns exec ns-vpc1-sub1 ping -c 3 172.16.1.1
```

### Example 3: Firewall Policy

```bash
# Create policy file
cat > my_policy.json << 'EOF'
{
  "subnet": "10.0.1.0/24",
  "ingress": [
    {"port": 80, "protocol": "tcp", "action": "allow"},
    {"port": 443, "protocol": "tcp", "action": "allow"},
    {"port": 22, "protocol": "tcp", "action": "deny"}
  ]
}
EOF

# Apply policy
sudo ./vpcctl apply-policy --vpc myvpc --subnet public --policy my_policy.json
```

## 📊 Test Results

All tests passing ✅

| Test Category | Status |
|--------------|--------|
| VPC Creation | ✅ PASS |
| Subnet Management | ✅ PASS |
| Intra-VPC Connectivity | ✅ PASS |
| NAT Gateway | ✅ PASS |
| VPC Isolation | ✅ PASS |
| VPC Peering | ✅ PASS |
| Application Deployment | ✅ PASS |
| Firewall Policies | ✅ PASS |
| Resource Cleanup | ✅ PASS |
| State Persistence | ✅ PASS |

See `tests/test_results_*.log` for detailed results.

## 🧹 Cleanup

```bash
# Clean up all VPCs via CLI
sudo ./vpcctl cleanup-all

# Or use the cleanup script (removes everything)
sudo ./cleanup.sh
```

## 📁 Project Structure├──

```
vpc-from-scratch/
├── vpcctl                          # Main CLI tool
├── quick_demo.sh                   # Quick demonstration
├── cleanup.sh                      # Complete cleanup
├── automate_setup.sh               # An automated script that sets up all the required files to create a VPC
├── all_commands.sh                 # All commands need to create and test the VPC
├── README.md                       # This file
├── tests/
│   ├── comprehensive_test.sh       # Full test suite
│   └── test_results_*.log          # Test logs
├── examples/
    ├── web_server_policy.json      # Example policies
    └── firewall_policies.json

```

## 🔍 Under the Hood

### Network Namespaces
Each subnet is a network namespace - an isolated networking environment with its own interfaces, routing table, and firewall rules.

### Linux Bridges
Act as virtual switches, connecting all subnets within a VPC and forwarding packets between them.

### veth Pairs
Virtual ethernet cables. One end stays in the host, attached to the bridge. The other end goes into the namespace.

### NAT with iptables
```bash
# MASQUERADE rule for outbound traffic
iptables -t nat -A POSTROUTING -s <subnet-cidr> -o <interface> -j MASQUERADE

# FORWARD rules for traffic flow
iptables -A FORWARD -i <bridge> -o <interface> -j ACCEPT
```

### Routing
```bash
# Default route in namespace
ip netns exec <namespace> ip route add default via <gateway-ip>

# Routes between VPCs (peering)
ip route add <vpc2-cidr> dev <vpc1-bridge>
```

## 🎓 Learning Resources

### Blog Post
📝 [Building a VPC from Scratch - Complete Tutorial] ()

### Video Demo
🎥 [VPC Project - Live Demonstration] ()

### Additional Reading
- [Linux Network Namespaces](https://man7.org/linux/man-pages/man8/ip-netns.8.html)
- [Understanding veth Pairs](https://developers.redhat.com/blog/2018/10/22/introduction-to-linux-interfaces-for-virtual-networking)
- [iptables Tutorial](https://www.netfilter.org/documentation/HOWTO/packet-filtering-HOWTO.html)
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)

## 🌟 Real-World Applications

This knowledge is directly applicable to:

- **Cloud Platforms**: Understanding AWS VPC, Azure VNet, GCP VPC
- **Kubernetes Networking**: CNI plugins use these same primitives
- **Docker Networking**: Container networking works similarly
- **Network Troubleshooting**: Deep understanding of packet flow
- **Infrastructure Design**: Designing secure, isolated networks

## 🤝 Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest features
- Submit pull requests
- Improve documentation

## 📝 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

- Built for HNG DevOps Internship Stage 4
- Inspired by AWS VPC and cloud networking concepts
- Thanks to the Linux networking community

## 📧 Contact

- GitHub: [@delightverse](https://github.com/delightverse/hng13-stage4-devops)
- Blog: [delightsVerse](https://medium.com/@delight.verse01/my-stage-4-hng-project-local-vpc-creation-aad81b52afd5)
- HNG: [HNG Internship](https://hng.tech)

---

**⭐ If this project helped you understand networking, please star the repository!**

---

Made with ❤️ for HNG DevOps Internship Stage 4
