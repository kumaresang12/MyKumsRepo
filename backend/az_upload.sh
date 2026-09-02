#!/usr/bin/env bash
set -euo pipefail

AZURE_CLIENT_ID="${AZURE_CLIENT_ID:-}"
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET:-}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-}"
AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-}"

usage() {
  echo "Usage: $0 <local-file-path> <container-name> [blob-name]"
  echo ""
  echo "Environment variables required:"
  echo "  AZURE_CLIENT_ID        — Service principal app/client ID"
  echo "  AZURE_CLIENT_SECRET    — Service principal client secret"
  echo "  AZURE_TENANT_ID        — Azure AD tenant ID"
  echo "  AZURE_STORAGE_ACCOUNT  — Target storage account name"
  echo ""
  echo "Example:"
  echo "  export AZURE_CLIENT_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'"
  echo "  export AZURE_CLIENT_SECRET='your-secret-value'"
  echo "  export AZURE_TENANT_ID='xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'"
  echo "  export AZURE_STORAGE_ACCOUNT='mystorageaccount'"
  echo "  $0 /path/to/file.txt my-container file.txt"
  exit 1
}

if [[ $# -lt 2 ]]; then
  usage
fi

LOCAL_FILE="$1"
CONTAINER_NAME="$2"
BLOB_NAME="${3:-$(basename "$LOCAL_FILE")}"   # Default blob name = filename

check_var() {
  local var_name="$1"
  local var_value="$2"
  if [[ -z "$var_value" ]]; then
    echo "[ERROR] Required variable '$var_name' is not set."
    exit 1
  fi
}

check_var "AZURE_CLIENT_ID"       "$AZURE_CLIENT_ID"
check_var "AZURE_CLIENT_SECRET"   "$AZURE_CLIENT_SECRET"
check_var "AZURE_TENANT_ID"       "$AZURE_TENANT_ID"
check_var "AZURE_STORAGE_ACCOUNT" "$AZURE_STORAGE_ACCOUNT"

if [[ ! -f "$LOCAL_FILE" ]]; then
  echo "[ERROR] File not found: $LOCAL_FILE"
  exit 1
fi

# Check Azure CLI is installed
if ! command -v az &>/dev/null; then
  echo "[ERROR] Azure CLI (az) is not installed."
  echo "  Install with: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
  exit 1
fi

echo "[INFO] Authenticating with Azure (Service Principal)..."
az login \
  --service-principal \
  --username  "$AZURE_CLIENT_ID" \
  --password  "$AZURE_CLIENT_SECRET" \
  --tenant    "$AZURE_TENANT_ID" \
  --output    none

echo "[INFO] Authentication successful."

echo "[INFO] Uploading '$LOCAL_FILE' → storage account '$AZURE_STORAGE_ACCOUNT' / container '$CONTAINER_NAME' / blob '$BLOB_NAME'..."

az storage blob upload \
  --account-name  "$AZURE_STORAGE_ACCOUNT" \
  --container-name "$CONTAINER_NAME" \
  --name          "$BLOB_NAME" \
  --file          "$LOCAL_FILE" \
  --auth-mode     login \
  --overwrite     true \
  --output        table

echo "[INFO] Upload complete."

az logout
echo "[INFO] Logged out of Azure CLI."
