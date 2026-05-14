#define FIELDMESH_WITH_IMGUI 1
#define FIELDMESH_IMGUI_NO_MAIN 1

#include "fieldmesh_imgui_control_app.cpp"

#include "backends/imgui_impl_glfw.h"
#include "backends/imgui_impl_opengl3.h"

#include <GLFW/glfw3.h>

#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <string>

#ifdef FIELDMESH_WITH_EMBEDDED_PYTHON
extern "C" bool fieldmesh_imgui_start_embedded_python(void);
#endif

namespace {

void glfw_error_callback(int error, const char *description)
{
    std::fprintf(stderr, "GLFW error %d: %s\n", error, description);
}

void apply_action_args(GuiState *state, int argc, char **argv)
{
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--api-browse") == 0) {
            (void)api_browse_peers(state);
        } else if (std::strcmp(argv[i], "--api-select-board") == 0 && i + 1 < argc) {
            (void)api_select_board(state, argv[++i]);
        } else if (std::strcmp(argv[i], "--api-elect-ap") == 0 && i + 1 < argc) {
            (void)api_elect_ap(state, argv[++i]);
        } else if (std::strcmp(argv[i], "--api-open-chat") == 0 && i + 1 < argc) {
            (void)api_open_conversation(state, argv[++i]);
        } else if (std::strcmp(argv[i], "--api-send-message") == 0 && i + 1 < argc) {
            (void)api_send_message(state, argv[++i]);
        } else if (std::strcmp(argv[i], "--api-publish-camera") == 0 && i + 1 < argc) {
            (void)api_publish_camera(state, argv[++i]);
        } else if (std::strcmp(argv[i], "--api-subscribe-camera") == 0 && i + 1 < argc) {
            (void)api_subscribe_camera(state, argv[++i]);
        } else if (std::strcmp(argv[i], "--api-run-python") == 0) {
            (void)run_python_automation(state);
        } else if (std::strcmp(argv[i], "--publish") == 0) {
            state->camera.publish_enabled = true;
        } else if (std::strcmp(argv[i], "--preview") == 0) {
            state->camera.preview_enabled = true;
        }
    }
}

}  // namespace

int main(int argc, char **argv)
{
    GuiState state;
    const char *profile = nullptr;
    const char *snapshot_output = nullptr;
    const char *discover_candidates = nullptr;
    const char *instance = "FieldMesh IM";
    bool smoke_frame = false;
    bool profile_loaded = false;

    populate_demo_state(&state);
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--profile") == 0 && i + 1 < argc) {
            profile = argv[++i];
        } else if (std::strcmp(argv[i], "--snapshot-output") == 0 && i + 1 < argc) {
            snapshot_output = argv[++i];
        } else if (std::strcmp(argv[i], "--discover-candidates") == 0 && i + 1 < argc) {
            discover_candidates = argv[++i];
        } else if (std::strcmp(argv[i], "--instance") == 0 && i + 1 < argc) {
            instance = argv[++i];
        } else if (std::strcmp(argv[i], "--smoke-frame") == 0) {
            smoke_frame = true;
        } else if (std::strcmp(argv[i], "--help") == 0 ||
                   std::strcmp(argv[i], "-h") == 0) {
            std::printf("Usage: %s [--profile PATH] [--instance NAME] "
                        "[--smoke-frame] [--snapshot-output PATH] "
                        "[app action flags]\n", argv[0]);
            return 0;
        }
    }
    if (profile && !load_runtime_profile(&state, profile)) {
        return 1;
    }
    profile_loaded = profile != nullptr;
    if (!profile_loaded) {
        const char *env_candidates = std::getenv("FIELDMESH_DISCOVERY_CANDIDATES");
        (void)discover_runtime_boards(&state,
                                      discover_candidates ? discover_candidates :
                                      env_candidates);
    }
    apply_action_args(&state, argc, argv);
#ifdef FIELDMESH_WITH_EMBEDDED_PYTHON
    if (!fieldmesh_imgui_start_embedded_python()) {
        std::fprintf(stderr, "failed to initialize embedded Python API\n");
        return 1;
    }
#endif

    glfwSetErrorCallback(glfw_error_callback);
    if (!glfwInit()) {
        std::fprintf(stderr, "failed to initialize GLFW\n");
        return 1;
    }

    const char *glsl_version = "#version 130";
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);

    GLFWwindow *window = glfwCreateWindow(1280, 820, instance, nullptr, nullptr);
    if (!window) {
        std::fprintf(stderr, "failed to create GLFW window\n");
        glfwTerminate();
        return 1;
    }
    glfwMakeContextCurrent(window);
    glfwSwapInterval(1);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.IniFilename = nullptr;
    io.LogFilename = nullptr;
    ImGui::StyleColorsLight();

    if (!ImGui_ImplGlfw_InitForOpenGL(window, true)) {
        std::fprintf(stderr, "failed to initialize ImGui GLFW backend\n");
        ImGui::DestroyContext();
        glfwDestroyWindow(window);
        glfwTerminate();
        return 1;
    }
    if (!ImGui_ImplOpenGL3_Init(glsl_version)) {
        std::fprintf(stderr, "failed to initialize ImGui OpenGL3 backend\n");
        ImGui_ImplGlfw_Shutdown();
        ImGui::DestroyContext();
        glfwDestroyWindow(window);
        glfwTerminate();
        return 1;
    }

    do {
        glfwPollEvents();
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();

        fieldmesh_imgui_render(&state);

        ImGui::Render();
        int display_w = 0;
        int display_h = 0;
        glfwGetFramebufferSize(window, &display_w, &display_h);
        glViewport(0, 0, display_w, display_h);
        glClearColor(0.95f, 0.97f, 0.98f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
        glfwSwapBuffers(window);
    } while (!glfwWindowShouldClose(window) && !smoke_frame);

    (void)poll_message_bus(&state);
    if (snapshot_output && !write_snapshot(state, snapshot_output)) {
        ImGui_ImplOpenGL3_Shutdown();
        ImGui_ImplGlfw_Shutdown();
        ImGui::DestroyContext();
        glfwDestroyWindow(window);
        glfwTerminate();
        return 1;
    }

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}
