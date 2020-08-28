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

clear
e_header "Alcide's kAudit Deployment Generator"
#echo -------------------------------------

# Check if helm is installed - Suggest installing using curl
package_exist helm

helmargs=()

e_arrow "Cluster name: "
read CLUSTER_NAME
if [ $CLUSTER_NAME = "" ]; then
  e_error "No cluster name"
  exit 1
fi

EXTERNAL_CONFIG=""
e_arrow "Using Vault configuration: [y/N]"
read
if [[ $REPLY =~ [yY]$ ]]; then
  EXTERNAL_CONFIG="vault"
fi

CLUSTER_TYPE="" # k8s, gke, aks, eks, s3

e_arrow 'Type Of Monitored Cluster: [G] GKE / [E] EKS / [A] AKS / [K] Kubernetes (native) / [W] Kubernetes (webhook) / [S] S3 backup bucket / [0] Exit'
while true; do
  read -p "Enter selection: "
  if [[ $REPLY =~ ^[GEAKWS0]$ ]]; then
    case $REPLY in
      G)
        CLUSTER_TYPE="gke"

        e_arrow "GKE access token (for StackDriver, base64-encoded): "
        read GKE_TOKEN
        if [[ -z "${GKE_TOKEN// }" ]]; then
          e_warning "No GKE access token"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        e_arrow "GKE project of the cluster: "
        read GKE_PROJECT
        if [[ -z "${GKE_PROJECT// }" ]]; then
          e_warning "No GKE project"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi

        helmargs+=(--set k8sAuditEnvironment=gke)
        helmargs+=(--set gke.projectId="${GKE_PROJECT}")
        helmargs+=(--set gke.token="${GKE_TOKEN}")

        break
        ;;
      E)
        CLUSTER_TYPE="eks"
        e_arrow "AWS access key id (for Kinesis stream): "
        read AWS_ACCESS_KEY_ID
        if [[ -z "${AWS_ACCESS_KEY_ID// }" ]]; then
          e_warning "No AWS access key id"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        e_arrow "AWS secret access key (for Kinesis stream, base64-encoded): "
        read AWS_SECRET_ACCESS_KEY
        if [[ -z "${AWS_SECRET_ACCESS_KEY// }" ]]; then
          e_warning "No AWS secret access key"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        e_arrow "AWS region (for Kinesis stream): "
        read AWS_REGION
        if [[ -z "${AWS_REGION// }" ]]; then
          e_warning "No AWS region"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        e_arrow "AWS Kinesis stream name: "
        read AWS_STREAM_NAME
        if [[ -z "${AWS_STREAM_NAME// }" ]]; then
          e_warning "No AWS Kinesis stream name"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        MARKETPLACE="false"
        e_arrow "Subscribed through AWS Marketplace? [y/N]"
        read
        if [[ $REPLY =~ [yY]$ ]]; then
          e_warning "==="
          e_warning "to deploy kAudit your EKS cluster should be running in the same AWS Marketplace account."
          e_warning "==="
          MARKETPLACE="true"
        fi
        helmargs+=(--set k8sAuditEnvironment=eks)
        helmargs+=(--set aws.region="${AWS_REGION}")
        helmargs+=(--set aws.accessKeyId="${AWS_ACCESS_KEY_ID}")    
        helmargs+=(--set aws.secretAccessKey="${AWS_SECRET_ACCESS_KEY}")
        helmargs+=(--set aws.kinesisStreamName="${AWS_STREAM_NAME}")             
        break
        ;;
      A)
        CLUSTER_TYPE="aks"
        e_arrow "Azure EventHub name: "
        read AKS_EVENT_HUB_NAME
        if [[ -z "${AKS_EVENT_HUB_NAME// }" ]]; then
          e_warning "Azure EventHub name"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        e_arrow "Azure EventHub connection string (base64-encoded): "
        read AKS_CONNECTION_STRING
        if [[ -z "${AKS_CONNECTION_STRING// }" ]]; then
          e_warning "No Azure EventHub connection string"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        e_arrow "No Azure EventHub ConsumerGroup name [default: \$Default]: "
        read AKS_CONSUMER_GROUP_NAME

        helmargs+=(--set k8sAuditEnvironment=aks)
        helmargs+=(--set aks.eventHubName="${AKS_EVENT_HUB_NAME}")
        helmargs+=(--set aks.eventHubconnectionString="${AKS_CONNECTION_STRING}")    
        helmargs+=(--set aks.consumerGroupName="${AKS_CONSUMER_GROUP_NAME}") 

        break
        ;;
      K)
        CLUSTER_TYPE="k8s"
        helmargs+=(--set k8s.mode="auditsink")
        e_note "Install Kubernetes Audit Sink in the monitored cluster"
        break
        ;;
      W)
        CLUSTER_TYPE="k8s"
        helmargs+=(--set k8s.mode="webhook")
        break
        ;;        
      S)
        CLUSTER_TYPE="s3"
        e_arrow "AWS access key id (for S3): "
        read AWS_ACCESS_KEY_ID
        if [[ -z "${AWS_ACCESS_KEY_ID// }" ]]; then
          e_warning "No AWS access key id"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        e_arrow "AWS secret access key (for S3, base64-encoded): "
        read AWS_SECRET_ACCESS_KEY
        if [[ -z "${AWS_SECRET_ACCESS_KEY// }" ]]; then
          e_warning "No AWS secret access key"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        e_arrow "AWS region (for S3): "
        read AWS_REGION
        if [[ -z "${AWS_REGION// }" ]]; then
          e_warning "No AWS region"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        e_arrow "S3 bucket name: "
        read AWS_BUCKET_NAME
        if [[ -z "${AWS_BUCKET_NAME// }" ]]; then
          e_warning "No S3 bucket name"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        e_arrow "S3 resources keys prefix: "
        read AWS_RESOURCE_KEY_PREFIX

        helmargs+=(--set k8sAuditEnvironment=s3)
        helmargs+=(--set aws.region="${AWS_REGION}")
        helmargs+=(--set aws.accessKeyId="${AWS_ACCESS_KEY_ID}")    
        helmargs+=(--set aws.secretAccessKey="${AWS_SECRET_ACCESS_KEY}")
        helmargs+=(--set aws.s3BucketName="${AWS_BUCKET_NAME}") 
        helmargs+=(--set aws.s3ResourceKeyPrefix="${AWS_RESOURCE_KEY_PREFIX}") 

        break
        ;;
      0)
        exit 0
        ;;
    esac
  else
    e_warning "Invalid selection"
    continue
  fi
done

if [[ $MARKETPLACE == true ]]; then
  REGISTRY="117940112483.dkr.ecr.us-east-1.amazonaws.com"
  helmargs+=(--set image.kaudit="${REGISTRY}/209df288-4da3-4c1a-878b-6a8af5d523b4/cg-2695406193/kaudit:2.3-latest")
  helmargs+=(--set image.pullSecretToken="Marketplace")
else
  e_arrow "Alcide repository token: "
  read ALCIDE_REPOSITORY_TOKEN
  if [[ -z "${ALCIDE_REPOSITORY_TOKEN// }" ]]; then
    e_warning "No Alcide repository token"
    if [[ -z "${EXTERNAL_CONFIG}" ]]; then
      exit 1
    fi
  fi

  helmargs+=(--set image.pullSecretToken="${ALCIDE_REPOSITORY_TOKEN}")
fi

NAMESPACE="alcide-kaudit"
e_arrow "Deployment namespace: [default: ${NAMESPACE}] "
read REPLY
if [[ ! -z "${REPLY// }" ]]; then
  NAMESPACE=$REPLY
fi

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

