# Top-level build: assembles tests, generates expected outputs, and runs single
# tests or the full regression in Xcelium.
PYTHON ?= python3
TEST ?= ebreak
TEST_DIR := tests/$(TEST)
MAX_CPU_CYCLES ?= 1000
CROSSBAR_TIMEOUT ?= 20

TEST_NAMES := $(sort $(notdir $(patsubst %/,%,$(dir $(wildcard tests/*/program.asm)))))

.PHONY: help generate smoke test regress clean clean-generated

help:
	@echo "make generate TEST=<name>  Assemble a test and generate golden files"
	@echo "make smoke                 Test build/TB wiring with a mock DUT"
	@echo "make test TEST=<name>      Generate and run one RTL test"
	@echo "make regress               Run every test, print PASS/FAIL summary (logs in tests/<name>/sim.log)"
	@echo "make clean                 Remove generated test and simulator files"
	@echo "Available tests: $(TEST_NAMES)"

generate:
	@test -f "$(TEST_DIR)/program.asm" || { echo "Unknown test: $(TEST)"; exit 2; }
	$(PYTHON) scripts/build_test.py "$(TEST_DIR)"

smoke:
	$(MAKE) --no-print-directory generate TEST=ebreak
	$(MAKE) -C sim/behav xrun INCLUDE_FILE_NAME=processor_mock.include SIM_PLUSARGS="+PROGRAM=$(abspath tests/ebreak/program.hex) +PROGRAM_WORDS=$$(wc -l < tests/ebreak/program.hex) +DATA=$(abspath tests/ebreak/data.hex) +DATA_WORDS=$$(wc -l < tests/ebreak/data.hex) +EXPECTED_REGS=$(abspath tests/ebreak/expected_regs.hex) +EXPECTED_DATA=$(abspath tests/ebreak/expected_data.hex) +EXPECTED_DATA_WORDS=$$(wc -l < tests/ebreak/expected_data.hex) +MAX_CPU_CYCLES=20 +CROSSBAR_TIMEOUT=5"

test: generate
	$(MAKE) -C sim/behav xrun SIM_PLUSARGS="+PROGRAM=$(abspath $(TEST_DIR)/program.hex) +PROGRAM_WORDS=$$(wc -l < $(TEST_DIR)/program.hex) +DATA=$(abspath $(TEST_DIR)/data.hex) +DATA_WORDS=$$(wc -l < $(TEST_DIR)/data.hex) +EXPECTED_REGS=$(abspath $(TEST_DIR)/expected_regs.hex) +EXPECTED_DATA=$(abspath $(TEST_DIR)/expected_data.hex) +EXPECTED_DATA_WORDS=$$(wc -l < $(TEST_DIR)/expected_data.hex) +MAX_CPU_CYCLES=$(MAX_CPU_CYCLES) +CROSSBAR_TIMEOUT=$(CROSSBAR_TIMEOUT)"

regress:
	@pass=0; fail=0; failed_tests=""; \
	for test_name in $(TEST_NAMES); do \
		log="tests/$$test_name/sim.log"; \
		if $(MAKE) --no-print-directory test TEST=$$test_name > "$$log" 2>&1; then \
			echo "PASS  $$test_name"; \
			pass=$$((pass + 1)); \
		else \
			echo "FAIL  $$test_name  (log: $$log)"; \
			mismatches=$$(grep -E '^FAIL: (register|data word)' "$$log"); \
			if [ -n "$$mismatches" ]; then \
				echo "$$mismatches" | sed 's/^/         /'; \
			else \
				echo "         (no register/data mismatch - build or tool error, see log)"; \
			fi; \
			fail=$$((fail + 1)); \
			failed_tests="$$failed_tests $$test_name"; \
		fi; \
	done; \
	echo "----------------------------------------"; \
	echo "$$pass passed, $$fail failed (of $$((pass + fail)))"; \
	if [ $$fail -ne 0 ]; then \
		echo "Failed:$$failed_tests"; \
		echo "Re-run one with 'make test TEST=<name>' for the full log + waveform."; \
		exit 1; \
	fi

clean:
	$(MAKE) -C sim/behav clean
	$(MAKE) --no-print-directory clean-generated

clean-generated:
	find tests -type f \( -name 'program.o' -o -name 'program.hex' -o -name 'sim.log' \) -delete
