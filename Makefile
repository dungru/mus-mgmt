SHELL := /bin/bash


PY =
_find_py:
ifeq ($(PY),)
ifneq ($(wildcard $(CURDIR)/.venv/bin/python),)
	$(eval PY = $(CURDIR)/.venv/bin/python)
else
	$(eval PY = $(shell pipenv --py 2>/dev/null || which python3))
endif
endif


init:
	@python3 -m venv .venv
	@.venv/bin/python -m pip install --upgrade pip
	@.venv/bin/python -m pip install --requirement requirements-dev.txt
	@.venv/bin/pre-commit install
	@.venv/bin/pre-commit install --hook-type commit-msg
	@echo Environment-ready:.venv


fmt: _find_py
	@$(PY) -m black .
	@find . -type f -name "*.py" | xargs $(PY) -m reorder_python_imports


lint: _find_py
	@$(PY) -m flake8 .


TYPE = smoke_tests
ROOTDIR = $(PWD)/$(TYPE)
AUTO_REPORT ?= 1
ALLURE := $(firstword $(wildcard $(HOME)/.local/bin/allure) $(shell command -v allure 2>/dev/null))
MARKER =
ENV =
OPTS =
TESTCASE =
PYTEST_OPTS =
PYTEST_OPTS += $(TESTCASE)
PYTEST_OPTS += $(OPTS)
ifneq ($(MARKER),)
	PYTEST_OPTS += -k "$(MARKER)"
endif
ifneq ($(ENV),)
	PYTEST_OPTS += --environment="$(ENV)"
endif
ifneq ($(CLINGENV_URL),)
	PYTEST_OPTS += --clingenv_url="$(CLINGENV_URL)"
endif
test: _find_py clean
	@set +e; \
	pushd $(ROOTDIR) > /dev/null; \
	ANSIBLE_CONFIG=$(PWD)/ansible.cfg $(PY) -m pytest $(PYTEST_OPTS); \
	test_status=$$?; \
	popd > /dev/null; \
	report_status=0; \
	if [ "$(AUTO_REPORT)" != "0" ]; then \
		if [ -n "$(ALLURE)" ]; then \
			$(ALLURE) generate $(ROOTDIR)/report \
				--output $(ROOTDIR)/allure-report --clean; \
			report_status=$$?; \
		else \
			echo "WARNING: Allure CLI not found; static report was not generated."; \
		fi; \
	fi; \
	if [ $$test_status -ne 0 ]; then exit $$test_status; fi; \
	exit $$report_status


report:
	@if [ -z "$(ALLURE)" ]; then \
		echo "ERROR: Allure CLI not found."; exit 1; \
	fi
	@$(ALLURE) generate $(ROOTDIR)/report \
		--output $(ROOTDIR)/allure-report --clean


clean:
	@find $(PWD) -type f -name '*.py[co]' \
			-o -type d -name __pycache__ \
			-o -type d -name .pytest_cache \
		| xargs rm -rf
	@rm -rf */report
	@rm -rf $(ROOTDIR)/report


REGISTRY = docker.dutsai.com
REPO = sv/dutsai-mgmt
TAG = latest
docker:
	docker build --no-cache -t $(REGISTRY)/$(REPO):$(TAG) .
