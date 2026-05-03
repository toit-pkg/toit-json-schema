# Copyright (C) 2025 Toit contributors.
# Use of this source code is governed by a Zero-Clause BSD license that can
# be found in the tests/TESTS_LICENSE file.

TOIT_EXECUTABLE ?= toit

.PHONY: all
all: test-suite

.PHONY: test-suite
test-suite: JSON-Schema-Test-Suite
	$(TOIT_EXECUTABLE) test.toit \
		--expected-failures=test-fail.json \
		JSON-Schema-Test-Suite/remotes \
		JSON-Schema-Test-Suite/tests/draft2020-12

JSON-Schema-Test-Suite:
	git clone --depth 1 https://github.com/json-schema-org/JSON-Schema-Test-Suite.git

