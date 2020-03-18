![Test Alcide kAudit Chart](https://github.com/alcideio/kaudit/workflows/Test%20Alcide%20kAudit%20Chart/badge.svg)

<img src="https://www.alcide.io/wp-content/themes/alcide/images/kaudit/ALCID%20KAUDIT@2x.png" alt="Alcide Code-to-production secutiry" width="400" 
/>

## Installation

* EKS
* GKE
* AKS
* Kubernetes Webhook
* Kubernetes Dynamic Auditing (AuditSink)

### In the Makefile

```bash
Usage: make [options] [target] ...

Generate:
  generate-aks                  Generate AKS installation
  generate-all                  Generate All Deployment targets
  generate-eks                  Generate EKS installation
  generate-gke                  Generate GKE installation
  generate-k8s                  Generate Audit Sink installation
  generate-k8s-webhook          Generate Audit Sink installation

Install:
  get-linux-deps                Dependencies Linux

Misc:
  help                          Show this help

Test:
  create-kind-cluster           KIND
  create-minikube-cluster       Minikube

```

# Create local test environment (Dynamic Auditing)

**Kubernetes [KIND](https://kind.sigs.k8s.io/)**

```bash
kind create cluster --config hack/kind-config.yaml --image kindest/node:v1.16.4 --name kaudit-v1.16
```

**[Minikube](https://kubernetes.io/docs/tasks/tools/install-minikube/)**

```bash
	minikube start --memory=6g --cpus=4 \
        --extra-config=apiserver.audit-dynamic-configuration=true \
        --extra-config=apiserver.feature-gates=DynamicAuditing=true \
        --extra-config=apiserver.runtime-config=auditregistration.k8s.io/v1alpha1=true  
```


# Before Installing Alcide kAudit

- [Download helm 3](https://helm.sh/docs/intro/install/)
    ```bash
   curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 && \
   chmod 700 get_helm.sh && \
   ./get_helm.sh
    ```
- Make sure you have the Image registry pull secret key from Alcide

# Installation Examples

### Kubernetes Webhook

```bash
helm upgrade -i kaudit deploy/charts/kaudit --set clusterName="mycluster" --set k8s.mode="webhook" --set image.pullSecretToken="YourAlcideToken"
```

### Kubernetes AuditSink

```bash
helm upgrade -i kaudit deploy/charts/kaudit --set clusterName="mycluster" --set image.pullSecretToken="YourAlcideToken"
```

or use the interactive wizard to generate a YAML:

```bash
deploy/install/kaudit-deployment-wizard.sh
```

And than run:

```bash
kubectl port-forward -n alcide-kaudit svc/kaudit-mycluster  7000:443
```

Point your browser to https://localhost:7000

# Access Alcide kAudit From Outside The Cluster

## Kubernetes Ingress Controller

Notes:
- You should have a DNS entry that points to the cluster
- By default self-signed certificates are generated
- See chart [values.yaml](deploy/charts/kaudit/values.yaml) on how to use external certificates
- The default domain in this example: *secops.mycompany.com*
- Use `--set ingress.subDomain="yourdomain.com"` to customise the sub-domain used to expose your Alcide kAudit analyzer(s).


### *Create KIND Cluster*
```bash
kind create cluster --config hack/kind-config.yaml --image kindest/node:v1.16.4 --name kaudit-v1.16
```

### *Install Kubernetes Ingress Controller*

  ```bash
  helm upgrade -i kaudit-ingress stable/nginx-ingress --namespace alcide-kaudit --set controller.daemonset.useHostPort=true --set controller.service.enabled=false --set controller.kind="DaemonSet" --set controller.ingressClass="kaudit-ingress"
  ```

### *Install Alcide kAudit*

   ```bash 
   helm upgrade -i kaudit deploy/charts/kaudit --set clusterName="mycluster" --set ingress.enable=true
   ```

Test that Alcide kAudit is exposed through 

```bash
curl  -D-  -k https://localhost:443/  -H 'Host: kaudit-mycluster.secops.mycompany.com'
```


# Integration with Hashicorp Vault

>**See Vault Agent Injector guide [here]( https://www.hashicorp.com/blog/injecting-vault-secrets-into-kubernetes-pods-via-a-sidecar/)**


#### Create kAudit Vault Policy

```bash
kubectl -n demo exec -ti vault-0 /bin/sh
cat <<EOF > /home/vault/kaudit-policy.hcl
path "secret/data/alcide/kaudit-*" {
  capabilities = ["read"]
}
EOF
```

```bash
vault policy write kaudit /home/vault/kaudit-policy.hcl
```

### Vault Kubernetes Integration

> ```kubectl -n demo exec -ti vault-0 /bin/sh```

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
   token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
   kubernetes_host=https://${KUBERNETES_PORT_443_TCP_ADDR}:443 \
   kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

### Configure kAudit in Vault

Note how kAudit is installed into the cluster:
* namespace 
* service account 

```bash
vault write auth/kubernetes/role/kaudit-mycluster \
   bound_service_account_names=alcide-k8s-kaudit-mycluster \
   bound_service_account_namespaces=alcide-kaudit \
   policies=kaudit \
   ttl=1h
```

Create a vault secret for the kAudit instance being deployed:

```bash
 vault kv put secret/alcide/kaudit-mycluster \
    token=''  \
    prometheusToken=''  \
    gkeToken='' \
    aksConnectionString=''  \
    awsSecretAccessKey='somesecret'
```

### Install Alcide kAudit

> * Download helm 3
> * Make sure you have the Image registry key from Alcide

Interactive wizard:
```bash
deploy/install/kaudit-deployment-wizard.sh
```

#### Helm (v3 and onward)

**Vault Agent Injector**

```bash
helm upgrade -i kaudit deploy/charts/kaudit --set clusterName="mycluster" --set vault.mode="agent-inject"
```
**Vault**

```bash
helm upgrade -i kaudit deploy/charts/kaudit --set clusterName="mycluster" --set vault.mode="vault"
```
