@echo off
setlocal

REM ##########################################
REM Creating k8s deployment for Alcide kAudit.
REM ##########################################

cls
echo Alcide\'s kAudit Deployment Generator
echo -------------------------------------
echo.
set /P CLUSTER_NAME="Cluster name: "
if "x%CLUSTER_NAME%"=="x" (
  echo "No cluster name"
  goto :EOF
)

REM Cluster type: k8s, gke, aks, eks, s3
set CLUSTER_TYPE=""

:TYPELOOP
set /P CLUSTER_TYPE_REPLY="Type Of Monitored Cluster: [G] GKE / [E] EKS / [A] AKS / [K] Kubernetes (native) / [S] S3 backup bucket / [0] Exit "
REM Call and mask out invalid call targets
goto switch-case-N-%CLUSTER_TYPE_REPLY% 2>nul || (
  REM Default case
  echo Invalid selection
)
goto :TYPELOOP

:switch-case-N-G
  set CLUSTER_TYPE="gke"
  set /P GKE_TOKEN="GKE access token (for StackDriver, base64-encoded): "
  if "x"=="x%GKE_TOKEN%" (
    echo No GKE access token
    goto :EOF
  )
  set /P GKE_PROJECT="GKE project of the cluster: "
  if "x"=="x%GKE_PROJECT%" (
    echo No GKE project
    goto :EOF
  )
  goto :TYPELOOPEND

:switch-case-N-E
  set CLUSTER_TYPE=eks
  set /P AWS_ACCESS_KEY_ID="AWS access key id (for Kinesis stream): "
  if "x"=="x%AWS_ACCESS_KEY_ID%" (
    echo No AWS access key id
    goto :EOF
  )
  set /P AWS_SECRET_ACCESS_KEY="AWS secret access key (for Kinesis stream, base64-encoded): "
  if "x"=="x%AWS_SECRET_ACCESS_KEY%" (
    echo No AWS secret access key
    goto :EOF
  )
  set /P AWS_REGION="AWS region (for Kinesis stream): "
  if "x"=="x%AWS_REGION%" (
    echo No AWS region
    goto :EOF
  )
  set /P AWS_STREAM_NAME="AWS Kinesis stream name: "
  if "x"=="x%AWS_STREAM_NAME%" (
    echo No AWS Kinesis stream name
    goto :EOF
  )
  goto :TYPELOOPEND

:switch-case-N-A
  set CLUSTER_TYPE="aks"
  set /P AKS_EVENT_HUB_NAME="Azure EventHub name: "
  if "x"=="x%AKS_EVENT_HUB_NAME%" (
    echo No Azure EventHub name
    goto :EOF
  )
  set /P AKS_CONNECTION_STRING="Azure EventHub connection string (base64-encoded): "
  if "x"=="x%AKS_CONNECTION_STRING%" (
    echo No Azure EventHub connection string
    goto :EOF
  )
  set /P AKS_CONSUMER_GROUP_NAME="Azure EventHub ConsumerGroup name [default: $Default]: "
  goto TYPELOOPEND

:switch-case-N-K
  set CLUSTER_TYPE=k8s
  echo Reminder: Kubernetes Audit Sink should created on the cluster
  goto :TYPELOOPEND

:switch-case-N-S
  set CLUSTER_TYPE=s3
  set /P AWS_ACCESS_KEY_ID="AWS access key id (for S3): "
  if "x"=="x%AWS_ACCESS_KEY_ID%" (
    echo No AWS access key id
    goto :EOF
  )
  set /P AWS_SECRET_ACCESS_KEY="AWS secret access key (for S3, base64-encoded): "
  if "x"=="x%AWS_SECRET_ACCESS_KEY%" (
    echo No AWS secret access key
    goto :EOF
  )
  set /P AWS_REGION="AWS region (for S3): "
  if "x"=="x%AWS_REGION%" (
    echo No AWS region
    goto :EOF
  )
  set /P AWS_BUCKET_NAME="S3 bucket name: "
  if "x"=="x%AWS_BUCKET_NAME%" (
    echo No S3 bucket name
    goto :EOF
  )
  set /P AWS_RESOURCE_KEY_PREFIX="S3 resources keys prefix: "
  goto TYPELOOPEND

:switch-case-N-0
  exit /b 0

:TYPELOOPEND

set NAMESPACE="alcide-kaudit"
set /P NAMESPACE_REPLY="Deployment namespace: [default: %NAMESPACE%] "
if not "x"=="x%NAMESPACE_REPLY%" (
  set NAMESPACE=%NAMESPACE_REPLY%
)

set /P ALCIDE_REPOSITORY_TOKEN="Alcide repository token: "
if "x"=="x%ALCIDE_REPOSITORY_TOKEN%" (
  echo No Alcide repository token
  goto :EOF
)

REM TODO normalize cluster name as k8s object name part, not assuming sed, tr etc. exist
REM should be alphanumeric or '-'
set LEGIT_NAME=%CLUSTER_NAME%

set NAME=kaudit-%LEGIT_NAME%
set DEPLOYMENT_FILE=%NAME%.yaml

(
echo ---
echo.
echo apiVersion: v1
echo kind: Namespace
echo metadata:
echo   name: %NAMESPACE%
echo spec:
echo.
echo ---
echo.
echo apiVersion: v1
echo kind: Secret
echo metadata:
echo   name: registry.alcide.io
echo   namespace: %NAMESPACE%
echo   labels:
echo     app: kaudit
echo   annotations:
echo     com.alcide.io/component.role: alcide-registry
echo     com.alcide.io/info.vendor: "Alcide IO Inc."
echo type: kubernetes.io/dockerconfigjson
echo data:
echo   .dockerconfigjson: "%ALCIDE_REPOSITORY_TOKEN%" # authentication token
echo.
echo ---
echo.
echo apiVersion: v1
echo kind: Secret
echo metadata:
echo   name: %NAME%
echo   namespace: %NAMESPACE%
echo   labels:
echo     app: kaudit
echo     app-name: %NAME%
echo type: Opaque
echo data:
echo   # GKE-token ^(for GKE^)
echo   gkeToken: "%GKE_TOKEN%"
echo   # Azure EventHub connection string ^(for AKS^)
echo   aksConnectionString: "%AKS_CONNECTION_STRING%"
echo   # AWS Kinesis stream credentials ^(for EKS and S3^)
echo   awsSecretAccessKey: "%AWS_SECRET_ACCESS_KEY%"
echo.
echo ---
echo.
echo apiVersion: v1
echo kind: ConfigMap
echo metadata:
echo   name: %NAME%
echo   namespace: %NAMESPACE%
echo   labels:
echo     app: kaudit
echo     app-name: %NAME%
echo data:
echo   ca.pem: "" # pem certificate
echo   metadata-exclusion: "kubectl.kubernetes.io/last-applied-configuration"
echo   audit-source: ^|
echo     audit-env: %CLUSTER_TYPE%                                 # Audit Logs Source - one of: k8s, gke, aks, eks, s3
echo     cluster: "%CLUSTER_NAME%"                                 # Name of cluster. For GKE - the GKE cluster name, otherwise - user provided unique name.
echo     project: "%GKE_PROJECT%"                                  # GKE-project ^(for GKE^)
echo     pubsub-subscription-id: "%GKE_PUBSUB_SUBSCRIPTION_ID%"    # GKE PubSub subscription ID ^(only if consuming audit logs via PubSub instead of StackDriver^)
echo     event-hub-name: "%AKS_EVENT_HUB_NAME%"                    # Azure EventHubName name ^(for AKS^).
echo     consumer-group-name: "%AKS_CONSUMER_GROUP_NAME%"          # Azure EventHubName ConsumerGroup name ^(for AKS^), if using a non-default ConsumerGroup ^(i.e. $Default^).
echo     stream-name: "%AWS_STREAM_NAME%"                          # AWS Kinesis stream name ^(for EKS^)
echo     region: "%AWS_REGION%"                                    # AWS Kinesis stream region ^(for EKS and S3^)
echo     access-key-id: "%AWS_ACCESS_KEY_ID%"                      # AWS Kinesis stream credentials ^(for EKS and S3^)
echo     bucket-name: "%AWS_BUCKET_NAME%"                          # AWS S3 bucket name ^(for S3^)
echo     resource-key-prefix: "%AWS_RESOURCE_KEY_PREFIX%"          # AWS S3 logs resources keys prefix ^(for S3^)
echo.
echo ---
echo.
echo apiVersion: v1
echo kind: ServiceAccount
echo metadata:
echo   name: alcide-k8s-%NAME%
echo   namespace: %NAMESPACE%
echo.
echo ---
echo.
echo apiVersion: v1
echo kind: PersistentVolumeClaim
echo metadata:
echo   name: data-volume-claim-%NAME%
echo   namespace: %NAMESPACE%
echo spec:
echo   storageClassName:
echo   accessModes:
echo   - ReadWriteOnce
echo   resources:
echo     requests:
echo       storage: 100Gi
echo.
echo ---
echo.
echo apiVersion: v1
echo kind: Service
echo metadata:
echo   name: %NAME%
echo   namespace: %NAMESPACE%
echo   labels:
echo     app: kaudit
echo     app-name: %NAME%
echo spec:
echo   ports:
echo     - port: 443
echo       protocol: TCP
echo       targetPort: 8443
echo       name: ui
echo   selector:
echo     app-name: %NAME%
echo.
echo ---
echo.
echo apiVersion: apps/v1
echo kind: StatefulSet
echo metadata:
echo   name: %NAME%
echo   namespace: %NAMESPACE%
echo   labels:
echo     app: kaudit
echo     app-name: %NAME%
echo   annotations:
echo     com.alcide.io/component.role: cloud-audit-k8s
echo     com.alcide.io/component.tier: database
echo     com.alcide.io/info.vendor: Alcide IO Inc.
echo spec:
echo   selector:
echo     matchLabels:
echo       app-name: %NAME%
echo   serviceName: %NAME%
echo   replicas: 1
echo   template:
echo     metadata:
echo       labels:
echo         app: kaudit
echo         app-name: %NAME%
echo       annotations:
echo         policy.alcide.io/inbound0: service://%NAME%
echo         policy.alcide.io/inbound1: tcp://any:8443
echo         policy.alcide.io/outbound0: service://kube-dns
echo         policy.alcide.io/outbound1: service://coredns
echo         policy.alcide.io/outbound2: service://%NAME%
echo     spec:
echo       terminationGracePeriodSeconds: 120
echo.
echo       securityContext:
echo         runAsNonRoot: true
echo         runAsUser: 10001
echo         fsGroup: 1000
echo.
echo       volumes:
echo       - name: key-volume
echo         emptyDir: {}
echo       - name: config-volume
echo         configMap:
echo             name: %NAME%
echo             items:
echo               - key: audit-source
echo                 path: audit-source.properties
echo       - name: data-volume
echo         persistentVolumeClaim:
echo           claimName: data-volume-claim-%NAME%
echo.
echo       serviceAccountName: alcide-k8s-%NAME%
echo.
echo       imagePullSecrets:
echo         - name: registry.alcide.io
echo       containers:
echo       - name: %NAME%
echo         image: "gcr.io/dcvisor-162009/alcide/dcvisor/kaudit:latest"
echo         #imagePullPolicy: Always for :latest or no tag, IfNotPresent for other tags
echo         volumeMounts:
echo         - name: key-volume
echo           mountPath: /key
echo         - name: config-volume
echo           mountPath: /config
echo         - name: data-volume
echo           mountPath: /data
echo         ports:
echo           - containerPort: 8443
echo             protocol: TCP
echo             name: sec-api
echo         livenessProbe:
echo           tcpSocket:
echo             port: 8443
echo           initialDelaySeconds: 120
echo           periodSeconds: 10
echo           timeoutSeconds: 30
echo         readinessProbe:
echo           tcpSocket:
echo             port: 8443
echo           initialDelaySeconds: 120
echo           periodSeconds: 10
echo           timeoutSeconds: 30
echo         resources:
echo           requests:
echo             memory: "2Gi"
echo             cpu: "1"
echo           limits:
echo             memory: "8Gi"
echo             cpu: "2"
echo         securityContext:
echo           allowPrivilegeEscalation: false
echo           capabilities:
echo             add:
echo               - NET_BIND_SERVICE
echo             drop:
echo               - all
echo         env:
echo         - name: JAVA_OPTS
echo           value: -Xmx7G -Djava.security.egd=file:/dev/urandom -Dclojure.spec.skip-macros=true -Dclojure.compiler.direct-linking=true
echo.
echo         - name: TOKEN                # GKE-token ^(for GKE^)
echo           valueFrom:
echo             secretKeyRef:
echo               name: %NAME%
echo               key: gkeToken
echo.
echo         - name: CONNECTION_STRING    # Azure EventHubName connection ^(for AKS^)
echo           valueFrom:
echo             secretKeyRef:
echo               name: %NAME%
echo               key: aksConnectionString
echo.
echo         - name: SECRET_ACCESS_KEY    # AWS Kinesis stream credentials ^(for EKS^)
echo           valueFrom:
echo             secretKeyRef:
echo               name: %NAME%
echo               key: awsSecretAccessKey
echo.
echo         - name: STORE_LOCATION
echo           value: /data
) > "%DEPLOYMENT_FILE%"

echo Generated file: %DEPLOYMENT_FILE%

:EOF