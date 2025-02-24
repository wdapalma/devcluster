LOGNAME := cluster
ROOT_DIR :=$(abspath ../..)
include $(ROOT_DIR)/base/base.mk

prereq:
	@if ! command -v kind > /dev/null; then \
		echo "Error: 'kind' command not found. Please install kind first."; \
		exit 1; \
	fi

create-cluster:
	@cat cluster-spec.yaml\
	| sed "s|##VOLUME_MOUNT##|$(VOLUME_MOUNT)|g"\
	| sed "s|##CLUSTER_NAME##|$(CLUSTER_NAME)|g"\
	| kind create cluster --name $(CLUSTER_NAME) --kubeconfig ${HOME}/.kube/config --config -

clean:
	@bash -xc "kind delete cluster --name $(CLUSTER_NAME)" | tee
	@bash -xc "rm -fr $(VOLUME_MOUNT)"

