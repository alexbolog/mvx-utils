#!/bin/bash

# MultiversX Wallet Generator
# 
# This script generates MultiversX wallets with optional parameters for count, shard, and mnemonic handling.
#
# Usage:
#   ./wallet_generator.sh [OPTIONS]
#
# Options:
#   --count=N        Number of wallets to generate (default: 1)
#   --shard=X        Restrict wallet generation to specific shard(s) (can be used multiple times)
#   --skip-mnemonic  Do not save mnemonic phrases to .txt files
#
# Examples:
#   Generate one wallet for any shard:
#     ./wallet_generator.sh
#
#   Generate 5 wallets for any shard:
#     ./wallet_generator.sh --count=5
#
#   Generate wallets only for shard 1:
#     ./wallet_generator.sh --shard=1
#
#   Generate 3 wallets for shards 0 or 1, without saving mnemonics:
#     ./wallet_generator.sh --count=3 --shard=0 --shard=1 --skip-mnemonic
#
# Requirements:
#   - mxpy (MultiversX SDK for Python) must be installed and configured
#   - curl must be installed for API calls
#
# Note: This script requires an active internet connection to fetch shard information from the MultiversX API.

# Function to generate a single wallet
generate_single() {
    local skip_mnemonic=$1
    shift
    local allowed_shards=("$@")

    while true; do
        # Generate the new wallet
        output=$(mxpy wallet new --format=pem --outfile=temp.pem)
        if [ $? -ne 0 ]; then
            echo "Something went wrong during wallet generation"
            rm -f temp.pem
            return 1
        fi

        # Extract the public key from the first line of the .pem file
        pubkey=$(head -n 1 temp.pem | grep -o 'erd[a-zA-Z0-9]*')
        if [ -z "$pubkey" ]; then
            echo "Something went wrong: Unable to extract public key"
            rm -f temp.pem
            return 1
        fi

        # Make API call to get shard information
        api_response=$(curl -s "https://api.multiversx.com/accounts/${pubkey}")
        if [ $? -ne 0 ]; then
            echo "Something went wrong: Unable to fetch shard information"
            rm -f temp.pem
            return 1
        fi

        # Extract shard number from API response
        shard=$(echo "$api_response" | grep -o '"shard":[0-9]*' | cut -d':' -f2)
        if [ -z "$shard" ]; then
            echo "Something went wrong: Unable to extract shard number"
            rm -f temp.pem
            return 1
        fi

        # Check if the shard is allowed
        if [ ${#allowed_shards[@]} -eq 0 ] || [[ " ${allowed_shards[@]} " =~ " ${shard} " ]]; then
            # Rename the .pem file
            mv temp.pem "${shard}_${pubkey}.pem"

            echo "Wallet generated: ${shard}_${pubkey}.pem"

            # Handle mnemonic based on skip_mnemonic flag
            if [ "$skip_mnemonic" = false ]; then
                # Extract the mnemonic phrase
                mnemonic=$(echo "$output" | grep "Mnemonic:" | sed 's/^Mnemonic: //')
                # Save the mnemonic to a text file
                printf "%s" "$mnemonic" > "${shard}_${pubkey}.txt"
                echo "Mnemonic saved: ${shard}_${pubkey}.txt"
            else
                echo "Mnemonic not saved (--skip-mnemonic flag used)"
            fi

            return 0
        else
            echo "Generated wallet for shard ${shard}, but it's not in the allowed list. Retrying..."
            rm -f temp.pem
        fi
    done
}

# Main function to handle wallet generation
generate() {
    local count=1
    local allowed_shards=()
    local skip_mnemonic=false

    # Parse named arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --count=*) count="${1#*=}" ;;
            --shard=*) allowed_shards+=("${1#*=}") ;;
            --skip-mnemonic) skip_mnemonic=true ;;
            --help) 
                sed -n '/^#/,/^[^#]/p' "$0" | sed 's/^# \?//g'
                return 0
                ;;
            *) echo "Unknown parameter passed: $1"; return 1 ;;
        esac
        shift
    done

    # Check if the count is a positive integer
    if ! [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: Please provide a positive integer for the number of wallets to generate."
        return 1
    fi

    for ((i=1; i<=count; i++)); do
        echo "Generating wallet $i of $count"
        generate_single "$skip_mnemonic" "${allowed_shards[@]}"
        if [ $? -ne 0 ]; then
            echo "Failed to generate wallet $i. Stopping."
            return 1
        fi
        echo ""
    done

    echo "Finished generating $count wallet(s)."
}

# Only execute generate if the script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    generate "$@"
fi