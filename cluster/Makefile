LOGNAME := cluster
ROOT_DIR :=$(abspath ..)
include $(ROOT_DIR)/base/base.mk

.DEFAULT_GOAL := all

all:
	@echo "[cluster] $@"
	@rm -f $(LOGFILE)
	$(R) make -C $(CLUSTER_KIND) prereq
	$(R) make -C $(CLUSTER_KIND) create-cluster

clean:
	@echo "[cluster] $@"
	$(R) make -C $(CLUSTER_KIND) clean
