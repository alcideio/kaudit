#!/bin/bash

############################################
# Creating k8s deployment for Alcide kAudit.
############################################
bold=$(tput bold)
underline=$(tput sgr 0 1)
reset=$(tput sgr0)

purple=$(tput setaf 171)
red=$(tput setaf 1)
green=$(tput setaf 76)
tan=$(tput setaf 3)
blue=$(tput setaf 38)


# Headers and  Logging
e_header() { printf "\n${bold}==========  %s  ==========${reset}\n" "$@"
}
e_arrow() { printf "${green}➜ $@${reset}\n"
}
e_success() { printf "${green}✔ ${reset}%s\n" "$@"
}
e_error() { printf "${red}✖ ${reset}%s\n" "$@"
}
e_warning() { printf "${tan}➜ ${reset}%s\n" "$@"
}
e_underline() { printf "${underline}${bold}%s${reset}\n" "$@"
}
e_bold() { printf "${bold}%s${reset}\n" "$@"
}
e_note() { printf "${underline}${bold}${blue}Note:${reset}  ${blue}%s${reset}\n" "$@"
}

type_exists() {

    if [[ $(type -P $1) ]]; then
      return 0
    fi
    return 1

}

package_exist(){
    if type_exists $1; then
      e_success "$1"
    else
      e_error "$1 should be installed. It isn't. Aborting."
      exit 1
    fi
}

function finish {
      stty icanon
}
trap finish EXIT
stty -icanon

# Set default value (optional): Environment_Variable_Name="value"
# Usage: get_input <Environment Variable Name> <Prompt Message> <Warning Message> <Expected Values>

function get_input()
{
    local prompt_msg=$2
    local expected_values=$3
    local env_var=$1
    local default_value=$(eval echo "\$$env_var")

    if [[ "${default_value}" ]] && [[ -z "${expected_values}" ]]; then
        e_arrow "${prompt_msg}: [default: ${default_value}]"
    else
        e_arrow "${prompt_msg}:"
    fi

    read -e
    if [[ "${REPLY}" ]]; then
      input=$REPLY
    elif [ "${default_value}" ]; then
      input=$default_value
    else
      e_warning "Missing input!"
      get_input "${env_var}" "${prompt_msg}" "${expected_values}"
    fi

    #validate_input
    if [[ "${expected_values}" ]] && [[ ! $input =~ ["${expected_values}"]$ ]]; then
      e_warning "Invalid input: [${REPLY}]"
      e_warning "Expected input: [${expected_values}]"
      e_warning "Please try again..."
      get_input "${env_var}" "${prompt_msg}" "${expected_values}"
    else
        eval $env_var=$REPLY
    fi
}

clear
e_header "Alcide's kAudit Deployment Generator"
#echo -------------------------------------

# Check if helm is installed - Suggest installing using curl
package_exist helm

helmargs=()

get_input CLUSTER_NAME "Cluster name"

CLUSTER_TYPE="" # k8s, gke, aks, eks, s3

get_input K8S_PROVIDER "Type Of Monitored Cluster: [G] GKE / [E] EKS / [A] AKS / [K] Kubernetes (native) / [W] Kubernetes (webhook) / [S] S3 backup bucket / [0] Exit" \
                       "GEAKWS0"

case $K8S_PROVIDER in
  G)
    CLUSTER_TYPE="gke"

    get_input GKE_TOKEN "GKE access token (for StackDriver, base64-encoded)"
    get_input GKE_PROJECT "GKE project of the cluster"

    helmargs+=(--set k8sAuditEnvironment="${CLUSTER_TYPE}")
    helmargs+=(--set gke.projectId="${GKE_PROJECT}")
    helmargs+=(--set gke.token="${GKE_TOKEN}")
    ;;
  E)
    CLUSTER_TYPE="eks"

    get_input AWS_AKI "AWS access key id (for Kinesis stream)"
    get_input AWS_SAK "AWS secret access key (for Kinesis stream, base64-encoded)"
    get_input AWS_REGION "AWS region (for Kinesis stream)"
    get_input AWS_STREAM_NAME "AWS Kinesis stream name"
    AWS_MARKETPLACE="N"
    get_input AWS_MARKETPLACE "Subscribed through AWS Marketplace? [y/N]" "yYnN"
    if [[ $AWS_MARKETPLACE =~ ["yY"]$ ]]; then
      e_warning "==="
      e_warning "In order to deploy kAudit, your EKS cluster should be running in the same AWS Marketplace account."
      e_warning "==="
    fi


    helmargs+=(--set k8sAuditEnvironment="${CLUSTER_TYPE}")
    helmargs+=(--set aws.region="${AWS_REGION}")
    helmargs+=(--set aws.accessKeyId="${AWS_AKI}")
    helmargs+=(--set aws.secretAccessKey="${AWS_SAK}")
    helmargs+=(--set aws.kinesisStreamName="${AWS_STREAM_NAME}")
    if [[ $AWS_MARKETPLACE =~ [yY] ]]; then
      AWS_IMG_REGISTRY_REGION="us-east-1"
      get_input AWS_IMG_REGISTRY_REGION "Registry region (for Alcide kAudit image)"
      REGISTRY="117940112483.dkr.ecr.${AWS_IMG_REGISTRY_REGION}.amazonaws.com"

      helmargs+=(--set image.source="Marketplace")
      helmargs+=(--set image.kaudit="${REGISTRY}/209df288-4da3-4c1a-878b-6a8af5d523b4/cg-2695406193/kaudit:2.3-latest")
    else
      get_input ALCIDE_REPOSITORY_TOKEN "Alcide repository token"

      helmargs+=(--set image.pullSecretToken="${ALCIDE_REPOSITORY_TOKEN}")
    fi
    ;;
  A)
    CLUSTER_TYPE="aks"

    get_input AKS_EVENT_HUB_NAME "Azure EventHub name"
    get_input AKS_CONNECTION_STRING "Azure EventHub connection string (base64-encoded)"
    AKS_CONSUMER_GROUP_NAME="\$Default"
    get_input AKS_CONSUMER_GROUP_NAME "No Azure EventHub ConsumerGroup name"

    helmargs+=(--set k8sAuditEnvironment="${CLUSTER_TYPE}")
    helmargs+=(--set aks.eventHubName="${AKS_EVENT_HUB_NAME}")
    helmargs+=(--set aks.eventHubconnectionString="${AKS_CONNECTION_STRING}")
    if [[ $AKS_CONSUMER_GROUP_NAME != "\$Default" ]]; then
      helmargs+=(--set aks.consumerGroupName="${AKS_CONSUMER_GROUP_NAME}")
    fi
    ;;
  K)
    CLUSTER_TYPE="k8s"

    helmargs+=(--set k8s.mode="auditsink")
    e_note "Install Kubernetes Audit Sink in the monitored cluster"

    ;;
  W)
    CLUSTER_TYPE="k8s"

    helmargs+=(--set k8s.mode="webhook")
    ;;
  S)
    CLUSTER_TYPE="s3"

    get_input AWS_AKI "AWS access key id (for S3)"
    get_input AWS_SAK "AWS secret access key (for S3, base64-encoded)"
    get_input AWS_REGION "AWS region (for S3)"
    get_input AWS_BUCKET_NAME "S3 bucket name"
    get_input AWS_RESOURCE_KEY_PREFIX "S3 resources keys prefix"

    helmargs+=(--set k8sAuditEnvironment="${CLUSTER_TYPE}")
    helmargs+=(--set aws.region="${AWS_REGION}")
    helmargs+=(--set aws.accessKeyId="${AWS_AKI}")
    helmargs+=(--set aws.secretAccessKey="${AWS_SAK}")
    helmargs+=(--set aws.s3BucketName="${AWS_BUCKET_NAME}")
    helmargs+=(--set aws.s3ResourceKeyPrefix="${AWS_RESOURCE_KEY_PREFIX}")
    ;;
  0)
    exit 0
    ;;
esac


NAMESPACE="alcide-kaudit"
get_input NAMESPACE "Deployment namespace" 

# normalize cluster name as k8s object name part, not assuming sed, tr etc. exist
# should be alphanumeric or '-'
LEGIT_NAME=${CLUSTER_NAME// /-}
LEGIT_NAME=${CLUSTER_NAME//_/-}

NAME="kaudit-${LEGIT_NAME}"
DEPLOYMENT_FILE="${NAME}.yaml"


helmargs+=(--set namespace="${NAMESPACE}")
helmargs+=(--set clusterName="${CLUSTER_NAME}")
helmargs+=(--set runOptions.eulaSign="true")

helm template kaudit deploy/charts/kaudit "${helmargs[@]}" > ${DEPLOYMENT_FILE}

e_header "Completed"
e_success "Generated file: ${DEPLOYMENT_FILE}"

e_header "Useful Commands"
e_success "kubectl apply -f ${DEPLOYMENT_FILE}"
e_success "kubectl -n ${NAMESPACE} get statefulsets,pods,svc"
e_success "kubectl port-forward -n ${NAMESPACE} svc/${NAME}  7000:443"
e_success "kubectl delete ns ${NAMESPACE} ; kubectl delete auditsinks.auditregistration.k8s.io alcide-kaudit-sink"
e_success "kubectl -n ${NAMESPACE} get secrets ${NAME}-certs -o json | jq -j .data.\\\"ca.pem\\\" | base64 -d"

