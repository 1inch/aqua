# SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
# Makefile for deploying and managing AquaRouter contracts
#
# Conditionally include .env or .env.automation based on OPS_LAUNCH_MODE
ifeq ($(OPS_LAUNCH_MODE),auto)
-include .env.automation
else
-include .env
endif
export

CURRENT_DIR:=$(shell pwd)

OPS_NETWORK := $(subst ",,$(OPS_NETWORK))
OPS_CHAIN_ID := $(subst ",,$(OPS_CHAIN_ID))

PREFIX:=$(shell echo "$(OPS_NETWORK)" | sed -r 's/([a-z0-9])([A-Z])/\1_\2/g' | tr '[:lower:]' '[:upper:]')
REGOP_ENV_RPC_URL:=$(PREFIX)_RPC_URL
REGOP_ENV_PK:=$(PREFIX)_PRIVATE_KEY

RPC_URL=$(shell echo "$${!REGOP_ENV_RPC_URL}" | tr -d '"')
PRIVATE_KEY=$(shell echo "$${!REGOP_ENV_PK}" | tr -d '"')

COMPILER_VERSION:=$(shell grep -oP "version:\s*\"\K[^\"]*" hardhat.config.ts | head -1)

deploy-aqua-router:
	@$(MAKE) FILE_DEPLOY_NAME=AquaRouter validate-aqua-router deploy-aqua-router-impl save-deployments

deploy-aqua-router-impl:
	@{ \
	    $(MAKE) ID=FILE_DEPLOY_NAME validate || exit 1; \
        forge script $(CURRENT_DIR)/script/Deploy$${FILE_DEPLOY_NAME}.s.sol:Deploy$${FILE_DEPLOY_NAME} \
            --rpc-url $(RPC_URL) \
            --private-key $(PRIVATE_KEY) \
            --broadcast -vvvv; \
	}

verify-aqua-router:
	@$(MAKE) FILE_DEPLOY_NAME=AquaRouter validate-aqua-router verify-aqua-router-impl

verify-aqua-router-impl:
	@{ \
	    $(MAKE) ID=FILE_DEPLOY_NAME validate || exit 1; \
	    DEPLOYMENT_FILE="$(CURRENT_DIR)/deployments/$(OPS_NETWORK)/$${FILE_DEPLOY_NAME}.json"; \
	    if [ ! -f $$DEPLOYMENT_FILE ]; then \
	        echo "Deployment file $$DEPLOYMENT_FILE does not exist! Deploy first."; \
	        exit 1; \
	    fi; \
	    CONTRACT_ADDRESS=$$($(MAKE) contract-address DEPLOYMENT_FILE=$$DEPLOYMENT_FILE); \
	    echo "Verifying $${FILE_DEPLOY_NAME} at $$CONTRACT_ADDRESS on $(OPS_NETWORK)..."; \
	    forge verify-contract $$CONTRACT_ADDRESS \
	        src/$${FILE_DEPLOY_NAME}.sol:$${FILE_DEPLOY_NAME} \
            --skip-is-verified-check \
            --rpc-url $(RPC_URL) \
	        --chain-id $(OPS_CHAIN_ID) \
	        --watch \
	        --compiler-version $(COMPILER_VERSION); \
	}

# Helper targets
save-deployments:
	@{ \
		$(MAKE) ID=FILE_DEPLOY_NAME validate || exit 1; \
		DEPLOYMENT_FILE="$(CURRENT_DIR)/broadcast/Deploy$${FILE_DEPLOY_NAME}.s.sol/$(OPS_CHAIN_ID)/run-latest.json"; \
		DIRECTORY="$(CURRENT_DIR)/deployments/$(OPS_NETWORK)"; \
		mkdir -p $$DIRECTORY; \
		if [ -f $$DEPLOYMENT_FILE ]; then \
			cp -f $$DEPLOYMENT_FILE "$${DIRECTORY}/$${FILE_DEPLOY_NAME}.json"; \
		else \
			echo "Deployment file $$DEPLOYMENT_FILE does not exist!"; \
			exit 1; \
		fi; \
	}

contract-address:
	@{ \
		$(MAKE) ID=DEPLOYMENT_FILE validate || exit 1; \
		echo $$(jq -r '.transactions[0].contractAddress' $(DEPLOYMENT_FILE)); \
	}

# Validation targets
validate-aqua-router:
		@{ \
		$(MAKE) ID=OPS_NETWORK validate || exit 1; \
		$(MAKE) ID=OPS_CHAIN_ID validate || exit 1; \
		}

validate:
		@{ \
			VALUE=$$(echo "$${!ID}" | tr -d '"'); \
			if [ -z "$${VALUE}" ]; then \
				echo "$${ID} is not set (Value: '$${VALUE}')!"; \
				exit 1; \
			fi; \
		}

# Get deployed contract addresses from deployment files
get:
		@{ \
		$(MAKE) ID=PARAMETER validate || exit 1; \
		$(MAKE) ID=OPS_NETWORK validate || exit 1; \
		if [ ! -d "$(CURRENT_DIR)/deployments/$(OPS_NETWORK)" ]; then \
			echo "Error: Directory $(CURRENT_DIR)/deployments/$(OPS_NETWORK) does not exist"; \
			exit 1; \
		fi; \
		CONTRACT_FILE=""; \
		contracts_list=$$(ls $(CURRENT_DIR)/deployments/$(OPS_NETWORK)/*.json | xargs -n1 basename | sed 's/\.json$$//'); \
		found=0; \
		for contract in $$contracts_list; do \
			contract_upper=$$(echo $$contract | sed 's/\([A-Z][a-z]\)/_\1/g' | sed 's/^_//' | tr 'a-z' 'A-Z'); \
			if [ "$(PARAMETER)" = "OPS_$${contract_upper}_ADDRESS" ]; then \
				CONTRACT_FILE="$${contract}.json"; \
				found=1; \
				break; \
			fi; \
		done; \
		if [ "$$found" -eq 0 ]; then \
			echo "Error: Unknown parameter $(PARAMETER)"; exit 1; \
		fi; \
		DEPLOYMENT_FILE="$(CURRENT_DIR)/deployments/$(OPS_NETWORK)/$$CONTRACT_FILE"; \
		if [ ! -f "$$DEPLOYMENT_FILE" ]; then \
			echo "Error: Deployment file $$DEPLOYMENT_FILE not found"; \
			exit 1; \
		fi; \
		ADDRESS=$$($(MAKE) contract-address DEPLOYMENT_FILE=$$DEPLOYMENT_FILE); \
		echo "$$ADDRESS"; \
		}

get-outputs:
		@{ \
		$(MAKE) ID=OPS_NETWORK validate || exit 1; \
		if [ ! -d "$(CURRENT_DIR)/deployments/$(OPS_NETWORK)" ]; then \
			echo "Error: Directory $(CURRENT_DIR)/deployments/$(OPS_NETWORK) does not exist"; \
			exit 1; \
		fi; \
		result="{"; \
		first=1; \
		for file in $(CURRENT_DIR)/deployments/$(OPS_NETWORK)/*.json; do \
			filename=$$(basename $$file .json); \
			key="OPS_$$(echo $$filename | sed 's/\([A-Z][a-z]\)/_\1/g' | sed 's/^_//' | tr 'a-z' 'A-Z')_ADDRESS"; \
			if [ $$first -eq 1 ]; then \
				result="$$result\"$$key\": \"$$key\""; \
				first=0; \
			else \
				result="$$result, \"$$key\": \"$$key\""; \
			fi; \
		done; \
		result="$$result}"; \
		echo "$$result"; \
		}

update:; forge update

build:; forge build

tests :; forge test -vvv --gas-report

coverage :; mkdir -p coverage && forge coverage --report summary --ir-minimum --report-file coverage/lcov.info

snapshot :; forge snapshot --no-match-test "testFuzz_*"

snapshot-check :; forge snapshot --check --no-match-test "testFuzz_*"

format :; forge fmt

clean :; forge clean

lint :; forge fmt --check

anvil :;  anvil --fork-url $(NODE_URL) --steps-tracing --chain-id $(OPS_CHAIN_ID) --host 127.0.0.1 --port 8546 -vvvvv

balance :; cast balance $(ADDRESS) --rpc-url $(RPC_URL) | cast from-wei

balance-erc20 :; cast call $(TOKEN) "balanceOf(address)(uint256)" $(ADDRESS) --rpc-url $(RPC_URL) | cast from-wei

help:
		@echo "Available targets:"
		@grep -E '^[a-zA-Z0-9_.-]+:' $(CURRENT_DIR)/Makefile | grep -v '^\.' | awk -F: '{print "  " $$1}' | sort -u

.PHONY: deploy-aqua-router deploy-aqua-router-impl verify-aqua-router verify-aqua-router-impl save-deployments contract-address validate-aqua-router validate \
        get get-outputs update build tests coverage snapshot snapshot-check format clean lint anvil balance balance-erc20 help
