#!/bin/bash

# Test script for alternative wallet address discovery method
# This script demonstrates how to get wallet address via inbox

echo "=== AO CLI Address Discovery Test ==="
echo "Testing alternative method: wallet address via inbox"
echo ""

# Step 1: Get wallet address using direct command
echo "Step 1: Getting wallet address using direct command..."
DIRECT_ADDRESS=$(node ao-cli.js address 2>/dev/null | grep "Wallet Address:" | sed 's/💰 Wallet Address: //')
echo "Direct address: $DIRECT_ADDRESS"
echo ""

# Step 2: Create a test process or use known process
echo "Step 2: Setting up test process for inbox testing..."

# Try to create a new process
echo "Attempting to spawn test process..."
SPAWN_OUTPUT=$(node ao-cli.js spawn default --name "address-test-$(date +%s)" 2>/dev/null)
TEST_PROCESS_ID=$(echo "$SPAWN_OUTPUT" | grep "Process ID:" | awk '{print $4}')

if [ -z "$TEST_PROCESS_ID" ]; then
    echo "⚠️  Failed to create new process, trying to use known test process..."
    # Fallback to a known process from previous tests
    TEST_PROCESS_ID="_7Mriehd19DW53VdCse4GQD1Wmvq0utMDyBBy0xRias"
    echo "Using fallback process ID: $TEST_PROCESS_ID"
else
    echo "✅ Test process created successfully!"
    echo "Test process ID: $TEST_PROCESS_ID"
    echo ""

    # Wait a moment for the process to be ready
    echo "Waiting 2 seconds for process to initialize..."
    sleep 2
fi

# Step 3: Send an unhandled message to the process
echo "Step 3: Sending unhandled message to test process..."
echo "Sending message with action 'AddressTestMessage'..."
node ao-cli.js message "$TEST_PROCESS_ID" AddressTestMessage --data "Testing wallet address discovery" --wait 2>/dev/null || echo "Message sent (ignoring potential network errors)"
echo ""

# Step 4: Check inbox for the message
echo "Step 4: Checking inbox for the sent message..."
echo "Inbox contents (last message):"
INBOX_RESULT=$(node ao-cli.js inbox "$TEST_PROCESS_ID" --latest 2>/dev/null || echo "Failed to check inbox")

if [ -n "$INBOX_RESULT" ]; then
    echo "$INBOX_RESULT"
    echo ""

    # Extract From address from inbox
    INBOX_ADDRESS=$(echo "$INBOX_RESULT" | grep "From =" | head -1 | sed 's/.*From = "\([^"]*\)".*/\1/')
    echo "Address found in inbox: $INBOX_ADDRESS"
    echo ""

    # Step 5: Compare addresses
    echo "Step 5: Comparing addresses..."
    if [ "$DIRECT_ADDRESS" = "$INBOX_ADDRESS" ]; then
        echo "✅ SUCCESS: Addresses match!"
        echo "   Direct command: $DIRECT_ADDRESS"
        echo "   Inbox method:   $INBOX_ADDRESS"
        echo ""
        echo "🎉 Alternative method works correctly!"
    else
        echo "❌ FAILURE: Addresses don't match!"
        echo "   Direct command: $DIRECT_ADDRESS"
        echo "   Inbox method:   $INBOX_ADDRESS"
        echo ""
        echo "⚠️  Alternative method may not work as expected"
    fi
else
    echo "❌ Could not retrieve inbox contents"
    echo "This might be due to network issues or the test process not existing"
    echo ""
    echo "💡 Alternative method theory:"
    echo "   When you send a message to a process with an action that isn't handled,"
    echo "   the message appears in that process's inbox with your address in the From field."
fi

echo ""
echo "=== Test Complete ==="
