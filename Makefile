
.SECONDARY:
.SECONDEXPANSION:

VERSION ?= 1.0.0

.phony: help tutorials


create-kind-cluster:  ##@Test create KIND cluster
	kind create cluster --config hack/kind-config.yaml --image kindest/node:v1.16.9 --name kaudit-v1.16

delete-kind-cluster:  ##@Test delete KIND cluster
	kind delete cluster --name kaudit-v1.16

HELM_VERSION=v3.2.4
get-linux-deps: ##@Install Dependencies Linux
	wget -q https://get.helm.sh/helm-$(HELM_VERSION)-linux-amd64.tar.gz -O - | sudo tar -xzO linux-amd64/helm > /usr/local/bin/helm3

INSTALL_OUTDIR=deploy/install
generate-eks:	##@Generate Generate EKS installation
	helm3 template kaudit deploy/charts/kaudit --set tls.mode="external" --set k8sAuditEnvironment=eks > $(INSTALL_OUTDIR)/kaudit_for_eks.yaml

generate-gke:	##@Generate Generate GKE installation
	helm3 template kaudit deploy/charts/kaudit --set tls.mode="external" --set k8sAuditEnvironment=gke > $(INSTALL_OUTDIR)/kaudit_for_gke.yaml

generate-aks:	##@Generate Generate AKS installation
	helm3 template kaudit deploy/charts/kaudit --set tls.mode="external" --set k8sAuditEnvironment=aks > $(INSTALL_OUTDIR)/kaudit_for_aks.yaml

generate-k8s:	##@Generate Generate Audit Sink installation
	helm3 template kaudit deploy/charts/kaudit --set tls.mode="external" --set k8sAuditEnvironment=k8s --set k8s.mode="auditsink" > $(INSTALL_OUTDIR)/kaudit_for_auditsink.yaml	

generate-k8s-webhook:	##@Generate Generate Audit Sink installation
	helm3 template kaudit deploy/charts/kaudit --set tls.mode="external" --set k8sAuditEnvironment=k8s --set k8s.mode="webhook" > $(INSTALL_OUTDIR)/kaudit_for_webhook.yaml	

generate-k8s-with-ingress:	##@Generate Generate Audit Sink installation
	helm3 template kaudit deploy/charts/kaudit --set tls.mode="external" --set k8sAuditEnvironment=k8s --set k8s.mode="auditsink" --set ingress.enable=true > $(INSTALL_OUTDIR)/kaudit_for_auditsink_with_ingress.yaml	


generate-all: generate-k8s generate-aks generate-gke generate-eks generate-k8s-webhook generate-k8s-with-ingress ##@Generate Generate All Deployment targets

HELP_FUN = \
         %help; \
         while(<>) { push @{$$help{$$2 // 'options'}}, [$$1, $$3] if /^(.+)\s*:.*\#\#(?:@(\w+))?\s(.*)$$/ }; \
         print "Usage: make [options] [target] ...\n\n"; \
     for (sort keys %help) { \
         print "$$_:\n"; \
         for (sort { $$a->[0] cmp $$b->[0] } @{$$help{$$_}}) { \
             $$sep = " " x (30 - length $$_->[0]); \
             print "  $$_->[0]$$sep$$_->[1]\n" ; \
         } print "\n"; }



help: ##@Misc Show this help
	@perl -e '$(HELP_FUN)' $(MAKEFILE_LIST)	

.DEFAULT_GOAL := help

USERID=$(shell id -u)	