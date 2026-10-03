# Developer entry points. `make check` is what CI runs on every push.
SHELL := bash
SCRIPTS := usb-audio-mapper.sh $(wildcard tests/e2e/*.sh) tests/bash-matrix.sh tests/mutation.sh \
	tests/helpers/bin/udevadm tests/helpers/bin/logger tests/test_helper.bash
SHFMT_FLAGS := -i 4 -bn -ci
E2E_DEPS ?= .cache/e2e

.PHONY: check lint fmt test test-awk bash-matrix mutation e2e-deps e2e e2e-matrix clean

check: lint test

lint:
	bash -n usb-audio-mapper.sh
	shellcheck -x $(SCRIPTS)
	shfmt -d $(SHFMT_FLAGS) usb-audio-mapper.sh tests/e2e/*.sh tests/bash-matrix.sh tests/mutation.sh tests/helpers/bin/*

fmt:
	shfmt -w $(SHFMT_FLAGS) usb-audio-mapper.sh tests/e2e/*.sh tests/bash-matrix.sh tests/mutation.sh tests/helpers/bin/*

# Unit/integration tests against a fake sysfs (no root, no udev needed).
# AWK=mawk|gawk|original-awk|busybox selects the awk the mapper sees.
test:
	@if [[ -n "$(AWK)" ]]; then \
		d=$$(mktemp -d); trap 'rm -rf "$$d"' EXIT; \
		if [[ "$(AWK)" == busybox ]]; then printf '#!/bin/sh\nexec busybox awk "$$@"\n' >"$$d/awk"; \
		else ln -s "$$(command -v $(AWK))" "$$d/awk"; fi; \
		chmod +x "$$d/awk"; echo "awk -> $(AWK)"; PATH="$$d:$$PATH" bats tests/; \
	else bats tests/; fi

test-awk:
	for a in gawk mawk original-awk busybox; do $(MAKE) --no-print-directory test AWK=$$a || exit 1; done

bash-matrix:
	tests/bash-matrix.sh

# Re-introduce known defects; every one must make the suite fail.
mutation:
	tests/mutation.sh

e2e-deps:
	tests/e2e/fetch-deps.sh $(E2E_DEPS)

# Real kernel + real systemd-udevd in QEMU (host kernel/udev by default).
e2e:
	tests/e2e/run.sh

e2e-matrix: e2e-deps
	for u in host 241 247 262; do \
		r=; [[ $$u == host ]] || r=$(E2E_DEPS)/udev-$$u; \
		echo "== udev $$u"; E2E_KERNEL_ROOT=$(E2E_DEPS)/kernel E2E_UDEV_ROOT=$$r tests/e2e/run.sh || exit 1; \
	done

clean:
	rm -rf .cache
