#!/bin/bash

# Azure Cloud Storage Manager Script
# This script provides a simple interface to manage Azure Cloud Storage operations
# A simple script with deployment and file operations
#
# Usage:
#   ./azurestorage.sh <command> [args...]
#
# Commands:
#   deploy                Deploy Azure storage resources
#   upload <file> [name]  Upload a file to Azure storage
#   download <blob> [path] Download a blob from Azure storage
#   list                  List files in the Azure storage container
#   info <blob>           Show information about a blob in Azure storage
#
# Environment Variables:
#   AZURE_OUTPUT_FORMAT   Set output format for 'list' command (e.g., table, json, tsv, yaml)

set -e  # Exit immediately if a command exits with a non-zero status

# configurations 
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_file="${script_dir}/azure_storage.config"
log_file="${script_dir}/storage_operations.log"

# colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color 

# logging function
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
     echo -e "${GREEN}[LOG] $timestamp - $message${NC}"
    echo -e "${timestamp} - ${message}" >> "${log_file}"
}
# error handling function
error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR] $timestamp - $message${NC}"
    echo -e "${timestamp} - ${message}" >> "${log_file}"
    exit 1
}   
# Check Azure CLI installation
check_azure_cli() {
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it to proceed."
    else
        log "Azure CLI is installed."
    fi
}

# check azure login status
check_azure_login() {
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure CLI. Please log in using 'az login'."
    else
        log "User is logged in to Azure CLI."
    fi
}
# Generate unique names
generate_unique_name() {
    local timestamp=$(date +%Y%m%d%H%M%S)
    export RESOURCE_GROUP="GROUP2TECH-${timestamp}"
    export STORAGE_ACCOUNT="g2store${timestamp}"
    export CONTAINER_NAME="g2files${timestamp}"
    export LOCATION="uksouth"
    
}

# Save configurations to file
save_configurations() {
    local account_key=$(get_storage_key)   # fetch the key dynamically
    cat <<EOF > "${config_file}"
RESOURCE_GROUP=${RESOURCE_GROUP}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
CONTAINER_NAME=${CONTAINER_NAME}
LOCATION=${LOCATION}
ACCOUNT_KEY=${account_key}
EOF
    log "Configurations saved to ${config_file}"
}

# Load configurations from file
load_configurations() {
    if [[ -f "${config_file}" ]]; then
        source "${config_file}"
        log "Configurations loaded from ${config_file}"

        # If ACCOUNT_KEY not set, fetch dynamically
        if [[ -z "${ACCOUNT_KEY}" ]]; then
            ACCOUNT_KEY=$(get_storage_key)
            log "Fetched storage account key dynamically."
            fi
    else
        error "Configuration file not found. Please deploy first using: ${0} deploy"
        exit 1
    fi
}
# get access key for storage account
get_storage_key() {
    local account_key=$(az storage account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --query "[0].value" -o tsv)
        if [[ -z "${account_key}" ]]; then
            error "Failed to retrieve storage account key."
        fi
    echo "${account_key}"
}
# Deploy Azure Storage
deploy_storage() {
    log "Starting Azure Storage deployment..."
    check_azure_cli
    check_azure_login
    generate_unique_name

    log "Creating Resource Group: ${RESOURCE_GROUP}"
    az group create --name "${RESOURCE_GROUP}" --location "${LOCATION}" || error "Failed to create resource group."

    log "Creating Storage Account: ${STORAGE_ACCOUNT}"
    az storage account create \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --allow-blob-public-access true || error "Failed to create storage account."

    log "Creating Blob Container: ${CONTAINER_NAME}"
    local account_key=$(get_storage_key)
    az storage container create \
     --name "${CONTAINER_NAME}" \
     --account-name "${STORAGE_ACCOUNT}" \
     --account-key "${account_key}" \
     --public-access blob \
     || error "Failed to create blob container."

    save_configurations
    log "Deployment completed successfully."
}

# Upload file to Azure Storage
upload_file() {
    load_configurations
    local file_path="$1"
    local blob_name="${2:-$(basename "$file_path")}"
    local account_key=$(get_storage_key)

    if [[ ! -f "${file_path}" ]]; then
        error "File ${file_path} does not exist."
        return 1
    fi

    log "Uploading file ${file_path} -> ${blob_name} to container ${CONTAINER_NAME}"
    
    az storage blob upload \
    --container-name "${CONTAINER_NAME}" \
    --file "${file_path}" \
    --name "${blob_name}" \
    --account-name "${STORAGE_ACCOUNT}" \
    --account-key "${account_key}" \
    --overwrite || error "Failed to upload file."

    local public_url="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/${blob_name}"
    log "File uploaded Successfully to: ${public_url}"
    echo "Public URL: ${public_url}"
}

# Download file from Azure Storage
download_file() {
    load_configurations
    local blob_name="$1"
    local download_path="${2:-./${blob_name}}"
    local account_key=$(get_storage_key)

    log "Downloading blob ${blob_name} from container ${CONTAINER_NAME} to ${download_path}"

    az storage blob download \
    --container-name "${CONTAINER_NAME}" \
    --name "${blob_name}" \
    --file "${download_path}" \
    --account-name "${STORAGE_ACCOUNT}" \
    --account-key "${account_key}" \
    --overwrite || error "Failed to download file."

    log "File downloaded successfully to: ${download_path}"
}

# List Files
list_files() {
    load_configurations
    local account_key=$(get_storage_key)
    # You can control the output format by setting the AZURE_OUTPUT_FORMAT environment variable (e.g., table, json, tsv, yaml).
    local output_format="${AZURE_OUTPUT_FORMAT:-table}"
    local header="Listing files in container: ${CONTAINER_NAME}"
    local line_length=${#header}
    local separator
    separator=$(printf '%*s' "$line_length" '' | tr ' ' '=')

    log "${header}"
    log "Using output format: ${output_format}"
    
    # print clean header
    echo -e "${header}"
    echo "${separator}"

az storage blob list \
    --container-name "${CONTAINER_NAME}" \
    --account-name "${STORAGE_ACCOUNT}" \
    --account-key "${account_key}" \
    --query "[].{Name:name, Size:properties.contentLength, LastModified:properties.lastModified}" \
    --output "${output_format}"
}

# Delete File
delete_file() {
    load_configurations
    local blob_name="$1"
    if [[ -z "${blob_name}" ]]; then
        error "No blob name provided. Usage: ${0} delete <blob>"
    fi
        log "Deleting file: ${blob_name} from container ${CONTAINER_NAME}"
    

az storage blob delete \
    --container-name "${CONTAINER_NAME}" \
    --name "${blob_name}" \
    --account-name "${STORAGE_ACCOUNT}" \
    --account-key "${account_key}" || error "Failed to delete file."
    log "File ${blob_name} deleted successfully."
}

# Show file info
show_file_info() {
    load_configurations
    local blob_name="$1"

    # Validate input
    if [[ -z "${blob_name}" ]]; then
        error "No blob name provided. Usage: ${0} info <blob>"
    fi

    local account_key=$(get_storage_key)      
    log "Fetching info for file: ${blob_name} in container ${CONTAINER_NAME}"
    
     az storage blob show \
    --container-name "${CONTAINER_NAME}" \
    --name "${blob_name}" \
    --account-name "${STORAGE_ACCOUNT}" \
    --account-key "${account_key}" \
    --query "{Name:name, Size:properties.contentLength, LastModified:properties.lastModified, ContentType:properties.contentSettings.contentType}" \
    --output json \
    || error "Failed to fetch file info."
}

# Show logs
show_logs() {
    if [[ -f "${log_file}" ]]; then
        echo -e "${BLUE}Displaying log file: ${log_file}${NC}"
        cat "${log_file}"
    else
        error "Log file not found."
    fi
}

# Clean up resources
cleanup_resources() {
    if [[ -f "${config_file}" ]]; then
        source "${config_file}"
        check_azure_cli

        log "Cleanup process started."
        echo "⚠️ WARNING: This will delete the Resource Group: ${RESOURCE_GROUP} and all associated resources."
        echo "- Resource Group: ${RESOURCE_GROUP}"
    echo "- Storage Account: ${STORAGE_ACCOUNT}"
    echo "- Container Name: ${CONTAINER_NAME}"
    echo
    read -p "Are you sure you want to proceed? (yes/no): " confirmation

    if [[ "${confirmation}" != "yes" ]]; then
        log "Cleanup aborted by user."
        exit 0
    fi

        
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait || error "Failed to delete resource group."
        rm -f "${config_file}"
        log "Cleanup initiated. Resource group deletion has been started and may take some time to complete."
    else
        error "Configuration file not found. Nothing to clean up."
    fi
}
    
# Display Usage
usage() {
    cat <<EOF
Azure Cloud File Storage Manager Script
Usage: ${0} <command> [args...]
Commands:
  deploy                Deploy Azure storage resources
  upload <file> [name]  Upload a file to Azure storage
  download <blob> [path] Download a file from Azure storage
  list                  List files in the Azure storage container
  info <blob>           Show information about a blob/file in Azure storage
   delete <blob>        Delete a blob from Azure storage
  logs                  Show operation logs
  cleanup               Clean up all deployed Azure resources
  help                  Show this help message

  Example:
    ${0} deploy
    ${0} upload myfile.txt
    ${0} download myfile.txt ./downloaded_myfile.txt
    ${0} list
    ${0} info myfile.txt
    ${0} delete myfile.txt
    ${0} logs
    ${0} cleanup
EOF
}   

# Main Script
main() {
    local command="$1"
    shift

    case "${command}" in
        deploy)
            deploy_storage
            ;;
        upload)
            [[ $# -lt 1 ]] && error "Usage: $0 upload <filename> [blob-name]" && exit 1
            upload_file "$@"
            ;;
        download)
            [[ $# -lt 1 ]] && error "Usage: $0 download <blob-name> [local-filename]" && exit 1
            download_file "$@"
            ;;
        list)
            list_files
            ;;
        info)
            [[ $# -lt 1 ]] && error "Usage: $0 info <blob-name>" && exit 1
            show_file_info "$@"
            ;;
        delete)
            [[ $# -lt 1 ]] && error "Usage: $0 delete <blob-name>" && exit 1
            delete_file "$@"
            ;;
        logs)
            show_logs
            ;;
        cleanup)
            cleanup_resources
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "Unknown command: ${command:-none provided}"
            usage
            exit 1
            ;;
    esac
}
main "$@"



