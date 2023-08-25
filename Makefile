ifndef MIX_APP_PATH
	MIX_APP_PATH=$(shell pwd)
endif

PRIV_DIR = $(MIX_APP_PATH)/priv
NIF_SO = $(PRIV_DIR)/nif.so
SRC_ROOT = $(shell pwd)
C_SRC = $(SRC_ROOT)/c_src

CFLAGS += -std=c++20 -shared -O3 -fPIC -I"$(ERTS_INCLUDE_DIR)"
UNAME_S := $(shell uname -s)
ifndef TARGET_ABI
ifeq ($(UNAME_S),Darwin)
	TARGET_ABI = darwin
endif
endif

ifeq ($(TARGET_ABI),darwin)
	CFLAGS += -undefined dynamic_lookup -flat_namespace -undefined suppress
endif

.DEFAULT_GLOBAL := build

build: $(NIF_SO)
	@ echo > /dev/null

priv_dir:
	@ if [ ! -e "$(PRIV_DIR)" ]; then \
		mkdir -p "$(PRIV_DIR)" ; \
	fi

$(NIF_SO): priv_dir $(C_SRC)/nif_utils.hpp $(C_SRC)/nif_utils.cpp $(C_SRC)/mem_table.hpp $(C_SRC)/mem_table.cpp $(C_SRC)/wal.hpp $(C_SRC)/wal.cpp $(C_SRC)/index.hpp $(C_SRC)/index.cpp $(C_SRC)/elasticlunr.cpp
	$(CC) $(CFLAGS) $(C_SRC)/nif_utils.cpp $(C_SRC)/mem_table.cpp $(C_SRC)/wal.cpp $(C_SRC)/index.cpp $(C_SRC)/elasticlunr.cpp -o $(NIF_SO)
