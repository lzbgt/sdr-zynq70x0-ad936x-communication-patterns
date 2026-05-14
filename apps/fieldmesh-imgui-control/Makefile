APP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(APP_DIR)/../..)
SDK_DIR := $(REPO_ROOT)/sdk/c

BUILD_DIR ?= $(REPO_ROOT)/.config/fieldmesh/imgui-control-build
OUT_DIR ?= $(REPO_ROOT)/.config/fieldmesh/imgui-control-check

CC ?= cc
CXX ?= c++
CFLAGS ?= -std=c99 -Wall -Wextra -Werror
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror
CPPFLAGS ?= -I$(SDK_DIR)/include

HEADLESS_APP := $(BUILD_DIR)/fieldmesh-imgui-control-headless
GUI_APP := $(BUILD_DIR)/fieldmesh-imgui-control
SDK_OBJ := $(BUILD_DIR)/fieldmesh_sdk.o

.ONESHELL:
.PHONY: all check clean gui

all: $(HEADLESS_APP)

$(BUILD_DIR):
	mkdir -p "$@"

$(SDK_OBJ): $(SDK_DIR)/src/fieldmesh_sdk.c $(SDK_DIR)/include/fieldmesh_sdk.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) -c "$<" -o "$@"

$(HEADLESS_APP): fieldmesh_imgui_control_app.cpp $(SDK_OBJ) $(SDK_DIR)/include/fieldmesh_sdk.h | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) "$<" "$(SDK_OBJ)" -o "$@"

gui: fieldmesh_imgui_control_app.cpp $(SDK_OBJ) | $(BUILD_DIR)
	@test -n "$(IMGUI_DIR)" || { echo "Set IMGUI_DIR=/path/to/dear-imgui"; exit 2; }
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -DFIELDMESH_WITH_IMGUI=1 \
		-I"$(IMGUI_DIR)" \
		"$<" "$(SDK_OBJ)" \
		"$(IMGUI_DIR)/imgui.cpp" \
		"$(IMGUI_DIR)/imgui_draw.cpp" \
		"$(IMGUI_DIR)/imgui_tables.cpp" \
		"$(IMGUI_DIR)/imgui_widgets.cpp" \
		-o "$(GUI_APP)"

check: $(HEADLESS_APP)
	mkdir -p "$(OUT_DIR)"
	python3 -m py_compile \
		fieldmesh_imgui_check.py \
		fieldmesh_imgui_pyapi.py \
		fieldmesh_imgui_pyapi_check.py
	"$(HEADLESS_APP)" --self-test \
		--snapshot-output "$(OUT_DIR)/imgui_control_snapshot.json"
	./fieldmesh_imgui_check.py \
		fieldmesh_imgui_control_app.cpp \
		"$(OUT_DIR)/imgui_control_snapshot.json"
	PYTHONPATH="$$(pwd)" ./fieldmesh_imgui_pyapi_check.py "$(HEADLESS_APP)"

clean:
	rm -rf "$(BUILD_DIR)" "$(OUT_DIR)"
