APP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(APP_DIR)/../..)
SDK_DIR := $(REPO_ROOT)/sdk/c

BUILD_DIR ?= $(REPO_ROOT)/.config/fieldmesh/control-camera-build
OUT_DIR ?= $(REPO_ROOT)/.config/fieldmesh/control-camera-check

CC ?= cc
CXX ?= c++
CFLAGS ?= -std=c99 -Wall -Wextra -Werror
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Werror
CPPFLAGS ?= -I$(SDK_DIR)/include

APP := $(BUILD_DIR)/fieldmesh-control-camera-demo
DAEMON := $(BUILD_DIR)/fieldmesh-state-daemon-demo
SDK_OBJ := $(BUILD_DIR)/fieldmesh_sdk.o
FRAME_INPUT := $(REPO_ROOT)/resources/fieldmesh/vectors/frame_001.bin

.PHONY: all check clean

all: $(APP) $(DAEMON)

$(BUILD_DIR):
	mkdir -p "$@"

$(SDK_OBJ): $(SDK_DIR)/src/fieldmesh_sdk.c $(SDK_DIR)/include/fieldmesh_sdk.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) -c "$<" -o "$@"

$(APP): fieldmesh_control_camera_demo.cpp $(SDK_OBJ) $(SDK_DIR)/include/fieldmesh_sdk.h | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(CPPFLAGS) "$<" "$(SDK_OBJ)" -o "$@"

$(DAEMON): $(SDK_DIR)/examples/fieldmesh_state_daemon_demo.c $(SDK_OBJ) $(SDK_DIR)/include/fieldmesh_sdk.h | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(CPPFLAGS) "$<" "$(SDK_OBJ)" -o "$@"

check: $(APP) $(DAEMON)
	mkdir -p "$(OUT_DIR)"
	python3 -m py_compile fieldmesh_camera_pipe.py fieldmesh_app_snapshot.py
	cp "$(FRAME_INPUT)" "$(OUT_DIR)/camera_input.bin"
	"$(APP)" \
		--camera-input "$(OUT_DIR)/camera_input.bin" \
		--preview-output "$(OUT_DIR)/camera_preview.bin" \
		--snapshot-output "$(OUT_DIR)/camera_snapshot.json" \
		--dashboard-output "$(OUT_DIR)/camera_dashboard.html" \
		--chunk-size 64 \
		>"$(OUT_DIR)/camera_app.ndjson" \
		2>"$(OUT_DIR)/camera_app.stderr"
	"$(APP)" \
		--camera-input "$(OUT_DIR)/camera_input.bin" \
		--preview-output "$(OUT_DIR)/explicit_camera_preview.bin" \
		--snapshot-output "$(OUT_DIR)/explicit_camera_snapshot.json" \
		--dashboard-output "$(OUT_DIR)/explicit_camera_dashboard.html" \
		--chunk-size 64 \
		--preferred-ap-eui 020000000103 \
		--dst-eui 020000000203 \
		>"$(OUT_DIR)/explicit_camera_app.ndjson" \
		2>"$(OUT_DIR)/explicit_camera_app.stderr"
	daemon_pid=; \
	"$(DAEMON)" serve 127.0.0.1 55431 4 5000 \
		>"$(OUT_DIR)/daemon_camera_server.ndjson" \
		2>"$(OUT_DIR)/daemon_camera_server.stderr" & \
	daemon_pid="$$!"; \
	sleep 0.2; \
	if "$(APP)" \
		--camera-input "$(OUT_DIR)/camera_input.bin" \
		--preview-output "$(OUT_DIR)/daemon_camera_preview.bin" \
		--snapshot-output "$(OUT_DIR)/daemon_camera_snapshot.json" \
		--dashboard-output "$(OUT_DIR)/daemon_camera_dashboard.html" \
		--chunk-size 64 \
		--max-chunks 3 \
		--preferred-ap-eui 020000000103 \
		--dst-eui 020000000203 \
		--daemon-host 127.0.0.1 \
		--daemon-port 55431 \
		>"$(OUT_DIR)/daemon_camera_app.ndjson" \
		2>"$(OUT_DIR)/daemon_camera_app.stderr"; then \
		app_rc=0; \
	else \
		app_rc="$$?"; \
	fi; \
	if wait "$$daemon_pid"; then \
		daemon_rc=0; \
	else \
		daemon_rc="$$?"; \
	fi; \
	test "$$app_rc" -eq 0; \
	test "$$daemon_rc" -eq 0
	./fieldmesh_app_snapshot.py \
		--input "$(OUT_DIR)/camera_app.ndjson" \
		--output "$(OUT_DIR)/camera_replayed_snapshot.json"
	./fieldmesh_camera_pipe.py preset \
		--platform linux \
		--backend ffmpeg \
		--device /dev/video0 \
		>"$(OUT_DIR)/camera_preset.json"

clean:
	rm -rf "$(BUILD_DIR)" "$(OUT_DIR)"
