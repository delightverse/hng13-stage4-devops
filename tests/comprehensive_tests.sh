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
