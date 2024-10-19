#!/bin/bash

# Wyświetlanie logo
curl -s https://raw.githubusercontent.com/zunxbt/logo/main/logo.sh | bash
sleep 3

ARCH=$(uname -m)

show() {
    echo -e "\033[1;35m$1\033[0m"
}

# Sprawdzenie i instalacja jq, jeśli brak
if ! command -v jq &> /dev/null; then
    show "jq not found, installing..."
    sudo apt-get update
    sudo apt-get install -y jq > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        show "Failed to install jq. Please check your package manager."
        exit 1
    fi
fi

# Funkcja sprawdzania najnowszej wersji
check_latest_version() {
    for i in {1..3}; do
        LATEST_VERSION=$(curl -s https://api.github.com/repos/hemilabs/heminetwork/releases/latest | jq -r '.tag_name')
        if [ -n "$LATEST_VERSION" ]; then
            show "Latest version available: $LATEST_VERSION"
            return 0
        fi
        show "Attempt $i: Failed to fetch the latest version. Retrying..."
        sleep 2
    done

    show "Failed to fetch the latest version after 3 attempts. Please check your internet connection or GitHub API limits."
    exit 1
}

check_latest_version

download_required=true

if [ "$ARCH" == "x86_64" ]; then
    if [ -d "heminetwork_${LATEST_VERSION}_linux_amd64" ]; then
        show "Latest version for x86_64 is already downloaded. Skipping download."
        cd "heminetwork_${LATEST_VERSION}_linux_amd64" || { show "Failed to change directory."; exit 1; }
        download_required=false
    fi
elif [ "$ARCH" == "arm64" ]; then
    if [ -d "heminetwork_${LATEST_VERSION}_linux_arm64" ]; then
        show "Latest version for arm64 is already downloaded. Skipping download."
        cd "heminetwork_${LATEST_VERSION}_linux_arm64" || { show "Failed to change directory."; exit 1; }
        download_required=false
    fi
fi

if [ "$download_required" = true ]; then
    if [ "$ARCH" == "x86_64" ]; then
        show "Downloading for x86_64 architecture..."
        wget --quiet --show-progress "https://github.com/hemilabs/heminetwork/releases/download/$LATEST_VERSION/heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz" -O "heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz"
        tar -xzf "heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz" > /dev/null
        cd "heminetwork_${LATEST_VERSION}_linux_amd64" || { show "Failed to change directory."; exit 1; }
    elif [ "$ARCH" == "arm64" ]; then
        show "Downloading for arm64 architecture..."
        wget --quiet --show-progress "https://github.com/hemilabs/heminetwork/releases/download/$LATEST_VERSION/heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz" -O "heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz"
        tar -xzf "heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz" > /dev/null
        cd "heminetwork_${LATEST_VERSION}_linux_arm64" || { show "Failed to change directory."; exit 1; }
    else
        show "Unsupported architecture: $ARCH"
        exit 1
    fi
else
    show "Skipping download as the latest version is already present."
fi

# Katalogi dla portfeli i logów
WALLET_DIR="$HOME/.heminetwork_wallets"
LOG_DIR="$HOME/.heminetwork_logs"
mkdir -p "$WALLET_DIR" "$LOG_DIR"

# Funkcja do tworzenia portfela
generate_wallet() {
    wallet_num=$1
    priv_key=$(openssl rand -hex 32)
    wallet_file="$WALLET_DIR/wallet_$wallet_num.json"
    echo "{\"private_key\": \"$priv_key\"}" > "$wallet_file"
    show "Wallet $wallet_num created successfully."
}

# Funkcja do uruchamiania usługi
create_and_start_service() {
    wallet_num=$1
    priv_key=$2
    static_fee=$3

    # Tworzenie usługi systemd
    service_name="heminetwork_wallet_$wallet_num.service"
    sudo bash -c "cat <<EOF > /etc/systemd/system/$service_name
[Unit]
Description=Heminetwork Wallet $wallet_num Mining Service
After=network.target

[Service]
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/popmd
Environment="POPM_BFG_REQUEST_TIMEOUT=60s"
Environment="POPM_BTC_PRIVKEY=$priv_key"
Environment="POPM_STATIC_FEE=$static_fee"
Environment="POPM_BFG_URL=wss://testnet.rpc.hemi.network/v1/ws/public"
Restart=on-failure
StandardOutput=append:$log_file
StandardError=append:$log_file

[Install]
WantedBy=multi-user.target
EOF"

    # Uruchomienie i włączenie usługi
    sudo systemctl daemon-reload
    sudo systemctl enable "$service_name"
    sudo systemctl start "$service_name"
    show "Service for wallet $wallet_num started."
}

# Funkcja do wyświetlania logów
view_logs() {
    wallet_num=$1
    service_name="heminetwork_wallet_$wallet_num.service"
    journalctl -u "$service_name" -f
}

# Główna pętla
wallet_count=0
while true; do
    echo
    show "1. Create a new wallet and start mining"
    show "2. Use an existing wallet and start mining"
    show "3. View logs for an existing wallet"
    show "4. Exit"
    read -p "Choose an option (1/2/3/4): " choice
    
    case $choice in
        1)
            wallet_count=$((wallet_count + 1))
            show "Creating wallet $wallet_count"
            generate_wallet $wallet_count
            read -p "Enter static fee for wallet $wallet_count (numerical only, recommended: 100-200): " static_fee
            priv_key=$(jq -r '.private_key' "$WALLET_DIR/wallet_$wallet_count.json")
            create_and_start_service $wallet_count "$priv_key" "$static_fee"
            ;;
        2)
            wallet_count=$((wallet_count + 1))
            read -p "Enter your Private key: " priv_key
            read -p "Enter static fee (recommended: 100-200): " static_fee
            echo
            create_and_start_service $wallet_count "$priv_key" "$static_fee"
            ;;
        3)
            read -p "Enter wallet number to view logs: " log_wallet
            view_logs $log_wallet
            ;;
        4)
            break
            ;;
        *)
            show "Invalid option. Please try again."
            ;;
    esac
done

show "PoP mining successfully started for $wallet_count wallet(s)"
show "You can check the logs for each wallet in the $LOG_DIR directory"
