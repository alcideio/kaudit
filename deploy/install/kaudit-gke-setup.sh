#!/bin/bash

######################################################
#       GKE Audit Log Setup for Alcide kAudit        #
######################################################

# mandatory user-defined script parameters
# may be provided in the command line: -p <GKE-project> -k <output key file>
# GKE project
GKE_PROJECT=""
# name of created file containing the credentials for the service account
KEY_FILE_NAME=""

echo "GKE Audit Log Setup for Alcide kAudit"

if [[ $# -eq 0 && $GKE_PROJECT == "" && $KEY_FILE_NAME == "" ]]; then
  echo "Command line options: -p <GKE-project> -k <output key file>"
  exit 0
fi

# Given command line args - parse them:
if (($# != 0)); then
  while getopts ":p:k:h" opt; do
    case $opt in
      p)
        GKE_PROJECT="${OPTARG}"
        ;;
      k)
        KEY_FILE_NAME="${OPTARG}"
        ;;
      h)
        echo "Command line options: -p <GKE-project> -k <output key file>"
        exit 0
        ;;
      \?)
        echo "Invalid option: -$OPTARG" >&2
        exit 1
        ;;
      :)
        echo "Option -$OPTARG requires an argument." >&2
        exit 1
        ;;
    esac
  done
fi

# 0. validate user-provided parameters
if [ -z ${GKE_PROJECT} ]; then
  echo GKE project is not configured
  exit
fi
if [ -z ${KEY_FILE_NAME} ]; then
  echo Key file name is not configured
  exit
fi

# optional user-defined script parameters
# service account name
KAUDIT_SERVICE_ACCOUNT_NAME="kaudit-logs-viewer"
# service account display name
KAUDIT_SERVICE_ACCOUNT_DISPLAY_NAME="kaudit-logs-viewer"
# name uninstall script
UNINSTALL_SCRIPT_FILE=kaudit-gke-uninstall-"${GKE_PROJECT}".sh

echo "Preparing StackDriver for collecting GKE audit logs in project ${GKE_PROJECT}"

# 1. create service account that will be used by kAudit
gcloud iam service-accounts create ${KAUDIT_SERVICE_ACCOUNT_NAME} \
      --display-name "${KAUDIT_SERVICE_ACCOUNT_DISPLAY_NAME}"

# 2. add permissions to the service account to view GKE audit logs
gcloud projects add-iam-policy-binding ${GKE_PROJECT} \
  --member serviceAccount:${KAUDIT_SERVICE_ACCOUNT_NAME}@${GKE_PROJECT}.iam.gserviceaccount.com \
  --role roles/logging.privateLogViewer

# 3. create access key for the service
gcloud iam service-accounts keys create \
      --iam-account ${KAUDIT_SERVICE_ACCOUNT_NAME}@${GKE_PROJECT}.iam.gserviceaccount.com ${KEY_FILE_NAME}

echo Parameters for kAudit setup:
echo ---------------------------
echo credentials in file: ${KEY_FILE_NAME}

echo "GKE Audit Log Setup for Alcide kAudit complete!"
echo "Please follow Alcide kAudit installation guide to verify the EKS setup and integrate with kAudit."

# 4. create uninstall script

echo "#!/bin/bash
GKE_KEY_ID=\"\"
gcloud projects remove-iam-policy-binding ${GKE_PROJECT} \\
  --member serviceAccount:${KAUDIT_SERVICE_ACCOUNT_NAME}@${GKE_PROJECT}.iam.gserviceaccount.com \\
  --role roles/logging.privateLogViewer
gcloud iam service-accounts keys delete ${GKE_KEY_ID}\\
  --iam-account ${KAUDIT_SERVICE_ACCOUNT_NAME}@${GKE_PROJECT}.iam.gserviceaccount.com
gcloud iam service-accounts delete ${KAUDIT_SERVICE_ACCOUNT_NAME}@${GKE_PROJECT}.iam.gserviceaccount.com
" > ${UNINSTALL_SCRIPT_FILE}

echo "Setup may be reverted using the script at: ${UNINSTALL_SCRIPT_FILE}"

