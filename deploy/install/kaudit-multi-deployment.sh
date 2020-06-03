#!/bin/bash

#
# Running multi-cluster audit analysis using Alcide kAudit.
# Each cluster is monitored with a seperate kAudit instance (service, instance etc.).
# All kAudit instances are running in the same K8S cluster & namespace.
#

# clusters identifiers, also used with the deployments failed to identify kaudit objects
# (e.g. for 'prod' cluster and within 'prod' kaudit deployment file, kaudit-prod is the name of its ConfigMap, Service, ServiceAccount...)
CLUSTERS=(
          #"devel"
          "poc2"
          "free"
          "prod"
          "eks"
          "aks"
          #"poc2ui2"
        )
# name of k8s deployment configuration file for each cluster's kaudit (matched to CLUSTERS by index)
DEPLOYMENTS=(
          #"kaudit_gke_devel.yaml"
          "kaudit_gke_poc2.yaml"
          "kaudit_gke_free.yaml"
          "kaudit_gke_prod.yaml"
          "kaudit_eks_eks-cluster-nitzan.yaml"
          "kaudit_aks-k8s-external-services.yaml"
          #"kaudit_gke_poc2_ui2.yaml"
        )
NUM_CLUSTERS=${#CLUSTERS[*]}

# validating deployment files exist
for ((i=0; i<NUM_CLUSTERS; i++)); do
  CLUSTER="${CLUSTERS[i]}"
  DEPLOYMENT="${DEPLOYMENTS[i]}"
  echo "for kAudit monitoring cluster $CLUSTER, deployment file: $DEPLOYMENT"
  if [ -e $DEPLOYMENT ]
  then
    echo "exists"
  else
    echo "not found"
    exit 1
  fi
done

CTXT=`kubectl config current-context`

DELAY=10 # Number of seconds to display results

PORT=7000 # Base port for forwarding
PF_PIDS=() # port-forward PIDs
PORTS=() # port-forward externalized ports

NL=$'\n'

while true; do
  STATE=()
  for ((i=0; i<NUM_CLUSTERS; i++)); do
    if [ ! -z "${PF_PIDS[i]}" ]
    then
      STATE+=("cluster ${CLUSTERS[i]}: port ${PORTS[i]}, port-forward process ${PF_PIDS[i]}${NL}")
    else
      STATE+=("cluster ${CLUSTERS[i]}${NL}")
    fi
  done
  clear
  cat << _EOF_
Alcide's kAudit Multi-cluster Monitoring Deployment
Kubernetes context: $CTXT
Monitored clusters:
 ${STATE[@]}

Please Select:

1. Initial deployment
2. Canary Deployment upgrade (${CLUSTERS[0]})
3. Deployment upgrade
4. Deployment restart (with updated image)
5. Port forwarding
6. Stopping port forwarding
7. Canary Deployment cleanup (${CLUSTERS[0]})
8. Deployment cleanup
0. Quit

_EOF_

  read -p "Enter selection [0-8] > "

  if [[ $REPLY =~ ^[0-8]$ ]]; then
    case $REPLY in
      1)
        for ((i=0; i<NUM_CLUSTERS; i++)); do
          CLUSTER="${CLUSTERS[i]}"
          DEPLOYMENT="${DEPLOYMENTS[i]}"
          echo deploying kAudit monitoring "$CLUSTER"
          kubectl apply -f "$DEPLOYMENT"
        done

        sleep $DELAY
        continue
        ;;

      2)
        PID=${PF_PIDS[0]}
        if [ ! -z "$PID" ]; then
          echo killing existing port-forwarding processes: "$PID"
          kill "$PID"
          PF_PIDS[0]=""
          PORTS[0]=""
        fi

        CLUSTER=${CLUSTERS[0]}
        DEPLOYMENT=${DEPLOYMENTS[0]}
        echo stopping kAudit monitoring "$CLUSTER"
        kubectl delete statefulset "kaudit-$CLUSTER" -n alcide-kaudit
        sleep 1
        echo updating and restarting kAudit monitoring "$CLUSTER"
        kubectl apply -f "$DEPLOYMENT"

        sleep 30
        ((CUR_PORT=PORT))
        kubectl port-forward -n alcide-kaudit svc/"kaudit-$CLUSTER" "$CUR_PORT":443 &
        PF_PID=$!
        echo pid "$PF_PID" port-forwarding localhost:"$CUR_PORT" to kAudit monitoring "$CLUSTER"
        PF_PIDS[0]="$PF_PID"
        PORTS[0]="$CUR_PORT"

        sleep $DELAY
        continue
        ;;

      3)
        echo killing existing port-forwarding processes: "${PF_PIDS[@]}"
        for PID in "${PF_PIDS[@]}"; do
          kill "$PID"
        done;
        PF_PIDS=()
        PORTS=()

        for CLUSTER in "${CLUSTERS[@]}"; do
          echo stopping kAudit monitoring "$CLUSTER"
          kubectl delete statefulset "kaudit-$CLUSTER" -n alcide-kaudit
        done
        sleep 1
        for ((i=0; i<NUM_CLUSTERS; i++)); do
          CLUSTER="${CLUSTERS[i]}"
          DEPLOYMENT="${DEPLOYMENTS[i]}"
          echo updating and restarting kAudit monitoring "$CLUSTER"
          kubectl apply -f "$DEPLOYMENT"
          sleep 15
        done

        sleep $DELAY
        continue
        ;;

      4)
        for CLUSTER in "${CLUSTERS[@]}"; do
          echo restarting kAudit monitoring "$CLUSTER"
          read -p "Are you sure? " -n 1 -r
          echo    # (optional) move to a new line
          if [[ $REPLY =~ ^[Yy]$ ]]
          then
            kubectl delete pod "kaudit-$CLUSTER-0" -n alcide-kaudit
          fi
        done

        sleep $DELAY
        continue
        ;;

      5)
        echo killing existing port-forwarding processes: "${PF_PIDS[@]}"
        for PID in "${PF_PIDS[@]}"; do
          kill "$PID"
        done;
        PF_PIDS=()
        PORTS=()

        ((CUR_PORT=PORT))
        for CLUSTER in "${CLUSTERS[@]}"; do
          kubectl port-forward -n alcide-kaudit svc/"kaudit-$CLUSTER" "$CUR_PORT":443 &
          PF_PID=$!
          echo pid "$PF_PID" port-forwarding localhost:"$CUR_PORT" to kAudit monitoring "$CLUSTER"
          PF_PIDS+=( "$PF_PID" )
          PORTS+=( "$CUR_PORT" )
          ((CUR_PORT=CUR_PORT+1))
        done

        sleep $DELAY
        continue
        ;;

      6)
        echo killing existing port-forwarding processes: "${PF_PIDS[@]}"
        for PID in "${PF_PIDS[@]}"; do
          kill "$PID"
        done;
        PF_PIDS=()
        PORTS=()

        sleep $DELAY
        continue
        ;;

      7)
        PID=${PF_PIDS[0]}
        if [ ! -z "$PID" ]; then
          echo killing existing port-forwarding processes: "$PID"
          kill "$PID"
          PF_PIDS[0]=""
          PORTS[0]=""
        fi

        CLUSTER=${CLUSTERS[0]}
        echo removing kAudit monitoring "$CLUSTER"
        read -p "Are you sure? " -n 1 -r
        echo    # (optional) move to a new line
        if [[ $REPLY =~ ^[Yy]$ ]]
        then
          kubectl delete service "kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete statefulset "kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete pvc "data-volume-claim-kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete serviceaccount "alcide-k8s-kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete secret "kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete configmap "kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete configmap "kaudit-policy-$CLUSTER" -n alcide-kaudit & kubectl delete configmap "kaudit-integration-$CLUSTER" -n alcide-kaudit & kubectl delete configmap "kaudit-data-filter-$CLUSTER" -n alcide-kaudit
        fi

        sleep $DELAY
        continue
        ;;

      8)
        for CLUSTER in "${CLUSTERS[@]}"; do
          echo removing kAudit monitoring "$CLUSTER"
          read -p "Are you sure? " -n 1 -r
          echo    # (optional) move to a new line
          if [[ $REPLY =~ ^[Yy]$ ]]
          then
            kubectl delete service "kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete statefulset "kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete pvc "data-volume-claim-kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete serviceaccount "alcide-k8s-kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete secret "kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete configmap "kaudit-$CLUSTER" -n alcide-kaudit & kubectl delete configmap "kaudit-policy-$CLUSTER" -n alcide-kaudit & kubectl delete configmap "kaudit-integration-$CLUSTER" -n alcide-kaudit & kubectl delete configmap "kaudit-data-filter-$CLUSTER" -n alcide-kaudit
          fi
        done

        sleep $DELAY
        continue
        ;;

      0)
        break
        ;;
    esac
  else
    echo "Invalid entry."
  fi
done
echo "Program terminated."


