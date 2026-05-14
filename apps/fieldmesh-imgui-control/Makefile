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
PY_EMBED_OBJ := $(BUILD_DIR)/fieldmesh_imgui_embedded_python.o
TEST_PROFILE := $(APP_DIR)/testdata/golden_lab.profile

.ONESHELL:
.PHONY: all check clean gui gui-python

all: $(HEADLESS_APP)

$(BUILD_DIR):
	mkdir -p "$@"

$(SDK_OBJ): $(SDK_DIR)/src/fieldmesh_sdk.c $(SDK_DIR)/include/fieldmesh_sdk.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) -c "$<" -o "$@"

$(PY_EMBED_OBJ): fieldmesh_imgui_embedded_python.cpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -c "$<" -o "$@"

$(HEADLESS_APP): fieldmesh_imgui_control_app.cpp fieldmesh_imgui_embedded_resources.h $(SDK_OBJ) $(PY_EMBED_OBJ) $(SDK_DIR)/include/fieldmesh_sdk.h | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) "$<" "$(SDK_OBJ)" "$(PY_EMBED_OBJ)" -o "$@"

gui: fieldmesh_imgui_control_app.cpp fieldmesh_imgui_embedded_resources.h $(SDK_OBJ) $(PY_EMBED_OBJ) | $(BUILD_DIR)
	@test -n "$(IMGUI_DIR)" || { echo "Set IMGUI_DIR=/path/to/dear-imgui"; exit 2; }
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -DFIELDMESH_WITH_IMGUI=1 \
		-I"$(IMGUI_DIR)" \
		"$<" "$(SDK_OBJ)" "$(PY_EMBED_OBJ)" \
		"$(IMGUI_DIR)/imgui.cpp" \
		"$(IMGUI_DIR)/imgui_draw.cpp" \
		"$(IMGUI_DIR)/imgui_tables.cpp" \
		"$(IMGUI_DIR)/imgui_widgets.cpp" \
		-o "$(GUI_APP)"

gui-python: fieldmesh_imgui_control_app.cpp fieldmesh_imgui_embedded_resources.h $(SDK_OBJ) | $(BUILD_DIR)
	@test -n "$(IMGUI_DIR)" || { echo "Set IMGUI_DIR=/path/to/dear-imgui"; exit 2; }
	python3-config --embed --cflags >/dev/null
	python3-config --embed --ldflags >/dev/null
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -DFIELDMESH_WITH_EMBEDDED_PYTHON=1 \
		$$(python3-config --embed --cflags) \
		-c fieldmesh_imgui_embedded_python.cpp \
		-o "$(BUILD_DIR)/fieldmesh_imgui_embedded_python_embed.o"
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) -DFIELDMESH_WITH_IMGUI=1 \
		-I"$(IMGUI_DIR)" \
		"$<" "$(SDK_OBJ)" "$(BUILD_DIR)/fieldmesh_imgui_embedded_python_embed.o" \
		"$(IMGUI_DIR)/imgui.cpp" \
		"$(IMGUI_DIR)/imgui_draw.cpp" \
		"$(IMGUI_DIR)/imgui_tables.cpp" \
		"$(IMGUI_DIR)/imgui_widgets.cpp" \
		$$(python3-config --embed --ldflags) \
		-o "$(GUI_APP)"

check: $(HEADLESS_APP)
	mkdir -p "$(OUT_DIR)"
	python3 -m py_compile \
		fieldmesh_imgui_check.py \
		fieldmesh_imgui_pyapi.py \
		fieldmesh_imgui_pyapi_check.py
	"$(HEADLESS_APP)" --self-test \
		--profile "$(TEST_PROFILE)" \
		--snapshot-output "$(OUT_DIR)/imgui_control_snapshot.json"
	./fieldmesh_imgui_check.py \
		fieldmesh_imgui_control_app.cpp \
		fieldmesh_imgui_embedded_resources.h \
		fieldmesh_imgui_embedded_python.cpp \
		"$(OUT_DIR)/imgui_control_snapshot.json"
	PYTHONPATH="$$(pwd)" ./fieldmesh_imgui_pyapi_check.py "$(HEADLESS_APP)" "$(TEST_PROFILE)"

clean:
	rm -rf "$(BUILD_DIR)" "$(OUT_DIR)"
