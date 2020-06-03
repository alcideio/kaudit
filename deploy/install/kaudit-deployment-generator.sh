#!/bin/bash

############################################
# Creating k8s deployment for Alcide kAudit.
############################################

stty -icanon

clear
echo "Alcide's kAudit Deployment Generator"
echo -------------------------------------

echo -n "Cluster name: "
read CLUSTER_NAME
if [ $CLUSTER_NAME = "" ]; then
  echo "No cluster name"
  exit 1
fi

EXTERNAL_CONFIG=""
read -p "Using Vault configuration: [y/N] "
if [[ $REPLY =~ [yY]$ ]]; then
  EXTERNAL_CONFIG="vault"
fi

CLUSTER_TYPE="" # k8s, gke, aks, eks, s3

echo 'Type Of Monitored Cluster: [G] GKE / [E] EKS / [A] AKS / [K] Kubernetes (native) / [S] S3 backup bucket / [0] Exit'
while true; do
  read -p "Enter selection: "
  if [[ $REPLY =~ ^[GEAKS0]$ ]]; then
    case $REPLY in
      G)
        CLUSTER_TYPE="gke"
        echo -n "GKE access token (for StackDriver, base64-encoded): "
        read GKE_TOKEN
        if [[ -z "${GKE_TOKEN// }" ]]; then
          echo "No GKE access token"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        echo -n "GKE project of the cluster: "
        read GKE_PROJECT
        if [[ -z "${GKE_PROJECT// }" ]]; then
          echo "No GKE project"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        break
        ;;
      E)
        CLUSTER_TYPE="eks"
        echo -n "AWS access key id (for Kinesis stream): "
        read AWS_ACCESS_KEY_ID
        if [[ -z "${AWS_ACCESS_KEY_ID// }" ]]; then
          echo "No AWS access key id"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        echo -n "AWS secret access key (for Kinesis stream, base64-encoded): "
        read AWS_SECRET_ACCESS_KEY
        if [[ -z "${AWS_SECRET_ACCESS_KEY// }" ]]; then
          echo "No AWS secret access key"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        echo -n "AWS region (for Kinesis stream): "
        read AWS_REGION
        if [[ -z "${AWS_REGION// }" ]]; then
          echo "No AWS region"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        echo -n "AWS Kinesis stream name: "
        read AWS_STREAM_NAME
        if [[ -z "${AWS_STREAM_NAME// }" ]]; then
          echo "No AWS Kinesis stream name"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        break
        ;;
      A)
        CLUSTER_TYPE="aks"
        echo -n "Azure EventHub name: "
        read AKS_EVENT_HUB_NAME
        if [[ -z "${AKS_EVENT_HUB_NAME// }" ]]; then
          echo "Azure EventHub name"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        echo -n "Azure EventHub connection string (base64-encoded): "
        read AKS_CONNECTION_STRING
        if [[ -z "${AKS_CONNECTION_STRING// }" ]]; then
          echo "No Azure EventHub connection string"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        echo -n "No Azure EventHub ConsumerGroup name [default: \$Default]: "
        read AKS_CONSUMER_GROUP_NAME
        break
        ;;
      K)
        CLUSTER_TYPE="k8s"
        echo "Reminder: Kubernetes Audit Sink should created on the cluster"
        break
        ;;
      S)
        CLUSTER_TYPE="s3"
        echo -n "AWS access key id (for S3): "
        read AWS_ACCESS_KEY_ID
        if [[ -z "${AWS_ACCESS_KEY_ID// }" ]]; then
          echo "No AWS access key id"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        echo -n "AWS secret access key (for S3, base64-encoded): "
        read AWS_SECRET_ACCESS_KEY
        if [[ -z "${AWS_SECRET_ACCESS_KEY// }" ]]; then
          echo "No AWS secret access key"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        echo -n "AWS region (for S3): "
        read AWS_REGION
        if [[ -z "${AWS_REGION// }" ]]; then
          echo "No AWS region"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        echo -n "S3 bucket name: "
        read AWS_BUCKET_NAME
        if [[ -z "${AWS_BUCKET_NAME// }" ]]; then
          echo "No S3 bucket name"
          if [[ -z "${EXTERNAL_CONFIG}" ]]; then
            exit 1
          fi
        fi
        echo -n "S3 resources keys prefix: "
        read AWS_RESOURCE_KEY_PREFIX
        break
        ;;
      0)
        exit 0
        ;;
    esac
  else
    echo "Invalid selection"
    continue
  fi
done

NAMESPACE="alcide-kaudit"
echo -n "Deployment namespace: [default: ${NAMESPACE}] "
read REPLY
if [[ ! -z "${REPLY// }" ]]; then
  NAMESPACE=$REPLY
fi

echo -n "Alcide repository token: "
read ALCIDE_REPOSITORY_TOKEN
if [[ -z "${ALCIDE_REPOSITORY_TOKEN// }" ]]; then
  echo "No Alcide repository token"
  if [[ -z "${EXTERNAL_CONFIG}" ]]; then
    exit 1
  fi
fi

# normalize cluster name as k8s object name part, not assuming sed, tr etc. exist
# should be alphanumeric or '-'
LEGIT_NAME=${CLUSTER_NAME// /-}
LEGIT_NAME=${CLUSTER_NAME//_/-}

NAME="kaudit-${LEGIT_NAME}"
DEPLOYMENT_FILE="${NAME}.yaml"

ADDITIONAL_ANNOTATIONS="
        vault.hashicorp.com/agent-inject: \"true\"
        vault.hashicorp.com/role: \"kaudit-vault-role\"
        vault.hashicorp.com/agent-inject-secret-${NAME}: \"secret/data/${NAME}/config\"
        vault.hashicorp.com/agent-inject-template-${NAME}: |
          {{- with secret \"secret/data/${NAME}/config\" -}}
          {{ range \$k, \$v := .Data.data }}
          \"{{ \$k }}\": \"{{ \$v }}\"
          {{ end }}
          {{- end -}}"
if [[ -z "${EXTERNAL_CONFIG// }" ]]; then
  ADDITIONAL_ANNOTATIONS=""
fi

echo "
---

apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
spec:

---

apiVersion: v1
kind: Secret
metadata:
  name: registry.alcide.io
  namespace: ${NAMESPACE}
  labels:
    app: kaudit
  annotations:
    com.alcide.io/component.role: alcide-registry
    com.alcide.io/info.vendor: \"Alcide IO Inc.\"
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: \"${ALCIDE_REPOSITORY_TOKEN}\" # authentication token

---

apiVersion: v1
kind: Secret
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
  labels:
    app: kaudit
    app-name: ${NAME}
type: Opaque
data:
  # GKE-token (for GKE)
  gkeToken: \"${GKE_TOKEN}\"
  # Azure EventHub connection string (for AKS)
  aksConnectionString: \"${AKS_CONNECTION_STRING}\"
  # AWS Kinesis stream credentials (for EKS and S3)
  awsSecretAccessKey: \"${AWS_SECRET_ACCESS_KEY}\"

---

apiVersion: v1
kind: ConfigMap
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
  labels:
    app: kaudit
    app-name: ${NAME}
data:
  ca.pem: \"\" # pem certificate
  metadata-exclusion: \"kubectl.kubernetes.io/last-applied-configuration\"
  audit-source: |
    audit-env: ${CLUSTER_TYPE}                                   # Audit Logs Source - one of: k8s, gke, aks, eks, s3
    cluster: \"${CLUSTER_NAME}\"                                 # Name of cluster. For GKE - the GKE cluster name, otherwise - user provided unique name.
    project: \"${GKE_PROJECT}\"                                  # GKE-project (for GKE)
    pubsub-subscription-id: \"${GKE_PUBSUB_SUBSCRIPTION_ID}\"    # GKE PubSub subscription ID (only if consuming audit logs via PubSub instead of StackDriver)
    event-hub-name: \"${AKS_EVENT_HUB_NAME}\"                    # Azure EventHubName name (for AKS).
    consumer-group-name: \"${AKS_CONSUMER_GROUP_NAME}\"          # Azure EventHubName ConsumerGroup name (for AKS), if using a non-default ConsumerGroup (i.e. \$Default).
    stream-name: \"${AWS_STREAM_NAME}\"                          # AWS Kinesis stream name (for EKS)
    region: \"${AWS_REGION}\"                                    # AWS Kinesis stream region (for EKS and S3)
    access-key-id: \"${AWS_ACCESS_KEY_ID}\"                      # AWS Kinesis stream credentials (for EKS and S3)
    bucket-name: \"${AWS_BUCKET_NAME}\"                          # AWS S3 bucket name (for S3)
    resource-key-prefix: \"${AWS_RESOURCE_KEY_PREFIX}\"          # AWS S3 logs resources keys prefix (for S3)

---

apiVersion: v1
kind: ConfigMap
metadata:
  name: kaudit-policy-${NAME}
  namespace: ${NAMESPACE}
  labels:
    app: kaudit
    app-name: ${NAME}
data:
  audit-policy: |

---

apiVersion: v1
kind: ConfigMap
metadata:
  name: kaudit-integration-${NAME}
  namespace: ${NAMESPACE}
  labels:
    app: kaudit
    app-name: ${NAME}
data:
  audit-integration: |

---

apiVersion: v1
kind: ConfigMap
metadata:
  name: kaudit-data-filter-${NAME}
  namespace: ${NAMESPACE}
  labels:
    app: kaudit
    app-name: ${NAME}
data:
  audit-data-filter: |

---

apiVersion: v1
kind: ServiceAccount
metadata:
  name: alcide-k8s-${NAME}
  namespace: ${NAMESPACE}

---

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-volume-claim-${NAME}
  namespace: ${NAMESPACE}
spec:
  storageClassName:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi

---

apiVersion: v1
kind: Service
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
  labels:
    app: kaudit
    app-name: ${NAME}
spec:
  ports:
    - port: 443
      protocol: TCP
      targetPort: 8443
      name: ui
  selector:
    app-name: ${NAME}

---

apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
  labels:
    app: kaudit
    app-name: ${NAME}
  annotations:
    com.alcide.io/component.role: cloud-audit-k8s
    com.alcide.io/component.tier: database
    com.alcide.io/info.vendor: Alcide IO Inc.
spec:
  selector:
    matchLabels:
      app-name: ${NAME}
  serviceName: ${NAME}
  replicas: 1
  template:
    metadata:
      labels:
        app: kaudit
        app-name: ${NAME}
      annotations:
        # Alcide Runtime Policy
        policy.alcide.io/inbound0: service://${NAME}
        policy.alcide.io/inbound1: tcp://any:8443
        policy.alcide.io/outbound0: service://kube-dns
        policy.alcide.io/outbound1: service://coredns
        policy.alcide.io/outbound2: service://${NAME}
        ${ADDITIONAL_ANNOTATIONS}
    spec:
      terminationGracePeriodSeconds: 120

      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        fsGroup: 1000

      volumes:
      - name: key-volume
        emptyDir: {}
      - name: config-volume
        configMap:
            name: ${NAME}
            items:
              - key: audit-source
                path: audit-source.properties
      - name: policy-volume
        configMap:
          name: kaudit-policy-${NAME}
          items:
            - key: audit-policy
              path: audit-policy.yaml
      - name: integration-volume
        configMap:
          name: kaudit-integration-${NAME}
          items:
            - key: audit-integration
              path: audit-integration.yaml
      - name: data-filter-volume
        configMap:
          name: kaudit-data-filter-${NAME}
          items:
            - key: audit-data-filter
              path: audit-data-filter.yaml
      - name: data-volume
        persistentVolumeClaim:
          claimName: data-volume-claim-${NAME}

      serviceAccountName: alcide-k8s-${NAME}

      imagePullSecrets:
        - name: registry.alcide.io
      containers:
      - name: ${NAME}
        image: \"gcr.io/dcvisor-162009/alcide/dcvisor/kaudit:latest\"
        #imagePullPolicy: Always for :latest or no tag, IfNotPresent for other tags
        volumeMounts:
        - name: key-volume
          mountPath: /key
        - name: config-volume
          mountPath: /config
        - name: policy-volume
          mountPath: /kaudit/policy
        - name: integration-volume
          mountPath: /kaudit/integration
        - name: data-filter-volume
          mountPath: /kaudit/data-filter
        - name: data-volume
          mountPath: /data
        ports:
          - containerPort: 8443
            protocol: TCP
            name: sec-api
        livenessProbe:
          tcpSocket:
            port: 8443
          initialDelaySeconds: 120
          periodSeconds: 10
          timeoutSeconds: 30
        readinessProbe:
          tcpSocket:
            port: 8443
          initialDelaySeconds: 120
          periodSeconds: 10
          timeoutSeconds: 30
        resources:
          requests:
            memory: \"2Gi\"
            cpu: \"1\"
          limits:
            memory: \"5Gi\"
            cpu: \"1\"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
              - NET_BIND_SERVICE
            drop:
              - all
        env:

        - name: JAVA_OPTS
          value: -Xmx4G -Djava.security.egd=file:/dev/urandom -Dclojure.spec.skip-macros=true -Dclojure.compiler.direct-linking=true

        - name: EXTERNAL_CONFIG_FILE
          value: ${EXTERNAL_CONFIG}

        - name: TOKEN                # GKE-token (for GKE)
          valueFrom:
            secretKeyRef:
              name: ${NAME}
              key: gkeToken

        - name: CONNECTION_STRING    # Azure EventHubName connection (for AKS)
          valueFrom:
            secretKeyRef:
              name: ${NAME}
              key: aksConnectionString

        - name: SECRET_ACCESS_KEY    # AWS Kinesis stream credentials (for EKS)
          valueFrom:
            secretKeyRef:
              name: ${NAME}
              key: awsSecretAccessKey

        - name: STORE_LOCATION
          value: /data
" > ${DEPLOYMENT_FILE}

echo "Generated file: ${DEPLOYMENT_FILE}"
