#!/bin/bash

######################################################
#       EKS Audit Log Setup for Alcide kAudit        #
######################################################

# mandatory user-defined script parameters
# may be provided in the command line: -a <CloudWatch-account-id> -k <Kinesis-account-id> -c <EKS-cluster-name> -r <region>
# AWS REGION
REGION=""
# EKS cluster name
CLUSTER_NAME=""
# CloudWatch account ID
CLOUDWATCH_ACCOUNT_ID=""
# Kinesis account ID (may or may not be the same as the CloudWatch account ID)
KINESIS_ACCOUNT_ID="${CLOUDWATCH_ACCOUNT_ID}"


echo "EKS Audit Log Setup for Alcide kAudit"

# Given command line args - parse them:
if (($# != 0)); then
  while getopts ":a:k:c:r:h" opt; do
    case $opt in
      a)
        CLOUDWATCH_ACCOUNT_ID="${OPTARG}"
        ;;
      k)
        KINESIS_ACCOUNT_ID="${OPTARG}"
        ;;
      c)
        CLUSTER_NAME="${OPTARG}"
        ;;
      r)
        REGION="${OPTARG}"
        ;;
      h)
        echo "Command line options: -a <CloudWatch (sending) account-id> -k <Kinesis (receiving) account-id> -c <EKS-cluster-name> -r <region>"
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

# optional script parameters, can leave default values
# name of Kinesis stream
STREAM_NAME="KAuditStream-${CLUSTER_NAME}"
# name of Kinesis destination
DESTINATION_NAME="kAuditLogsDestination-${CLUSTER_NAME}"
# name of Kinesis filter
STREAM_FILTER_NAME="KAuditStreamFilter-${CLUSTER_NAME}"
# name of role used to send from CloudWatch to Kinesis
SENDING_ROLE_NAME="CWLtoKinesisRole-${CLUSTER_NAME}"
# name of policy for sending (CloudWatch account)
PERMISSION_POLICY_FOR_ROLE_NAME="Permissions-Policy-For-CWL-${CLUSTER_NAME}"
# name of kAudit user, used to read from Kinesis
KAUDIT_USER_NAME="KAuditReadKinesis-${STREAM_NAME}"
# name of kAudit user's policy
PERMISSION_POLICY_FOR_KAUDIT_USER_NAME="Permissions-Policy-For-${KAUDIT_USER_NAME}"
# name uninstall script
UNINSTALL_SCRIPT_FILE=~/kaudit-eks-uninstall-"${CLUSTER_NAME}".sh

# Number of seconds to wait for AWS command results
DELAY=10

# Variables that should not be changed
# CloudWatch EKS audit log group
LOG_GROUP_NAME="/aws/eks/$CLUSTER_NAME/cluster"
# Kinesis filter pattern
FILTER_PATTERN=""

echo "Preparing Kinesis Stream ${STREAM_NAME} at account ${KINESIS_ACCOUNT_ID} for EKS cluster ${CLUSTER_NAME} in region ${REGION} and account ${CLOUDWATCH_ACCOUNT_ID}"

# 0. validate user-provided parameters
if [ -z ${CLOUDWATCH_ACCOUNT_ID} ]; then
  echo CloudWatch account ID is not configured
  exit
fi
if [ -z ${REGION} ]; then
  echo Region is not configured
  exit
fi
if [ -z ${CLUSTER_NAME} ]; then
  echo EKS cluster name is not configured
  exit
fi

# 1. enable cluster's audit log
echo enable audit logging of EKS cluster: ${CLUSTER_NAME} region ${REGION}

# TODO: check if cluster's audit logging already enabled
#CLUSTER_DESCRIPTION="$(aws eks \
#    --region $REGION \
#    describe-cluster \
#    --name $CLUSTER_NAME)"
#
#pattern='"logging":[:space:]*{[:space:]*"clusterLogging":[:space:]*\[[:space:]*{[:space:]*"types":[^]]*"audit"[^]]*][:space:]*,[:space:]*"enabled":[:space:]*true'
#if [[ "$CLUSTER_DESCRIPTION" =~ $pattern ]]; then
#    echo audit logging enabled for EKS cluster: ${CLUSTER_NAME} region ${REGION}
#else
    CMD_ID=$(aws eks \
        --region $REGION \
        update-cluster-config \
        --name $CLUSTER_NAME \
        --logging '{"clusterLogging":[{"types":["audit"],"enabled":true}]}')

# if audit logging needed to be enabled, check that the command succeeded
# TODO extract ID from returned CMD_ID structure
#logging_update_status=""
#for ((i=0; i<20; i++)); do
#  echo "waiting for audit logging of cluster ${CLUSTER_NAME} region ${REGION} to become enabled"
#  sleep $DELAY
#  result=$(aws eks \
#             --region "$REGION" \
#             describe-update \
#             --update-id "$CMD_ID" \
#             --name "$CLUSTER_NAME")
#  if [[ "${result}" =~ \"Status\":\ \"Successful\" ]]; then
#    logging_update_status="success"
#    break;
#  fi
#  echo "${result}"
#done
#if [[ $logging_update_status != "success" ]]; then
#  echo failed to update logging of EKS cluster: ${CLUSTER_NAME} region ${REGION}
#  exit 1
#fi

#fi

# 2. create Kinesis Stream
echo creating Kinesis Stream: ${STREAM_NAME}

aws kinesis \
    create-stream \
    --region ${REGION} \
    --stream-name "${STREAM_NAME}" \
    --shard-count 1

#validate stream created before additional operations on it (creating destination, destination policy, destination filter)
stream_status=""
for ((i=0; i<20; i++)); do
  echo "waiting for stream ${STREAM_NAME} to become active"
  sleep $DELAY
  result=$(aws kinesis \
      describe-stream \
      --region "${REGION}" \
      --stream-name "${STREAM_NAME}")
  if [[ "${result}" =~ \"StreamStatus\":\ +\"ACTIVE\" ]]; then
    stream_status="active"
    break;
  fi
done

if [[ $stream_status != "active" ]]; then
  echo failed to create Kinesis stream: "${STREAM_NAME}"
  exit 1
fi


# 3. create Role that will be used for putting filtered records from CloudWatch (the cluster's audit entries) on the Kinesis Stream
echo creating role ${SENDING_ROLE_NAME} that can be assumed by CloudWatch for putting records on Kinesis Stream

echo "{
  \"Statement\": {
    \"Effect\": \"Allow\",
    \"Principal\": { \"Service\": \"logs.${REGION}.amazonaws.com\" },
    \"Action\": \"sts:AssumeRole\"
  }
}
" > ~/TrustPolicyForCWL.json
aws iam \
    create-role \
    --role-name ${SENDING_ROLE_NAME} \
    --assume-role-policy-document file://~/TrustPolicyForCWL.json
CLOUDWATCH_ROLE_ARN="arn:aws:iam::${CLOUDWATCH_ACCOUNT_ID}:role/${SENDING_ROLE_NAME}"

# 4. create Policy for the Role that will be used for putting filtered records from CloudWatch (the cluster's audit entries) on the Kinesis Stream

echo creating policy ${PERMISSION_POLICY_FOR_ROLE_NAME} for role ${SENDING_ROLE_NAME} to enable it to put filtered records from CloudWatch on the Kinesis Stream

echo "{
  \"Statement\": [
    {
      \"Effect\": \"Allow\",
      \"Action\": \"kinesis:PutRecord\",
      \"Resource\": \"arn:aws:kinesis:${REGION}:${KINESIS_ACCOUNT_ID}:stream/${STREAM_NAME}\"
    },
    {
      \"Effect\": \"Allow\",
      \"Action\": \"iam:PassRole\",
      \"Resource\": \"arn:aws:iam::${KINESIS_ACCOUNT_ID}:role/${SENDING_ROLE_NAME}\"
    }
  ]
}
" > ~/PermissionsForCWL.json
aws iam \
    put-role-policy \
    --role-name ${SENDING_ROLE_NAME} \
    --policy-name ${PERMISSION_POLICY_FOR_ROLE_NAME} \
    --policy-document file://~/PermissionsForCWL.json
KINESIS_ROLE_ARN="arn:aws:iam::${KINESIS_ACCOUNT_ID}:role/${SENDING_ROLE_NAME}"

# 5. create Kinesis Stream Destination

echo creating Kinesis stream destination ${DESTINATION_NAME} on stream ${STREAM_NAME}

aws logs \
    put-destination \
    --region ${REGION} \
    --destination-name "${DESTINATION_NAME}" \
    --target-arn "arn:aws:kinesis:${REGION}:${KINESIS_ACCOUNT_ID}:stream/${STREAM_NAME}" \
    --role-arn "${KINESIS_ROLE_ARN}"
DESTINATION_ARN="arn:aws:logs:${REGION}:${KINESIS_ACCOUNT_ID}:destination:${DESTINATION_NAME}"

# 6. create policy for the CloudWatch account on the Kinesis Stream destination

echo creating policy for to enable ${CLOUDWATCH_ACCOUNT_ID} to set Kinesis subscription filter on destination ${DESTINATION_NAME} of stream ${STREAM_NAME}

echo "{
  \"Statement\" : [
    {
      \"Sid\" : \"\",
      \"Effect\" : \"Allow\",
      \"Principal\" : {
        \"AWS\" : \"${CLOUDWATCH_ACCOUNT_ID}\"
      },
      \"Action\" : \"logs:PutSubscriptionFilter\",
      \"Resource\" : \"${DESTINATION_ARN}\"
    }
  ]
}
" > ~/AccessPolicy.json
aws logs \
    put-destination-policy \
    --region ${REGION} \
    --destination-name "${DESTINATION_NAME}" \
    --access-policy file://~/AccessPolicy.json

# 7. create Kinesis Stream subscription filter from the CloudWatch cluster audit to the Kinesis stream destination

echo creating Kinesis subscription filter on destination ${DESTINATION_NAME} of stream ${STREAM_NAME}

# Note: if running on Windows- the subscription-filter setup using this paramter doesn't work in Bash

if [ $KINESIS_ACCOUNT_ID != $CLOUDWATCH_ACCOUNT_ID ]; then
  aws logs \
      put-subscription-filter \
    --region ${REGION} \
      --log-group-name "${LOG_GROUP_NAME}" \
      --filter-name "${STREAM_FILTER_NAME}" \
      --filter-pattern "${FILTER_PATTERN}" \
      --destination-arn "${DESTINATION_ARN}" \
      --role-arn "${CLOUDWATCH_ROLE_ARN}"
else
  aws logs \
    put-subscription-filter \
    --region ${REGION} \
    --log-group-name "${LOG_GROUP_NAME}" \
    --filter-name "${STREAM_FILTER_NAME}" \
    --filter-pattern "${FILTER_PATTERN}" \
    --destination-arn "${DESTINATION_ARN}"
fi


# 8. create User that will be used by kAudit to read from the Kinesis Stream
echo creating role ${KAUDIT_USER_NAME} that will be used by kAudit to read from the Kinesis Stream

aws iam \
    create-user \
    --user-name "${KAUDIT_USER_NAME}"

echo "{
  \"Statement\": [
    {
      \"Effect\": \"Allow\",
      \"Action\": [\"kinesis:GetRecords\", \"kinesis:GetShardIterator\"],
      \"Resource\": \"arn:aws:kinesis:${REGION}:${KINESIS_ACCOUNT_ID}:stream/${STREAM_NAME}\"
    }
  ]
}
" > ~/PermissionsForKinesisRead.json
aws iam \
    put-user-policy \
    --user-name "${KAUDIT_USER_NAME}" \
    --policy-name "${PERMISSION_POLICY_FOR_KAUDIT_USER_NAME}" \
    --policy-document file://~/PermissionsForKinesisRead.json


# 9. create uninstall script

echo "#!/bin/bash
KAUDIT_ACCESS_KEY_ID=\"\"
aws eks \\
    --region ${REGION} \\
    update-cluster-config \\
    --name ${CLUSTER_NAME} \\
    --logging '{\"clusterLogging\":[{\"types\":[\"audit\"],\"enabled\":false}]}'
aws logs \\
    delete-subscription-filter \\
    --region ${REGION} \\
    --log-group-name ${LOG_GROUP_NAME} \\
    --filter-name ${STREAM_FILTER_NAME}
aws logs \\
    delete-destination \\
    --region ${REGION} \\
    --destination-name ${DESTINATION_NAME}
aws kinesis \\
    delete-stream \\
    --region ${REGION} \\
    --stream-name ${STREAM_NAME}
aws iam \\
    delete-role-policy \\
    --role-name ${SENDING_ROLE_NAME} \\
    --policy-name ${PERMISSION_POLICY_FOR_ROLE_NAME}
aws iam \\
    delete-role \\
    --role-name ${SENDING_ROLE_NAME}
aws iam \\
    delete-user-policy \\
    --user-name ${KAUDIT_USER_NAME} \\
    --policy-name ${PERMISSION_POLICY_FOR_KAUDIT_USER_NAME}
if [ ! -z $\"KAUDIT_ACCESS_KEY_ID\" ]; then
aws iam \\
    delete-access-key \\
    --user-name ${KAUDIT_USER_NAME} \\
    --access-key-id ${KAUDIT_ACCESS_KEY_ID}
fi
aws iam \\
    delete-user \\
    --user-name ${KAUDIT_USER_NAME}
" > "${UNINSTALL_SCRIPT_FILE}"

echo Parameters for kAudit setup:
echo ---------------------------
echo user credentials:
aws iam \
    create-access-key \
    --user-name "${KAUDIT_USER_NAME}"

echo region="${REGION}"
echo kinesis stream name="${STREAM_NAME}"

echo "EKS Audit Log Setup for Alcide kAudit complete!"
echo "Please follow Alcide kAudit installation guide to verify the EKS setup and integrate with kAudit."
echo "Setup may be reverted using the script at: ${UNINSTALL_SCRIPT_FILE}"

