#!/bin/bash

# Copyright (c) 2023-2024 sinamics
# Author: sinamics (Bernt Christian Egeland)
# License: GPL-3.0
# https://github.com/sinamics/ztnet/blob/main/LICENSE
# Rocky Linux & Cloud Database Migration Edition

clear
set -E -o functrace

if [ -t 1 ]; then
  is_tty() {
    true
  }
else
  is_tty() {
    false
  }
fi
supports_truecolor() {
  case "$COLORTERM" in
  truecolor|24bit) return 0 ;;
  esac

  case "$TERM" in
  iterm           |\
  tmux-truecolor  |\
  linux-truecolor |\
  xterm-truecolor |\
  screen-truecolor) return 0 ;;
  esac

  return 1
}

setup_color() {
  # Only use colors if connected to a terminal
  if ! is_tty; then
    FMT_RAINBOW=""
    FMT_RED=""
    FMT_GREEN=""
    FMT_YELLOW=""
    FMT_BLUE=""
    FMT_BOLD=""
    FMT_RESET=""
    return
  fi

  if supports_truecolor; then
    FMT_RAINBOW="
      $(printf '\033[38;2;255;0;0m')
      $(printf '\033[38;2;255;97;0m')
      $(printf '\033[38;2;247;255;0m')
      $(printf '\033[38;2;0;255;30m')
      $(printf '\033[38;2;77;0;255m')
      $(printf '\033[38;2;168;0;255m')
      $(printf '\033[38;2;245;0;172m')
    "
  else
    FMT_RAINBOW="
      $(printf '\033[38;5;196m')
      $(printf '\033[38;5;202m')
      $(printf '\033[38;5;226m')
      $(printf '\033[38;5;082m')
      $(printf '\033[38;5;021m')
      $(printf '\033[38;5;093m')
      $(printf '\033[38;5;163m')
    "
  fi

  FMT_RED=$(printf '\033[31m')
  FMT_GREEN=$(printf '\033[32m')
  FMT_YELLOW=$(printf '\033[33m')
  FMT_BLUE=$(printf '\033[34m')
  FMT_BOLD=$(printf '\033[1m')
  FMT_RESET=$(printf '\033[0m')
}

print_ztnet() {
    printf '%s  %s______    %s___________   %s_____  %s___    %s_______  %s___________  %s\n'      $FMT_RAINBOW $FMT_RESET
    printf '%s %s("      "\%s("     _   ") %s(\"   \ %s|\"  \  %s/\"     "| %s("    _   ") %s\n'  $FMT_RAINBOW $FMT_RESET
    printf '%s  %s\___/   :)%s))__/  \\__/  %s|.\\\   %s\    | %s(: ______) %s )__/ \\__/  %s\n'  $FMT_RAINBOW $FMT_RESET
    printf '%s    %s/  ___/    %s\\_  /     %s|: \   %s \   |  %s\/   |      %s\\_  /        %s\n'  $FMT_RAINBOW $FMT_RESET
    printf '%s   %s//  \__     %s|.  |     %s|.  \  %s  \. | %s// ___)_     %s|.  |        %s\n'  $FMT_RAINBOW $FMT_RESET
    printf '%s  %s(:   / "\    %s\:  |     %s|    \   %s \ | %s(:      "|   %s\:  |        %s\n'  $FMT_RAINBOW $FMT_RESET
    printf '%s   %s\_______)    %s\__|     %s \___|\ %s___\) %s\_______)    %s \__|         %s\n'  $FMT_RAINBOW $FMT_RESET
    printf '\n\n'
}

setup_color
print_ztnet

##     ##    ###    ########  ####    ###    ########  ##       ########  ######  
##     ##   ## ##   ##     ##  ##    ## ##   ##     ## ##       ##       ##    ## 
##     ##  ##   ##  ##     ##  ##   ##   ##  ##     ## ##       ##       ##       
##     ## ##     ## ########   ##  ##     ## ########  ##       ######    ######  
 ##   ##  ######### ##   ##    ##  ######### ##     ## ##       ##             ## 
  ## ##   ##     ## ##    ##   ##  ##     ## ##     ## ##       ##       ##    ## 
   ###    ##     ## ##     ## #### ##     ## ########  ######## ########  ######  

INSTALLER_LAST_UPDATED="2026-10-06"
ZEROTIER_VERSION="1.14.2"
DNF_PROGRAMS=("git" "curl" "jq" "tar" "findutils")
HOST_OS=$(( cat /etc/*release || uname -om ) 2>/dev/null | head -n1)
INSTALL_NODE=false
SILENT_MODE=No
TEMP_INSTALL_DIR="/tmp/ztnet"
TEMP_REPO_DIR="$TEMP_INSTALL_DIR/repo"
TARGET_DIR="/opt/ztnet"
NODE_MAJOR=20
UNINSTALL=0
DATABASE_URL=""

# Architecture mapping
ARCH="$(uname -m)"
case "$ARCH" in
    "x86_64")
        ARCH="amd64"
        ;;
    "aarch64")
        ARCH="arm64"
        ;;
    *)
        printf "\n>>> Unsupported architecture: %s\n" "$ARCH"
        exit 1
        ;;
esac

# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
NC=$(tput sgr0) # No Color

# Check for root/sudo execution
if [[ $EUID -ne 0 ]]; then
  printf "\n${RED}This script must be run as root (sudo). Exiting.${NC}\n\n"
  exit 1
fi

# Operating System Detection (Rocky Linux / RHEL family)
if [ -f /etc/os-release ]; then
  # Source os-release in subshell to avoid overwriting existing environment vars
  DISTRO_ID=$(grep -E '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
  DISTRO_ID_LIKE=$(grep -E '^ID_LIKE=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
  DISTRO_VERSION_ID=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
  DISTRO_NAME=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
else
  printf "\n${RED}Unable to detect operating system (/etc/os-release not found). Exiting.${NC}\n"
  exit 1
fi

if [[ "$DISTRO_ID" != "rocky" && "$DISTRO_ID" != "almalinux" && "$DISTRO_ID" != "rhel" && "$DISTRO_ID_LIKE" != *"rhel"* && "$DISTRO_ID_LIKE" != *"fedora"* ]]; then
  printf "\n${RED}This script is designed for Rocky Linux and RHEL-compatible distributions.${NC}\n"
  printf "Detected system: %s. Exiting.\n" "${DISTRO_NAME:-$DISTRO_ID}"
  exit 1
fi

EL_VERSION=$(echo "$DISTRO_VERSION_ID" | cut -d'.' -f1)
[ -z "$EL_VERSION" ] && EL_VERSION="9"

# We need openssl early in the script
if ! command -v openssl >/dev/null 2>&1; then
  sudo dnf install -y openssl
fi

# File path to the .env file
TARGET_ENV_FILE="$TARGET_DIR/.env"
TEMP_ENV_FILE="$TEMP_REPO_DIR/.env"

# trap errors
exec 3>&1 4>&2
trap 'cleanup; exit' SIGINT

# Remove directories and then recreate the target directory
rm -rf "$TEMP_INSTALL_DIR" "$TARGET_DIR/.next" "$TARGET_DIR/prisma" "$TARGET_DIR/src" "$TARGET_DIR/public"
mkdir -p "$TARGET_DIR"

# Function to check if a command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Create a temporary directory for the installation
mkdir -p "$TEMP_INSTALL_DIR"
cd "$TEMP_INSTALL_DIR"

# Function to ask a Yes/No question
ask_question() {
    local question=$1
    local default_answer=$2
    local varname=$3

    echo -ne "\033[32m❔\033[0m${YELLOW} $question (Yes/No) [Default: $default_answer]: ${NC}"
    read -r reply < /dev/tty

    if [[ -z "$reply" ]]; then
        reply=$default_answer
        tput cuu1
        tput cuf $((${#question} + ${#default_answer} + 26))
        echo -n "$reply"
        echo 
    fi

    while true; do
        case "$reply" in
            [Yy]*)
                eval "$varname='Yes'"
                break
                ;;
            [Nn]* | "")
                eval "$varname='No'"
                break
                ;;
            *) 
                echo -n "Invalid response. Please answer Yes or No: "
                read -r reply
                ;;
        esac
    done
}

ask_string() {
    local question=$1
    local default_value=$2
    local varname=$3

    echo -ne "\033[32m❔\033[0m${YELLOW} $question [Default: $default_value]:${NC}"
    read -r ask_string < /dev/tty
  
    if [ -z "$ask_string" ]; then
        ask_string=$default_value
        tput cuu1
        tput cuf $((${#question} + ${#default_value} + 17))
        echo -n "$ask_string"
        echo
    fi

    eval "$varname='$ask_string'"
}

silent() {
    local output
    local status
    local command="$@"
    
    if [ "$SILENT_MODE" = "Yes" ]; then
        output="$($command 2>&1)"
        status=$?

        if echo "$output" | grep -q "out of memory"; then
            failure $BASH_LINENO "$command" "$status" "Out of Memory"
        elif [ $status -ne 0 ]; then
            failure $BASH_LINENO "$command" "$status" "$output"
        fi
    fi
}

verbose() {
    local output
    local status
    local command="$@"

    output=$($command 2>&1 | tee /dev/tty)
    status=$?

    if echo "$output" | grep -q "out of memory"; then
        failure $BASH_LINENO "$command" "$status" "Out of Memory"
    elif [ $status -ne 0 ]; then
        failure $BASH_LINENO "$command" "$status" "$output"
    fi
}

# Functions to manage environment variables in .env files
set_env_temp_var() {
  local key="$1"
  local value="$2"

  if [[ ! -f "$TEMP_ENV_FILE" ]]; then
    touch "$TEMP_ENV_FILE"
  fi

  if grep -qE "^$key=" "$TEMP_ENV_FILE" ; then
    sed -i "s|^$key=.*|$key=$value|" "$TEMP_ENV_FILE"
  else
    echo "$key=$value" >> "$TEMP_ENV_FILE"
  fi
}

set_env_target_var() {
  local key="$1"
  local value="$2"

  if [[ ! -f "$TARGET_ENV_FILE" ]]; then
    touch "$TARGET_ENV_FILE"
  fi

  if grep -qE "^$key=" "$TARGET_ENV_FILE" ; then
    sed -i "s|^$key=.*|$key=$value|" "$TARGET_ENV_FILE"
  else
    echo "$key=$value" >> "$TARGET_ENV_FILE"
  fi
}

CURRENT_TASK=""
print_status() {
    local message=$1

    if [ ! -z "$CURRENT_TASK" ]; then
        printf "\r\033[K ${GREEN}[✔]${NC} $CURRENT_TASK\n"
    fi

    printf "\r\033[K [-]  $message"
    CURRENT_TASK="$message"
}

function failure() {
  cleanup

  local _bash_lineno=$1
  local _last_command=$2
  local _exitcode=$3
  local _output=$4
  local formatted_output=$(echo "$_output" | tr '\n' ' ' | sed 's/  */ /g')

  local uname=$(uname -a | sed -e 's/"//g')
  local disk_space=$(df -m | awk 'NR>1 {print $1": "$4"MB"}' | xargs)

  local total_mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  local total_mem_mb=$((total_mem_kb / 1024))

  printf "\n${RED}An error occurred! ${NC}\n" >&2

  if command -v jq >/dev/null 2>&1; then
      jsonError=$(jq -n --arg kernel "$uname" \
          --arg runner "ztnet rocky linux" \
          --arg arch "$ARCH" \
          --arg os "$HOST_OS" \
          --arg command "$_last_command" \
          --arg exitcode "$_exitcode" \
          --arg disk "$disk_space" \
          --arg memory "$total_mem_mb"MB \
          --arg output "$formatted_output" \
          --arg timestamp "$(date +"%d-%m-%Y/%M:%S")" \
          --arg lineno "$_bash_lineno" \
          '{runner: $runner, kernel: $kernel, command: $command, output: $output, exitcode: $exitcode, disk: $disk, memory: $memory, lineno:$lineno, arch: $arch, os: $os, timestamp: $timestamp}')
  else
      jsonError="{\"kernel\": \"$uname\", \"runner\": \"ztnet rocky linux\", \"arch\": \"$ARCH\", \"os\": \"$HOST_OS\", \"command\": \"$_last_command\",  \"disk\": \"$disk_space\",  \"memory\": \"$total_mem_mb\", \"output\": \"$formatted_output\", \"exitcode\": \"$_exitcode\", \"timestamp\": \"$(date +"%d-%m-%Y/%M:%S")\", \"lineno\": \"$_bash_lineno\"}"
      jsonError=$(echo $jsonError | sed ':a;N;$!ba;s/\n/\\n/g')
  fi

  echo -e "\n${RED}Error report:${NC}\n$jsonError\n"
  echo -e "\nDo you want to send the error report to ztnet.network admin for application improvements?"
  echo -e "Only the above error message will be sent! [Default No]"
  sleep 0.1
  ask_string "Yes / No ==> " "No" SEND_REPORT

  if [ -z "$SEND_REPORT" ]; then
      SEND_REPORT="No"
  fi

  case $SEND_REPORT in
    y | Y | yes | YES | Yes) 
      print_status ">>> Generating Report..."
      print_status ">>> Transmitting..."
      curl --insecure --max-time 10 \
      -d "$jsonError" \
      -H 'Content-Type: application/json' \
      -X POST "http://install.ztnet.network/post/error"
      ;;
    *)
      printf "Exiting! Please create new issue at https://github.com/sinamics/ztnet/issues/new/choose with the above information\n"
      exit 1 
      ;;
  esac
  exit 1
}

function cleanup() {
  printf "\n\nCleaning up...\n"
  if [ "$SILENT_MODE" = "Yes" ]; then
      stop_spinner "$SPINNER_PID"
  fi
  rm -rf "$TEMP_INSTALL_DIR"
  tput cnorm
}

start_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\\'

    tput civis
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "\r [\033[34m%c\033[0m]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r\033[K"
}

stop_spinner() {
    kill "$1" 2>/dev/null
    exec 3>&-
    print_status "Operation completed."
}

# Detect primary local IP address
local_ip=$(hostname -I | awk '{print $1}')

is_package_installed() {
    rpm -q "$1" > /dev/null 2>&1
    return $?
}

memory_warning() {
  local total_mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  local total_mem_mb=$((total_mem_kb / 1024))

  if [ "$total_mem_mb" -le 1024 ]; then
      printf "\n"
      echo "${YELLOW}Warning: Your system's total memory is only ${total_mem_mb}MB. Next.js build may require additional swap/RAM.${NC}"
      read -n 1 -s -r -p "Press any key to continue..." < /dev/tty
  fi
}

while getopts v:b:su option 
do 
 case "${option}" 
 in 
 v) CUSTOM_VERSION=${OPTARG};;
 b) BRANCH=${OPTARG};;
 s) SILENT_MODE=Yes;;
 u) UNINSTALL=1;;
 esac 
done

# Uninstall procedure
if [ "$UNINSTALL" = 1 ]; then
  UNINSTALL_ZTNET=No

  printf "\n\n${YELLOW}ZTNET uninstallation script (Rocky Linux).${NC}\n"
  printf "This script will perform the following actions:\n"
  printf "  1. Stop the ZTnet service.\n"
  printf "  2. Remove the ZTnet systemd service.\n"
  printf "  3. Remove the ZTnet directory (/opt/ztnet).\n"
  printf "  4. Remove zerotier-one package via dnf.\n\n"
  printf "NOTE: Your cloud database will not be affected.\n\n"

  ask_question "Do you want to uninstall ZTnet?" No UNINSTALL_ZTNET
  
  if [ "$UNINSTALL_ZTNET" = "No" ]; then
    exit 0
  fi
  
  print_status "Uninstalling ZTnet..."

  if systemctl is-active --quiet ztnet; then
    print_status "Stopping ZTnet service..."
    sudo systemctl stop ztnet
  fi

  if is_package_installed "zerotier-one"; then
    print_status "Removing zerotier-one..."
    sudo dnf remove -y zerotier-one > /dev/null 2>&1
  fi

  print_status "Removing ZTnet directory..."
  sudo rm -rf /opt/ztnet > /dev/null 2>&1

  print_status "Removing ZTnet systemd service..."
  sudo rm -f /etc/systemd/system/ztnet.service > /dev/null 2>&1
  
  print_status "Reloading systemd daemon..."
  sudo systemctl daemon-reload > /dev/null 2>&1

  printf "\n\nZTnet has been completely removed.\n"
  exit 0
fi

# Show welcome information
printf "Installer version: Rocky Linux & Cloud DB Edition (%s)\n" "$INSTALLER_LAST_UPDATED"
printf "\n${YELLOW}ZTNET installation script.${NC}\n"
printf "Target Platform: %s (EL %s)\n" "${DISTRO_NAME:-Rocky Linux}" "$EL_VERSION"
printf "This script will perform the following actions:\n"
printf "  1. Connect to your Cloud PostgreSQL database (e.g. Supabase).\n"
printf "  2. Ensure Node.js version %s is installed via NodeSource.\n" "$NODE_MAJOR"
printf "  3. Install ZeroTier %s via official ZeroTier RPM repository.\n" "$ZEROTIER_VERSION"
printf "  4. Clone the ZTnet repository and build Next.js artifacts.\n"
printf "  5. Deploy artifacts to %s and configure systemd.\n" "$TARGET_DIR"
printf "  6. Configure firewalld (ports 3000/tcp, 9993/udp) and SELinux.\n\n"

# Prompt for IP address / domain
if [ ! -f "$TARGET_ENV_FILE" ]; then
  ask_string "Enter the ZTnet server IP address or domain name" "$local_ip" input_ip
fi

# Prompt for Cloud Database URL
prompt_cloud_database_url() {
  local existing_url=""
  if [ -f "$TARGET_ENV_FILE" ]; then
    existing_url=$(grep -E '^DATABASE_URL=' "$TARGET_ENV_FILE" | cut -d'=' -f2- | tr -d '"')
  fi

  if [ -n "$existing_url" ]; then
    DATABASE_URL="$existing_url"
    print_status "Found existing DATABASE_URL in $TARGET_ENV_FILE"
  else
    printf "\n${YELLOW}=== Cloud Database Configuration (Supabase / Remote Postgres) ===${NC}\n"
    printf "Please provide your PostgreSQL connection URL.\n"
    printf "Example (Supabase direct connection):\n"
    printf "  postgresql://postgres:[PASSWORD]@db.[PROJECT-REF].supabase.co:5432/postgres?sslmode=require\n\n"

    while true; do
      ask_string "Enter your PostgreSQL DATABASE_URL" "" input_db_url
      if [[ "$input_db_url" =~ ^postgres(ql)?:// ]]; then
        DATABASE_URL="$input_db_url"
        break
      else
        printf "${RED}Invalid format! Connection string must begin with postgresql:// or postgres://${NC}\n"
      fi
    done
  fi
}

prompt_cloud_database_url

ask_question "Use silent (non-verbose) installation with minimal output?" Yes SILENT_MODE
memory_warning

printf "\n"
print_status "Starting installation for Rocky Linux..."

if [ "$SILENT_MODE" = "Yes" ]; then
    STD="silent"
    sleep 86400 &
    SPINNER_PID=$!
    start_spinner "$SPINNER_PID" &
else
    STD="verbose"
fi

# Package cache and base dependencies
print_status "Updating dnf package cache..."
$STD sudo dnf makecache -y

install_dnf_packages() {
  for program in "${DNF_PROGRAMS[@]}"; do
      if ! command_exists "$program"; then
          print_status "Installing $program..."
          $STD sudo dnf install -y "$program"
      else
          print_status "$program is already installed."
      fi
  done
}

install_dnf_packages

# Determine server IP
server_ip=${input_ip:-$local_ip}
if [[ $server_ip != http://* && $server_ip != https://* ]]; then
    server_ip="http://${server_ip}"
fi

check_existing_env_handler() {
  declare -A env_vars=(
    ["NEXTAUTH_SECRET"]=$(openssl rand -hex 32)
    ["NEXTAUTH_URL"]="${server_ip}:3000"
    ["ZT_ADDR"]=
    ["ZT_SECRET"]=
    ["DATABASE_URL"]="$DATABASE_URL"
  )

  if [ -f "$TARGET_ENV_FILE" ]; then
    print_status "Found existing .env file. Reading variables from it..."
    env_content=$(<"$TARGET_ENV_FILE")

    extract_env_value() {
      echo "$env_content" | grep "^$1=" | cut -d '=' -f2- | tr -d '"'
    }

    for var in "${!env_vars[@]}"; do
      local val=$(extract_env_value "$var")
      if [ -n "$val" ]; then
        declare -g "$var=$val"
      else
        declare -g "$var=${env_vars[$var]}"
      fi
    done
  else
    for var in "${!env_vars[@]}"; do
      declare -g "$var=${env_vars[$var]}"
    done
  fi
}

check_existing_env_handler

# Node.js installation via NodeSource RPM
setup_nodejs(){
  if ! command_exists node || ! command_exists npm; then
    INSTALL_NODE=true
  else
    NODE_VERSION=$(node -v | cut -d 'v' -f 2 | cut -d '.' -f 1)
    if [ "$NODE_VERSION" -lt "$NODE_MAJOR" ]; then
      INSTALL_NODE=true
    fi
  fi

  if [ "$INSTALL_NODE" = true ]; then
    print_status "Configuring NodeSource RPM repository for Node.js $NODE_MAJOR..."
    $STD curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | sudo bash -
    print_status "Installing Node.js $NODE_MAJOR..."
    $STD sudo dnf install -y nodejs
  fi
}

setup_nodejs
export NODE_OPTIONS=--dns-result-order=ipv4first

# Validate Cloud Database Network Connectivity using Node.js
validate_cloud_db_connectivity() {
  print_status "Testing Cloud Database connectivity..."
  local test_result
  test_result=$(node -e '
    try {
      const { URL } = require("url");
      const net = require("net");
      const dbUrl = process.env.DATABASE_URL;
      if (!dbUrl) process.exit(1);
      const parsed = new URL(dbUrl);
      const host = parsed.hostname;
      const port = parseInt(parsed.port) || 5432;
      const client = net.createConnection({ host, port, timeout: 8000 }, () => {
        client.end();
        process.exit(0);
      });
      client.on("error", (err) => {
        console.error("Socket error: " + err.message);
        process.exit(2);
      });
      client.on("timeout", () => {
        client.destroy();
        console.error("Connection timed out after 8s");
        process.exit(3);
      });
    } catch (e) {
      console.error("URL error: " + e.message);
      process.exit(4);
    }
  ' 2>&1)
  local test_status=$?

  if [ $test_status -eq 0 ]; then
    print_status "Cloud Database endpoint is reachable."
  else
    if [ "$SILENT_MODE" = "Yes" ]; then
      stop_spinner "$SPINNER_PID" 2>/dev/null
    fi
    printf "\n${YELLOW}Notice: Could not establish TCP connection to the database endpoint:${NC}\n"
    printf "${RED}%s${NC}\n" "$test_result"
    printf "Please verify that your Supabase / Cloud Postgres host is active and accessible.\n"
    ask_question "Do you want to proceed anyway?" No PROCEED_DB
    if [ "$PROCEED_DB" != "Yes" ]; then
      exit 1
    fi
    if [ "$SILENT_MODE" = "Yes" ]; then
      sleep 86400 &
      SPINNER_PID=$!
      start_spinner "$SPINNER_PID" &
    fi
  fi
}

validate_cloud_db_connectivity

# ZeroTier Installation via RPM Repository
setup_zerotier(){
  if ! command_exists zerotier-cli; then
      print_status "Configuring ZeroTier RPM repository (EL $EL_VERSION)..."

      cat <<EOF | sudo tee /etc/yum.repos.d/zerotier.repo > /dev/null
[zerotier]
name=ZeroTier, Inc. RPM Release Repository
baseurl=https://download.zerotier.com/redhat/el/$EL_VERSION
enabled=1
gpgcheck=1
gpgkey=https://download.zerotier.com/contact@zerotier.com.gpg
EOF

      print_status "Installing ZeroTier..."
      if ! $STD sudo dnf install -y "zerotier-one-${ZEROTIER_VERSION}"; then
        print_status "Installing latest available zerotier-one package..."
        $STD sudo dnf install -y zerotier-one
      fi

      print_status "Configuring ZeroTier service..."
      $STD sudo systemctl daemon-reload
      $STD sudo systemctl enable zerotier-one
      $STD sudo systemctl start zerotier-one

      print_status "Waiting for ZeroTier identity generation..."
      while [ ! -f /var/lib/zerotier-one/identity.secret ]; do
          sleep 1
      done

      if [ -f /var/lib/zerotier-one/identity.public ]; then
          ZT_ADDRESS=$(cat /var/lib/zerotier-one/identity.public | cut -d: -f1)
          print_status "ZeroTier installed successfully! Address: $ZT_ADDRESS"
      fi
  else
      print_status "ZeroTier is already installed."
  fi
}

setup_zerotier

# Repository Clone & Build
pull_checkout_ztnet(){
  if [[ ! -d "$TEMP_REPO_DIR/.git" ]]; then
    print_status "Initializing repository..."
    $STD git clone --depth 1 --no-single-branch https://github.com/sinamics/ztnet.git "$TEMP_REPO_DIR"
    cd "$TEMP_REPO_DIR"
    $STD git config core.sparseCheckout true
    mkdir -p .git/info
    cat > .git/info/sparse-checkout <<-EOF
/*
!/.devcontainer/*
!/.github/*
!/.vscode/*
!/install.ztnet/*
!/docs/*
docs/images/logo
EOF
    $STD git read-tree -mu HEAD
    print_status "Cloned ZTnet repository (minimal version)."
  else
    print_status "$TEMP_REPO_DIR already exists. Updating the repository."
    cd "$TEMP_REPO_DIR"
    $STD git pull --depth 1 origin main
  fi

  if [[ -z "$BRANCH" ]]; then
    print_status "Fetching tags..."
    $STD git fetch --unshallow --tags || $STD git fetch --tags

    allTags=$(git tag --sort=-committerdate)

    if [[ -z "$allTags" ]]; then
      print_status "No tags found in the repository! Defaulting to main branch."
      $STD git checkout main
    else
      latestTag=$(echo "$allTags" | head -n 1)
      print_status "Checking out tag: ${CUSTOM_VERSION:-$latestTag}"
      $STD git checkout "${CUSTOM_VERSION:-$latestTag}"
    fi
  else
    print_status "Checking out branch: $BRANCH"
    $STD git checkout "$BRANCH"
  fi

  print_status "Installing npm dependencies..."
  $STD npm install
}

pull_checkout_ztnet

# Copy mkworld binary
if [ -f "$TEMP_REPO_DIR/ztnodeid/build/linux_$ARCH/ztmkworld" ]; then
  cp "$TEMP_REPO_DIR/ztnodeid/build/linux_$ARCH/ztmkworld" /usr/local/bin/ztmkworld
  chmod +x /usr/local/bin/ztmkworld
fi

NEXT_PUBLIC_APP_VERSION="${CUSTOM_VERSION:-$latestTag}"

# Set temporary environment variables for building
set_env_temp_var "DATABASE_URL" "$DATABASE_URL"
set_env_temp_var "ZT_ADDR" "$ZT_ADDR"
set_env_temp_var "NEXTAUTH_URL" "$NEXTAUTH_URL"
set_env_temp_var "NEXT_PUBLIC_APP_VERSION" "$NEXT_PUBLIC_APP_VERSION"
set_env_temp_var "NEXTAUTH_SECRET" "$NEXTAUTH_SECRET"

export DATABASE_URL

# Prisma Database Migrations & Next.js Build
print_status "Applying database migrations to Cloud Database..."
$STD npx prisma migrate deploy

print_status "Seeding database..."
$STD npx prisma db seed

print_status "Building ZTnet artifacts... This may take a while."
$STD npm run build

# Deploy Artifacts
print_status "Copying files to $TARGET_DIR..."
mkdir -p "$TARGET_DIR"
mkdir -p "$TARGET_DIR/.next/standalone"
mkdir -p "$TARGET_DIR/prisma"

cp "$TEMP_REPO_DIR/next.config.mjs" "$TARGET_DIR/"
cp -r "$TEMP_REPO_DIR/public" "$TARGET_DIR/"
cp "$TEMP_REPO_DIR/package.json" "$TARGET_DIR/package.json"

cp -a "$TEMP_REPO_DIR/.next/standalone/." "$TARGET_DIR/"
cp -r "$TEMP_REPO_DIR/.next/static" "$TARGET_DIR/.next/static"
cp -r "$TEMP_REPO_DIR/prisma" "$TARGET_DIR/prisma"

# Populate production .env file
set_env_target_var "DATABASE_URL" "$DATABASE_URL"
set_env_target_var "ZT_ADDR" "$ZT_ADDR"
set_env_target_var "NEXTAUTH_URL" "$NEXTAUTH_URL"
set_env_target_var "NEXT_PUBLIC_APP_VERSION" "$NEXT_PUBLIC_APP_VERSION"
set_env_target_var "NEXTAUTH_SECRET" "$NEXTAUTH_SECRET"
chmod 600 "$TARGET_ENV_FILE"

# Setup systemd service
print_status "Creating systemd service..."
cat > /etc/systemd/system/ztnet.service <<EOL
[Unit]
Description=ZTnet Service
After=network.target zerotier-one.service

[Service]
EnvironmentFile=$TARGET_DIR/.env
ExecStart=/usr/bin/node "$TARGET_DIR/server.js"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOL

# Security: Configure firewalld and SELinux
configure_firewall_and_selinux() {
  if command_exists firewall-cmd && systemctl is-active --quiet firewalld; then
    print_status "Configuring firewalld rules (3000/tcp, 9993/udp)..."
    $STD sudo firewall-cmd --permanent --add-port=3000/tcp
    $STD sudo firewall-cmd --permanent --add-port=9993/udp
    $STD sudo firewall-cmd --reload
    print_status "Firewalld configured: opened ports 3000/tcp and 9993/udp."
  fi

  if command_exists getenforce; then
    local selinux_status
    selinux_status=$(getenforce 2>/dev/null)
    if [ "$selinux_status" = "Enforcing" ]; then
      print_status "SELinux is Enforcing. Setting network connection permissions..."
      if command_exists setsebool; then
        $STD sudo setsebool -P httpd_can_network_connect 1 2>/dev/null || true
      fi
    fi
  fi
}

configure_firewall_and_selinux

# Enable and start the service
print_status "Starting ZTnet service..."
$STD sudo systemctl daemon-reload
$STD sudo systemctl enable ztnet
$STD sudo systemctl restart ztnet

sleep 4

cleanup

# Summary for the user
echo -e "\n${GREEN}===============================================${NC}"
echo -e "${GREEN}      ZTnet Installation Completed!           ${NC}"
echo -e "${GREEN}===============================================${NC}"
echo -e "- Platform: ${YELLOW}${DISTRO_NAME:-Rocky Linux} (EL $EL_VERSION)${NC}"
echo -e "- ZTnet Location: ${GREEN}/opt/ztnet${NC}"
echo -e "- Database: ${GREEN}Cloud Database Configured${NC}"
echo -e "- Service Status: ${YELLOW}sudo systemctl status ztnet${NC}"
echo -e "- Stop Service:   ${YELLOW}sudo systemctl stop ztnet${NC}"
echo -e "- View Logs:      ${YELLOW}sudo journalctl -u ztnet -f${NC}"
echo -e "- Config File:    ${YELLOW}/opt/ztnet/.env${NC}"

echo -e "\nZTnet is accessible at: ${YELLOW}${server_ip}:3000${NC}\n"