# Complete Command Reference

## 🚀 STEP-BY-STEP EXECUTION COMMANDS

### PHASE 1: Initial Setup (10 minutes)

```bash
# 1. Update system
sudo apt update && sudo apt upgrade -y

# 2. Install dependencies
sudo apt install -y iproute2 iptables bridge-utils python3 git curl

# 3. Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# 4. Verify
sysctl net.ipv4.ip_forward  # Should show "1"
python3 --version            # Should show Python 3.x
ip --version                 # Should show ip utility version
```

### PHASE 2: Create Project (5 minutes)

```bash
# 1. Create project directory
cd ~
mkdir -p vpc-project/{tests,examples,docs}
cd vpc-project

# 2. Create all files (you'll paste content into these)
touch vpcctl
touch quick_demo.sh
touch cleanup.sh
touch tests/comprehensive_test.sh
touch examples/web_server_policy.json
touch README.md
touch .gitignore

# 3. Make scripts executable
chmod +x vpcctl quick_demo.sh cleanup.sh tests/comprehensive_test.sh
```

### PHASE 3: Add Content to Files (15 minutes)

For each file, use your text editor to paste the content:

```bash
# Option 1: Using nano
nano vpcctl
# Paste content, Ctrl+O to save, Ctrl+X to exit

# Option 2: Using cat (for each file)
cat > vpcctl << 'EOF'
[Paste the complete vpcctl script content here]
EOF

# Repeat for all files:
# - vpcctl
# - quick_demo.sh
# - cleanup.sh  
# - tests/comprehensive_test.sh
# - examples/web_server_policy.json
# - README.md
# - .gitignore
```

### PHASE 4: Test Your Setup (10 minutes)

```bash
# 1. Test vpcctl help
./vpcctl --help

# 2. Create test VPC
sudo ./vpcctl create-vpc --name testvpc --cidr 10.0.0.0/16

# 3. Add test subnet
sudo ./vpcctl add-subnet --vpc testvpc --name testsub --cidr 10.0.1.0/24 --type public

# 4. List VPCs
sudo ./vpcctl list

# 5. Test internet connectivity
sudo ip netns exec ns-testvpc-testsub ping -c 3 8.8.8.8

# 6. Clean up test
sudo ./vpcctl delete-vpc --name testvpc

# 7. Verify cleanup
sudo ./vpcctl list  # Should show no VPCs
```

### PHASE 5: Git Setup (5 minutes)

```bash
# 1. Configure git
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"

# 2. Initialize repository
git init
git branch -M main

# 3. First commit
git add .
git commit -m "Initial commit: VPC from scratch implementation"

# 4. Create GitHub repository
# Go to github.com and create new repository named "vpc-from-scratch"
# Set it to PUBLIC

# 5. Link and push
git remote add origin https://github.com/YOUR_USERNAME/vpc-from-scratch.git
git push -u origin main
```

### PHASE 6: Run Quick Demo (2 minutes)

```bash
# Run quick demonstration
sudo ./quick_demo.sh

# This will:
# - Create a VPC
# - Add subnets
# - Test connectivity
# - Deploy web server
# - Show everything working
```

### PHASE 7: Run Comprehensive Tests (10 minutes)

```bash
# Run full test suite
cd tests
sudo ./comprehensive_test.sh

# This tests:
# ✓ VPC creation
# ✓ Subnet management
# ✓ Intra-VPC connectivity
# ✓ NAT gateway
# ✓ VPC isolation
# ✓ VPC peering
# ✓ Application deployment
# ✓ Firewall policies
# ✓ Cleanup

# Save test results
cp test_results_*.log ../
```

### PHASE 8: Clean Everything (2 minutes)

```bash
# Return to project root
cd ..

# Run cleanup
sudo ./cleanup.sh

# Verify cleanup
sudo ./vpcctl list  # Should show no VPCs
sudo ip netns list  # Should show no ns-* namespaces
sudo ip link show type bridge  # Should show no br-* bridges
```

---

## 📝 ALL VPCCTL COMMANDS

### VPC Management

```bash
# Create VPC
sudo ./vpcctl create-vpc --name <name> --cidr <cidr>
# Example:
sudo ./vpcctl create-vpc --name myvpc --cidr 10.0.0.0/16

# Delete VPC
sudo ./vpcctl delete-vpc --name <name>
# Example:
sudo ./vpcctl delete-vpc --name myvpc

# List all VPCs
sudo ./vpcctl list

# Show VPC details
sudo ./vpcctl show-vpc --name <name>
# Example:
sudo ./vpcctl show-vpc --name myvpc

# Delete all VPCs
sudo ./vpcctl cleanup-all
```

### Subnet Management

```bash
# Add public subnet
sudo ./vpcctl add-subnet --vpc <vpc> --name <name> --cidr <cidr> --type public
# Example:
sudo ./vpcctl add-subnet --vpc myvpc --name public1 --cidr 10.0.1.0/24 --type public

# Add private subnet
sudo ./vpcctl add-subnet --vpc <vpc> --name <name> --cidr <cidr> --type private
# Example:
sudo ./vpcctl add-subnet --vpc myvpc --name private1 --cidr 10.0.2.0/24 --type private

# Delete subnet
sudo ./vpcctl delete-subnet --vpc <vpc> --name <name>
# Example:
sudo ./vpcctl delete-subnet --vpc myvpc --name public1
```

### VPC Peering

```bash
# Create peering
sudo ./vpcctl peer-vpcs --vpc1 <vpc1> --vpc2 <vpc2>
# Example:
sudo ./vpcctl peer-vpcs --vpc1 vpc1 --vpc2 vpc2

# Delete peering
sudo ./vpcctl unpeer-vpcs --vpc1 <vpc1> --vpc2 <vpc2>
# Example:
sudo ./vpcctl unpeer-vpcs --vpc1 vpc1 --vpc2 vpc2
```

### Security & Applications

```bash
# Apply firewall policy
sudo ./vpcctl apply-policy --vpc <vpc> --subnet <subnet> --policy <file>
# Example:
sudo ./vpcctl apply-policy --vpc myvpc --subnet public1 --policy examples/web_server_policy.json

# Deploy application
sudo ./vpcctl deploy-app --vpc <vpc> --subnet <subnet> --port <port>
# Example:
sudo ./vpcctl deploy-app --vpc myvpc --subnet public1 --port 8000
```

---

## 🧪 TESTING COMMANDS

### Manual Testing

```bash
# Test connectivity between subnets
sudo ip netns exec ns-<vpc>-<subnet> ping <target-ip>
# Example:
sudo ip netns exec ns-myvpc-public1 ping 10.0.2.1

# Test internet access
sudo ip netns exec ns-<vpc>-<subnet> ping 8.8.8.8
# Example:
sudo ip netns exec ns-myvpc-public1 ping 8.8.8.8

# Test web server
curl http://<subnet-ip>:<port>
# Example:
curl http://10.0.1.1:8000

# Execute command in namespace
sudo ip netns exec ns-<vpc>-<subnet> <command>
# Example:
sudo ip netns exec ns-myvpc-public1 ip addr show
```

### Verification Commands

```bash
# List all namespaces
sudo ip netns list

# List all bridges
ip link show type bridge

# List all veth pairs
ip link show type veth

# Show iptables NAT rules
sudo iptables -t nat -L -n -v

# Show iptables FORWARD rules
sudo iptables -L FORWARD -n -v

# Show routing table
ip route show

# Show VPC state file
cat ~/.vpcctl/vpc_state.json

# View logs
cat ~/.vpcctl/logs/vpcctl_*.log
tail -f ~/.vpcctl/logs/vpcctl_*.log
```

---

## 📊 EXAMPLE WORKFLOWS

### Workflow 1: Simple VPC

```bash
# Create VPC
sudo ./vpcctl create-vpc --name simple --cidr 10.0.0.0/16

# Add public subnet
sudo ./vpcctl add-subnet --vpc simple --name public --cidr 10.0.1.0/24 --type public

# Test internet
sudo ip netns exec ns-simple-public ping -c 3 8.8.8.8

# Deploy app
sudo ./vpcctl deploy-app --vpc simple --subnet public --port 8000

# Test app
curl http://10.0.1.1:8000

# Cleanup
sudo ./vpcctl delete-vpc --name simple
```

### Workflow 2: Multi-Tier Application

```bash
# Create VPC
sudo ./vpcctl create-vpc --name app --cidr 10.0.0.0/16

# Add web tier (public)
sudo ./vpcctl add-subnet --vpc app --name web --cidr 10.0.1.0/24 --type public

# Add app tier (private)
sudo ./vpcctl add-subnet --vpc app --name app --cidr 10.0.2.0/24 --type private

# Add DB tier (private)
sudo ./vpcctl add-subnet --vpc app --name db --cidr 10.0.3.0/24 --type private

# Test connectivity
sudo ip netns exec ns-app-web ping -c 3 10.0.2.1  # Web to App
sudo ip netns exec ns-app-app ping -c 3 10.0.3.1  # App to DB

# Web has internet
sudo ip netns exec ns-app-web ping -c 3 8.8.8.8

# App tier does NOT have internet
sudo ip netns exec ns-app-app ping -c 2 8.8.8.8  # Should timeout

# Cleanup
sudo ./vpcctl delete-vpc --name app
```

### Workflow 3: VPC Peering

```bash
# Create VPC 1
sudo ./vpcctl create-vpc --name vpc1 --cidr 10.0.0.0/16
sudo ./vpcctl add-subnet --vpc vpc1 --name sub1 --cidr 10.0.1.0/24 --type public

# Create VPC 2
sudo ./vpcctl create-vpc --name vpc2 --cidr 172.16.0.0/16
sudo ./vpcctl add-subnet --vpc vpc2 --name sub2 --cidr 172.16.1.0/24 --type public

# Test isolation (should FAIL)
sudo ip netns exec ns-vpc1-sub1 ping -c 2 -W 2 172.16.1.1  # Times out

# Create peering
sudo ./vpcctl peer-vpcs --vpc1 vpc1 --vpc2 vpc2

# Test connectivity (should WORK)
sudo ip netns exec ns-vpc1-sub1 ping -c 3 172.16.1.1
sudo ip netns exec ns-vpc2-sub2 ping -c 3 10.0.1.1

# Remove peering
sudo ./vpcctl unpeer-vpcs --vpc1 vpc1 --vpc2 vpc2

# Test isolation again (should FAIL)
sudo ip netns exec ns-vpc1-sub1 ping -c 2 -W 2 172.16.1.1

# Cleanup
sudo ./vpcctl delete-vpc --name vpc1
sudo ./vpcctl delete-vpc --name vpc2
```

### Workflow 4: Firewall Policy

```bash
# Create VPC and subnet
sudo ./vpcctl create-vpc --name secure --cidr 10.0.0.0/16
sudo ./vpcctl add-subnet --vpc secure --name public --cidr 10.0.1.0/24 --type public

# Deploy web server
sudo ./vpcctl deploy-app --vpc secure --subnet public --port 8000

# Apply firewall policy
sudo ./vpcctl apply-policy --vpc secure --subnet public --policy examples/web_server_policy.json

# Test allowed port (should work)
curl http://10.0.1.1:8000

# Cleanup
sudo ./vpcctl delete-vpc --name secure
```

---

## 🎥 VIDEO RECORDING COMMANDS

```bash
# Install recording tool
sudo apt install asciinema  # or simplescreenrecorder or obs-studio

# Start recording
asciinema rec vpc-demo.cast

# Run your demo
sudo ./quick_demo.sh

# Stop recording (Ctrl+D)

# Upload to asciinema or YouTube
```

---

## 📦 GIT COMMANDS

```bash
# Add all changes
git add .

# Commit with message
git commit -m "feat: Add comprehensive VPC implementation"

# Push to GitHub
git push origin main

# Check status
git status

# View commit history
git log --oneline

# Create and push tag
git tag -a v1.0 -m "Stage 4 Submission"
git push origin v1.0
```

---

## 🧹 CLEANUP COMMANDS

```bash
# Clean using vpcctl
sudo ./vpcctl cleanup-all

# Clean using cleanup script
sudo ./cleanup.sh

# Manual cleanup (if needed)
# Delete all namespaces
for ns in $(sudo ip netns list | grep ns- | awk '{print $1}'); do sudo ip netns del $ns; done

# Delete all bridges
for br in $(ip link show type bridge | grep br- | awk -F: '{print $2}'); do sudo ip link del $br; done

# Delete all veth pairs
for veth in $(ip link show type veth | grep -E "(veth-|peer-)" | awk -F: '{print $2}'); do sudo ip link del $veth; done

# Flush iptables
sudo iptables -t nat -F
sudo iptables -F FORWARD

# Kill web servers
sudo pkill -f "python3 -m http.server"
```

---

## 📋 SUBMISSION CHECKLIST COMMANDS

```bash
# 1. Verify all tests pass
cd tests && sudo ./comprehensive_test.sh && cd ..

# 2. Verify quick demo works
sudo ./quick_demo.sh && sudo ./cleanup.sh

# 3. Check Git status
git status

# 4. Verify GitHub repository
git remote -v
git log --oneline

# 5. Check file structure
tree -L 2

# 6. Verify all scripts are executable
ls -la *.sh tests/*.sh

# 7. Test cleanup
sudo ./cleanup.sh

# 8. Final git push
git add .
git commit -m "Final submission - Stage 4"
git push origin main
```

---

**Remember: Always run vpcctl commands with `sudo`!**

**Good luck with your submission! 🚀**
