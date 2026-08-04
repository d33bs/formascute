SHELL := /usr/bin/env bash

EXPERIMENT ?= independent_jobs
ITEMS ?= 16
BATCH_SIZE ?=
RUN_ID ?=
PROFILE ?= alpine
ACCOUNT ?=
PARTITION ?= acpu
QOS ?= cpu-normal
SUBMIT_HOST ?=

ARGS :=
ifneq ($(strip $(RUN_ID)),)
ARGS += --run-id $(RUN_ID)
endif
ifneq ($(strip $(ITEMS)),)
ARGS += --items $(ITEMS)
endif
ifneq ($(strip $(BATCH_SIZE)),)
ARGS += --batch-size $(BATCH_SIZE)
endif

.PHONY: help bootstrap check lint prek doctor preflight smoke run submit submit-dry-run list-experiments

help:
	@bash bin/formascute --help
	@printf '\nMake targets:\n'
	@printf '  make bootstrap\n'
	@printf '  make check\n'
	@printf '  make lint\n'
	@printf '  make prek\n'
	@printf '  make doctor\n'
	@printf '  make preflight ACCOUNT=<allocation>\n'
	@printf '  make smoke\n'
	@printf '  make run EXPERIMENT=independent_jobs ITEMS=16\n'
	@printf '  make submit EXPERIMENT=independent_jobs ITEMS=16 ACCOUNT=<allocation>\n'
	@printf '  make submit-dry-run EXPERIMENT=independent_jobs ITEMS=16 ACCOUNT=<allocation>\n'
	@printf '  make list-experiments\n'
	@printf '\nMake variables:\n'
	@printf '  EXPERIMENT   Experiment name from conf/experiments. Default: independent_jobs\n'
	@printf '  ITEMS        Number of synthetic work items. Default: 16\n'
	@printf '  BATCH_SIZE   Work items per Nextflow task. Default: experiment default\n'
	@printf '  RUN_ID       Output directory name under results/. Default: UTC timestamp\n'
	@printf '  PROFILE      Nextflow profile for make run. Default: alpine\n'
	@printf '  ACCOUNT      Slurm account/allocation for make submit. Default: none\n'
	@printf '  PARTITION    Slurm partition for make submit. Default: acpu\n'
	@printf '  QOS          Slurm QoS for make submit. Default: cpu-normal\n'
	@printf '  SUBMIT_HOST  Optional SSH host used to run sbatch. Alpine: Persistence1\n'
	@printf '\nEnvironment overrides:\n'
	@printf '  FORMASCUTE_NEXTFLOW_MODULE    Module loaded in generated Slurm scripts; default nextflow/25.10.2\n'
	@printf '  FORMASCUTE_CONTAINER_MODULE   Optional container module loaded in generated Slurm scripts\n'
	@printf '  FORMASCUTE_ENABLE_CONTAINER   Enable Nextflow Singularity support; default false\n'
	@printf '  FORMASCUTE_ENV_DIR            Bootstrap env directory; default .formascute/conda\n'
	@printf '  FORMASCUTE_SCRATCH            Shared scratch root; default /scratch/alpine/$$USER\n'
	@printf '  FORMASCUTE_PROJECT            Project/cache root; default /projects/$$USER\n'

bootstrap:
	@bash scripts/bootstrap

check:
	@bash scripts/check

lint:
	@bash scripts/lint

prek:
	@if command -v prek >/dev/null 2>&1; then \
	  prek run --all-files; \
	elif command -v pre-commit >/dev/null 2>&1; then \
	  pre-commit run --all-files; \
	else \
	  printf 'Install prek or pre-commit, then rerun: make prek\n' >&2; \
	  printf '  python -m pip install prek\n' >&2; \
	  exit 127; \
	fi

doctor:
	@bash bin/formascute doctor

preflight:
	@bash bin/formascute preflight $(if $(RUN_ID),--run-id $(RUN_ID)) --account "$(ACCOUNT)" --partition "$(PARTITION)" --qos "$(QOS)"

smoke:
	@bash bin/formascute run-local-smoke $(if $(RUN_ID),--run-id $(RUN_ID))

run:
	@FORMASCUTE_ACCOUNT="$(ACCOUNT)" FORMASCUTE_PARTITION="$(PARTITION)" FORMASCUTE_QOS="$(QOS)" \
	  bash bin/formascute run $(EXPERIMENT) --profile $(PROFILE) $(ARGS) --account "$(ACCOUNT)" --partition "$(PARTITION)" --qos "$(QOS)"

submit:
	@bash bin/formascute submit $(EXPERIMENT) $(ARGS) --account "$(ACCOUNT)" --partition "$(PARTITION)" --qos "$(QOS)" $(if $(SUBMIT_HOST),--submit-host "$(SUBMIT_HOST)")

submit-dry-run:
	@bash bin/formascute submit $(EXPERIMENT) $(ARGS) --account "$(ACCOUNT)" --partition "$(PARTITION)" --qos "$(QOS)" $(if $(SUBMIT_HOST),--submit-host "$(SUBMIT_HOST)") --dry-run

list-experiments:
	@find conf/experiments -maxdepth 1 -type f -name '*.config' | sed 's#conf/experiments/##; s#\.config##' | sort
