#!/bin/bash
#
# Quick Demo Script for VPC Project
# Demonstrates basic functionality in under 2 minutes
#

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
