SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

.DEFAULT:
	@echo "Something went wrong, check $@ file/target is present"
	@exit 1

.PHONY: help
help:
	@echo "Provide a target, type in the command prompt: \
	make <space> <tab> <tab> to see all targets"

.PHONY: nvim-helptags-generate
nvim-helptags-generate:
	nvim --headless -u NONE -c 'helptags doc' -c 'qa!'

.PHONY: nvim-test-unit
nvim-test-unit:
	nvim --clean --headless -u NONE -S test/unit.vim
