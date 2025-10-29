# Azure-filestorage
Group 2 Capstone Project

A simple cloud-based file storage system similar to Dropbox/Google Drive, built with Bash scripting and Azure CLI.

# Features
-  Automated Azure storage deployment
-  File upload/download/list/delete operations
-  Comprehensive logging system
-  Public URL generation for files
-  GitHub Actions CI/CD pipeline

## Prerequisites
- Azure CLI installed
- Azure subscription
- GitHub account

## Local Usage
```bash
# Deploy Script
./azure-storage.sh deploy

# Upload file
./azure-storage.sh upload myfile.pdf

# List files
./azure-storage.sh list

# Download file
./azure-storage.sh download myfile.pdf

# Show logs
./azure-storage.sh logs

# Cleanup resources
./azure-storage.sh cleanup
