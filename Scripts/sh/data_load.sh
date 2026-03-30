#!/bin/bash
set -e

# ============================================================
# data_load.sh — Deploy configurations to a Salesforce org
# ============================================================
# Prerequisites: Node.js, Salesforce CLI (sf), jq, curl
# This script will attempt to install missing dependencies
# automatically on Debian/Ubuntu-based systems.
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "======================================"
echo "  LSStarter Config — Data Load"
echo "======================================"
echo ""

# ----------------------------------------------------------
# 1. Dependency checks & auto-install
# ----------------------------------------------------------
echo "Checking dependencies..."

install_pkg() {
  local pkg="$1"
  if command -v apt-get &> /dev/null; then
    echo -e "  ${YELLOW}Installing $pkg via apt...${NC}"
    sudo apt-get update -qq && sudo apt-get install -y -qq "$pkg"
  elif command -v brew &> /dev/null; then
    echo -e "  ${YELLOW}Installing $pkg via brew...${NC}"
    brew install "$pkg"
  else
    echo -e "  ${RED}Error: Cannot auto-install $pkg. Please install it manually.${NC}"
    exit 1
  fi
}

# jq
if ! command -v jq &> /dev/null; then
  echo -e "  ${YELLOW}jq not found.${NC}"
  install_pkg jq
fi
echo -e "  ${GREEN}✓ jq$(jq --version 2>/dev/null | head -1)${NC}"

# curl
if ! command -v curl &> /dev/null; then
  echo -e "  ${YELLOW}curl not found.${NC}"
  install_pkg curl
fi
echo -e "  ${GREEN}✓ curl$(curl --version 2>/dev/null | head -1 | awk '{print " "$2}')${NC}"

# Node.js
if ! command -v node &> /dev/null; then
  echo -e "  ${YELLOW}Node.js not found. Installing LTS...${NC}"
  if command -v apt-get &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y -qq nodejs
  elif command -v brew &> /dev/null; then
    brew install node
  else
    echo -e "  ${RED}Error: Cannot auto-install Node.js. Please install it manually.${NC}"
    exit 1
  fi
fi
echo -e "  ${GREEN}✓ node $(node --version)${NC}"

# Salesforce CLI (sf)
if ! command -v sf &> /dev/null; then
  echo -e "  ${YELLOW}Salesforce CLI (sf) not found. Installing...${NC}"
  sudo npm install -g @salesforce/cli
fi
echo -e "  ${GREEN}✓ sf $(sf --version 2>/dev/null | head -1)${NC}"

echo ""

# ----------------------------------------------------------
# 2. Org selector
# ----------------------------------------------------------

login_new_org() {
  echo ""
  echo "  [1] Production (login.salesforce.com)"
  echo "  [2] Sandbox    (test.salesforce.com)"
  echo ""
  read -rp "  Environment: " ENV_CHOICE
  case "$ENV_CHOICE" in
    1) sf org login web --instance-url https://login.salesforce.com --set-default ;;
    2) sf org login web --instance-url https://test.salesforce.com --set-default ;;
    *) echo -e "${RED}Invalid choice.${NC}"; exit 1 ;;
  esac
  ORG_USER=$(sf org display --json 2>/dev/null | jq -r '.result.username // "unknown"')
  echo -e "  ${GREEN}✓ Authenticated as: ${ORG_USER}${NC}"
}

echo "Loading authenticated Salesforce orgs..."

ORG_LIST=$(sf org list --json 2>/dev/null | jq -r '
  (.result.nonScratchOrgs // []) + (.result.scratchOrgs // [])
  | .[]
  | select(.connectedStatus == "Connected")
  | .username + (if .alias then " (" + .alias + ")" else "" end)
    + (if .isDefaultUsername then " [default]" else "" end)
' 2>/dev/null)

if [ -z "$ORG_LIST" ]; then
  echo -e "${YELLOW}No connected orgs found.${NC}"
  echo ""
  echo "  [1] Login to a new org"
  echo "  [0] Exit"
  read -rp "Choice: " CHOICE
  case "$CHOICE" in
    1)
      login_new_org
      ;;
    *)
      echo "Exiting."
      exit 0
      ;;
  esac
else
  echo ""
  echo "Select the target org:"
  echo ""

  # Build array from org list
  mapfile -t ORGS <<< "$ORG_LIST"
  for i in "${!ORGS[@]}"; do
    echo "  [$((i+1))] ${ORGS[$i]}"
  done
  echo "  [$((${#ORGS[@]}+1))] Login to a new org"
  echo "  [0] Exit"
  echo ""
  read -rp "Choice: " CHOICE

  if [ "$CHOICE" = "0" ]; then
    echo "Exiting."
    exit 0
  elif [ "$CHOICE" = "$((${#ORGS[@]}+1))" ]; then
    login_new_org
  elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "${#ORGS[@]}" ]; then
    SELECTED_USER=$(echo "${ORGS[$((CHOICE-1))]}" | awk '{print $1}')
    sf config set target-org="$SELECTED_USER" --global 1>/dev/null
    echo -e "  ${GREEN}✓ Target org set to: ${SELECTED_USER}${NC}"
    ORG_USER="$SELECTED_USER"
  else
    echo -e "${RED}Invalid choice.${NC}"
    exit 1
  fi
fi
echo ""

# ----------------------------------------------------------
# 3. Deploy configurations
# ----------------------------------------------------------
echo "Deploying configurations..."
echo ""

echo "  [1/4] Deploying profile..."
if sf project deploy start -d "PackageComponents/profiles/LSC Custom Profile.profile-meta.xml" --json 1>/dev/null 2>/dev/null; then
  echo -e "  ${GREEN}✓ Profile deployed${NC}"
else
  echo -e "  ${RED}✗ Profile deploy failed. Run without --json to see details.${NC}"
  exit 1
fi

echo "  [2/4] Importing metadata records..."
if sf data import tree --plan LSConfig/lifeSciMetadataRecord/LifeSciMetadataCategory-plan.json --json 1>/dev/null 2>/dev/null; then
  echo -e "  ${GREEN}✓ Metadata records imported${NC}"
else
  echo -e "  ${YELLOW}⚠ Data import had errors (duplicates may already exist). Continuing...${NC}"
fi

echo "  [3/4] Deploying config records..."
if sf project deploy start -d LSConfig/lifeSciConfigRecord --json 1>/dev/null 2>/dev/null; then
  echo -e "  ${GREEN}✓ Config records deployed${NC}"
else
  echo -e "  ${RED}✗ Config records deploy failed. Run without --json to see details.${NC}"
  exit 1
fi

echo "  [4/4] Activating trigger handlers..."
if bash Scripts/sh/activate_trigger_handlers.sh --file TriggerHandlers/TriggerHandlers.ts; then
  echo -e "  ${GREEN}✓ Trigger handlers activated${NC}"
else
  echo -e "  ${RED}✗ Trigger handler activation failed.${NC}"
  exit 1
fi

echo ""
echo "======================================"
echo -e "${GREEN}  Data load complete! 🚀${NC}"
echo "======================================"