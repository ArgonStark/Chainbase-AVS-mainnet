#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Display logo
echo -e "${GREEN}"
cat << "EOF"
                                               _____   _                    _    
     /\                                       / ____| | |                  | |   
    /  \     _ __    __ _    ___    _ __     | (___   | |_    __ _   _ __  | | __
   / /\ \   | '__|  / _ |  / _ \  | '_ \     \___ \  | __|  / _ | | '__| | |/ /
  / ____ \  | |    | (_| | | (_) | | | | |    ____) | | |_  | (_| | | |    |   < 
 /_/    \_\ |_|     \__, |  \___/  |_| |_|   |_____/   \__|  \__,_| |_|    |_|\_\
                     __/ |                                                       
                    |___/                                                         
EOF

sleep 3

echo -e "${NC}"

# Update and upgrade system packages
echo -e "${BLUE}Updating and upgrading the system...${NC}"
sudo apt update && sudo apt upgrade -y

# Install Docker
echo -e "${BLUE}Adding Docker's official GPG key and repository...${NC}"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo -e "${BLUE}Installing Docker...${NC}"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

docker version

# Install Docker Compose
echo -e "${BLUE}Installing Docker Compose...${NC}"
VER=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
curl -L "https://github.com/docker/compose/releases/download/$VER/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
docker-compose --version

# Install Go
echo -e "${BLUE}Installing Go...${NC}"
cd $HOME
ver="1.22.0"
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
rm "go$ver.linux-amd64.tar.gz"
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bash_profile
source ~/.bash_profile
go version

# Install Eigenlayer CLI
echo -e "${BLUE}Installing Eigenlayer CLI...${NC}"
curl -sSfL https://raw.githubusercontent.com/layr-labs/eigenlayer-cli/master/scripts/install.sh | sh -s
export PATH=$PATH:~/bin
eigenlayer --version

# Clone Chainbase Mainnet Repository
echo -e "${BLUE}Cloning Chainbase repository...${NC}"
cd $HOME
git clone https://github.com/chainbase-labs/chainbase-avs-setup
cd chainbase-avs-setup/mainnet

# Create or Import ECDSA and BLS keys
echo -e "${YELLOW}Do you want to create or import Eigenlayer ECDSA key?${NC}"
echo "1. Create"
echo "2. Import"
read -rp "Choose an option (1/2): " wallet_option

if [ "$wallet_option" -eq 1 ]; then
    read -rp "Enter a name for your ECDSA key: " ecdsa_keyname
    eigenlayer operator keys create --key-type ecdsa "$ecdsa_keyname"
else
    read -rp "Enter the name for your ECDSA key: " ecdsa_keyname
    read -rp "Enter your ECDSA private key: " ecdsa_privatekey
    eigenlayer operator keys import --key-type ecdsa "$ecdsa_keyname" "$ecdsa_privatekey"
fi

echo -e "${YELLOW}Do you want to create or import Eigenlayer BLS key?${NC}"
echo "1. Create"
echo "2. Import"
read -rp "Choose an option (1/2): " bls_option

if [ "$bls_option" -eq 1 ]; then
    read -rp "Enter a name for your BLS key: " bls_keyname
    eigenlayer operator keys create --key-type bls "$bls_keyname"
else
    read -rp "Enter the name for your BLS key: " bls_keyname
    read -rp "Enter your BLS private key: " bls_privatekey
    eigenlayer operator keys import --key-type bls "$bls_keyname" "$bls_privatekey"
fi

# Fund wallet verification
echo -e "${YELLOW}Ensure your wallet is funded with Mainnet ETH before proceeding. Have you done this? (yes/no)${NC}"
read -rp "Answer: " funded
if [ "$funded" != "yes" ]; then
    echo -e "${RED}Please fund your wallet and rerun the script.${NC}"
    exit 1
fi

echo -e "${BLUE}Registering the operator...${NC}"
eigenlayer operator config create

# Metadata upload and operator registration
echo -e "${YELLOW}Upload the metadata file to your GitHub profile and provide the link:${NC}"
read -p "GitHub Metadata URL: " metadata_url
sed -i "s|metadata_url:.*|metadata_url: \"$metadata_url\"|" operator.yaml

eigenlayer operator register operator.yaml

# Configure .env file
echo -e "${YELLOW}Please provide the following information to configure the .env file.${NC}"
read -rp "ECDSA key file path: " NODE_ECDSA_KEY_FILE_PATH
read -rp "BLS key file path: " NODE_BLS_KEY_FILE_PATH
read -rp "ECDSA key password: " OPERATOR_ECDSA_KEY_PASSWORD
read -rp "BLS key password: " OPERATOR_BLS_KEY_PASSWORD
read -rp "ECDSA key address: " OPERATOR_ADDRESS
read -rp "Server public IP: " NODE_SOCKET
NODE_SOCKET="$NODE_SOCKET:8011"
read -rp "Operator name: " OPERATOR_NAME

cp .env.example .env
cat <<EOT > .env
NODE_ECDSA_KEY_FILE_PATH=$NODE_ECDSA_KEY_FILE_PATH
NODE_BLS_KEY_FILE_PATH=$NODE_BLS_KEY_FILE_PATH
OPERATOR_ECDSA_KEY_PASSWORD=$OPERATOR_ECDSA_KEY_PASSWORD
OPERATOR_BLS_KEY_PASSWORD=$OPERATOR_BLS_KEY_PASSWORD
OPERATOR_ADDRESS=$OPERATOR_ADDRESS
NODE_SOCKET=$NODE_SOCKET
OPERATOR_NAME=$OPERATOR_NAME
EOT

# Grafana Port Customization
echo -e "${YELLOW}Enter the port you want Grafana to run on (default is 3010):${NC}"
read -rp "Port: " GRAFANA_PORT

if [ -z "$GRAFANA_PORT" ]; then
    GRAFANA_PORT=3010
fi
echo -e "${GREEN}Using port $GRAFANA_PORT for Grafana.${NC}"

# Update docker-compose.yaml
if [ -f "./docker-compose.yaml" ]; then
    sed -i "s|3010:3000|$GRAFANA_PORT:3000|" docker-compose.yaml
    echo -e "${GREEN}Updated docker-compose.yml to use port $GRAFANA_PORT for Grafana.${NC}"
else
    echo -e "${RED}Error: docker-compose.yaml file not found!${NC}"
    exit 1
fi

# Start Docker and the node
systemctl start docker

echo -e "${BLUE}Starting the node...${NC}"
chmod +x ./chainbase-avs.sh
echo -e "${GREEN}Registering AVS${NC}"
./chainbase-avs.sh register

sleep 3

echo -e "${GREEN}Running Chainbase AVS${NC}"
./chainbase-avs.sh run
