ifndef ROOT_DIR
$(error ROOT_DIR is not set)
endif

include $(ROOT_DIR)/defaults.env
include $(ROOT_DIR)/settings.env

R := @bash $(ROOT_DIR)/base/wrapper.sh
LOGNAME ?= wrapper
export LOGDIR  := $(ROOT_DIR)/.logs
export LOGFILE := $(LOGDIR)/$(LOGNAME).log

KUBECTX ?= $(CLUSTER_KIND)-$(CLUSTER_NAME)
KCTL    := kubectl --context $(KUBECTX)
HELM    := helm --kube-context $(KUBECTX)
PGENTRY := PGPASSWORD=$$POSTGRES_POSTGRES_PASSWORD /opt/bitnami/scripts/postgresql/entrypoint.sh

ifndef NAMESPC
#$(error NAMESPC is not set)
else
KCTL_NS := $(KCTL) -n $(NAMESPC)
HELM_NS := $(HELM) --namespace $(NAMESPC)
endif

## Base Targets
.PHONY: mktarget clonerepo clonepath buildimage readonly-dockerhub

mktarget:
	@mkdir -p target

## Cloning and Building
CLONE_PATH := target/clone.$(REPO)
IMAGE_PATH := target/image.$(REPO)
CERTIMAGE_PATH := target/certimage.$(REPO)

clonerepo: $(CLONE_PATH)
$(CLONE_PATH):
ifndef LOCALDIR
	$(if $(REPO),,$(error REPO not set))
	$(if $(BRANCH),,$(error BRANCH not set))
	@make mktarget
	@rm -fr $@
	git clone --quiet --depth 1 --branch $(BRANCH) git@github.com:wdapalma/$(REPO).git $@
	touch $@
else
	@echo "Warning: git clone skipped, using $(LOCALDIR)"
endif

clonepath:
ifndef LOCALDIR
	$(if $(REPO),,$(error REPO not set))
	@echo $(CLONE_PATH)
else
	@echo $(LOCALDIR)
endif

DOCKERFILE ?= Dockerfile
ifndef LOCALDIR
FQ_DOCKERFILE ?= $(CLONE_PATH)/$(DOCKERFILE)
else
FQ_DOCKERFILE ?= $(LOCALDIR)/$(DOCKERFILE)
endif

buildimage: $(IMAGE_PATH)
$(IMAGE_PATH):
	$(if $(REPO),,$(error REPO not set))
	$(if $(IMAGE),,$(error IMAGE not set))
	@make mktarget
ifndef LOCALDIR
	make netrc
	DOCKER_BUILDKIT=1 docker build -t $(IMAGE) -f $(FQ_DOCKERFILE) $(CLONE_PATH) --ssh=default $(EXTRA_ARGS)
else
	@echo "+ Warning: using local $(LOCALDIR)"
	DOCKER_BUILDKIT=1 docker build -t $(IMAGE) -f $(FQ_DOCKERFILE) $(LOCALDIR) --ssh=default $(EXTRA_ARGS)
	@touch $@
endif

buildimage_cacert: $(CERTIMAGE_PATH)
$(CERTIMAGE_PATH): target/Keycloak-RootCA.crt $(IMAGE_PATH)
	$(if $(IMAGE),,$(error IMAGE not set))
	docker image tag $(IMAGE) $(IMAGE)-og
	docker build -t $(IMAGE) -f ../base/Dockerfile . --build-arg BASE_IMAGE=$(IMAGE) $(EXTRA_ARGS)
	@touch $@

# Download RootCA used by Keycloak
target/Keycloak-RootCA.crt:
	@make mktarget
	$(KCTL) -n keycloak get secret tls-secret -o jsonpath='{.data.ca\.crt}' | base64 -d > $@.tmp
	@grep CERTIFICATE $@.tmp > /dev/null
	mv $@.tmp $@

# Database targets
createdb: target/createdb
target/createdb:
	$(if $(DBNAME),,$(error DBNAME not set))
	$(KCTL) -n postgresql exec -it postgresql-0 -- /bin/sh -c '$(PGENTRY) createdb --host=postgresql --owner=dbuser1 $(DBNAME)'
	@make mktarget
	@touch $@

dropdb:
	$(if $(DBNAME),,$(error DBNAME not set))
	$(KCTL) -n postgresql exec -it postgresql-0 -- /bin/sh -c '$(PGENTRY) dropdb --host=postgresql $(DBNAME) --if-exists'
	rm -f target/createdb

dbdrop-sessions:
	$(eval CMD := SELECT pg_terminate_backend (pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = current_database() AND pid <> pg_backend_pid();)
	@make psql DBNAME=keycloak COMMAND="$(CMD)" | tee

psql:
	$(if $(DBNAME),,$(error DBNAME not set))
	$(if $(COMMAND),,$(error COMMAND not set))
	$(eval PGSHELL := $(KCTL) -n postgresql exec -it postgresql-0 -- /bin/sh)
	$(PGSHELL) -c 'PGPASSWORD=$$POSTGRES_PASSWORD psql -U dbuser1 -d $(DBNAME) -c "$(COMMAND)"'

# Bucket targets
createbucket:
	$(if $(BUCKETNAME),,$(error BUCKETNAME not set))
	@bash -xc 'mc mb --insecure --ignore-existing playground/$(BUCKETNAME)'

removebucket:
	$(if $(BUCKETNAME),,$(error BUCKETNAME not set))
	@bash -xc 'mc rb --insecure playground/$(BUCKETNAME) --force 2>/dev/null' | tee

listbuckets:
	@bash -xc 'mc ls --insecure playground'

# Create readonly-dockerhub docker-registry secret
readonly-dockerhub: target/readonly-dockerhub.json
	$(KCTL_NS) create secret docker-registry readonly-dockerhub --from-file .dockerconfigjson=$< --dry-run=client -o yaml | $(KCTL) apply -f -

# Generate dockerconfigjson for readonly-dockerhub
readonly-dockerconfigjson: target/readonly-dockerhub.json
	@$(KCTL_NS) create secret docker-registry readonly-dockerhub --from-file .dockerconfigjson=$< --dry-run=client -o json | jq -r '.data.".dockerconfigjson"'

target/readonly-dockerhub.json: ../cluster/readonly-dockerhub.json
	$(if $(NEXUS_USER),,$(error NEXUS_USER not set))
	$(if $(NEXUS_PASS),,$(error NEXUS_PASS not set))
	$(if $(NEXUS_STAGE_USER),,$(error NEXUS_STAGE_USER not set))
	$(if $(NEXUS_STAGE_PASS),,$(error NEXUS_STAGE_PASS not set))
	$(eval TOKEN := $(shell bash -c 'echo -n "$(NEXUS_USER):$(NEXUS_PASS)" | base64'))
	$(eval STAGETOKEN := $(shell bash -c 'echo -n "$(NEXUS_STAGE_USER):$(NEXUS_STAGE_PASS)" | base64'))
	@make mktarget
	@jq --null-input --arg user "$(NEXUS_USER)" --arg pass "$(NEXUS_PASS)" --arg auth "$(TOKEN)" --arg stageuser "$(NEXUS_STAGE_USER)" --arg stagepass "$(NEXUS_STAGE_PASS)" --arg stageauth "$(STAGETOKEN)" '$(shell cat $<)' > $@.tmp
	@mv $@.tmp $@
