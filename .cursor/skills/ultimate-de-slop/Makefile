.PHONY: test syntax ci install-codex

test:
	python3 -m unittest discover -s tests -v

syntax:
	python3 -m compileall scripts tests
	bash -n scripts/*.sh scripts/install/*.sh

ci: syntax test

install-codex:
	scripts/install/install-codex.sh
