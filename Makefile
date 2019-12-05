.DEFAULT_GOAL := all
CHART := ccd-elasticsearch
CI_VALUES := ci-values.yaml
RELEASE := chart-${CHART}-release
NAMESPACE := chart-tests-ccd
TEST := ${RELEASE}-test-service
ACR := hmctspublic
AKS_RESOURCE_GROUP := cnp-aks-rg
AKS_CLUSTER := cnp-aks-cluster

setup:
	az configure --defaults acr=${ACR}
	az acr helm repo add
	az aks get-credentials --resource-group ${AKS_RESOURCE_GROUP} --name ${AKS_CLUSTER} --overwrite-existing
	helm dependency update ${CHART}

clean:
	-helm delete --purge ${RELEASE}
	-kubectl delete pod ${TEST} -n ${NAMESPACE}

lint:
	helm lint ${CHART} --namespace ${NAMESPACE} -f ci-values.yaml

inspect:
	helm inspect chart ${CHART}

upgrade:
	helm upgrade --install ${RELEASE}  ${CHART} --namespace ${NAMESPACE} -f ci-values.yaml  --wait

deploy:
	helm install ${CHART} --name ${RELEASE} --namespace ${NAMESPACE} -f ci-values.yaml  --wait

test:
	helm test ${RELEASE}

all: setup clean lint deploy test

.PHONY: setup clean lint deploy test all
