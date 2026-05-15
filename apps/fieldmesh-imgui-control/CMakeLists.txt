cmake_minimum_required(VERSION 3.20)

project(fieldmesh_imgui_control LANGUAGES C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(FIELDMESH_IMGUI_BUILD_GLFW "Build the visible GLFW/OpenGL Dear ImGui app" OFF)
option(FIELDMESH_IMGUI_EMBED_PYTHON "Embed the in-process fieldmesh_imgui Python module" OFF)

set(FIELDMESH_REPO_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../.."
    CACHE PATH "FieldMesh repository root")
set(IMGUI_DIR "" CACHE PATH "Dear ImGui checkout with imgui.cpp and backends/")

set(FIELDMESH_SDK_INCLUDE "${FIELDMESH_REPO_ROOT}/sdk/c/include")
set(FIELDMESH_SDK_SOURCE "${FIELDMESH_REPO_ROOT}/sdk/c/src/fieldmesh_sdk.c")
set(FIELDMESH_APP_PYTHON_SOURCE "${CMAKE_CURRENT_LIST_DIR}/fieldmesh_imgui_embedded_python.cpp")

function(fieldmesh_apply_common target)
    target_include_directories("${target}" PRIVATE "${FIELDMESH_SDK_INCLUDE}")
    if(FIELDMESH_IMGUI_EMBED_PYTHON)
        target_compile_definitions("${target}" PRIVATE FIELDMESH_WITH_EMBEDDED_PYTHON=1)
        target_link_libraries("${target}" PRIVATE Python3::Python)
    endif()
    if(MSVC)
        target_compile_options("${target}" PRIVATE /W4 /WX /permissive-)
        target_compile_definitions("${target}" PRIVATE _CRT_SECURE_NO_WARNINGS=1)
    else()
        target_compile_options("${target}" PRIVATE -Wall -Wextra -Werror)
    endif()
endfunction()

if(FIELDMESH_IMGUI_EMBED_PYTHON)
    find_package(Python3 REQUIRED COMPONENTS Development.Embed)
endif()

add_executable(fieldmesh-imgui-control-headless
    fieldmesh_imgui_control_app.cpp
    "${FIELDMESH_APP_PYTHON_SOURCE}"
    "${FIELDMESH_SDK_SOURCE}")
fieldmesh_apply_common(fieldmesh-imgui-control-headless)

if(FIELDMESH_IMGUI_BUILD_GLFW)
    if(NOT EXISTS "${IMGUI_DIR}/imgui.cpp")
        message(FATAL_ERROR
            "Set IMGUI_DIR to a Dear ImGui checkout before enabling "
            "FIELDMESH_IMGUI_BUILD_GLFW")
    endif()
    if(NOT EXISTS "${IMGUI_DIR}/backends/imgui_impl_glfw.cpp")
        message(FATAL_ERROR
            "IMGUI_DIR must include Dear ImGui backends/imgui_impl_glfw.cpp")
    endif()

    find_package(OpenGL REQUIRED)
    find_package(glfw3 CONFIG QUIET)
    if(NOT glfw3_FOUND)
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            pkg_check_modules(GLFW3 QUIET glfw3)
        endif()
    endif()
    if(NOT glfw3_FOUND AND NOT GLFW3_FOUND)
        message(FATAL_ERROR
            "GLFW3 was not found. On Windows, install glfw3 through vcpkg "
            "and pass CMAKE_TOOLCHAIN_FILE; on Linux install glfw.")
    endif()

    add_executable(fieldmesh-imgui-control-glfw
        fieldmesh_imgui_glfw_main.cpp
        "${FIELDMESH_APP_PYTHON_SOURCE}"
        "${FIELDMESH_SDK_SOURCE}"
        "${IMGUI_DIR}/imgui.cpp"
        "${IMGUI_DIR}/imgui_draw.cpp"
        "${IMGUI_DIR}/imgui_tables.cpp"
        "${IMGUI_DIR}/imgui_widgets.cpp"
        "${IMGUI_DIR}/backends/imgui_impl_glfw.cpp"
        "${IMGUI_DIR}/backends/imgui_impl_opengl3.cpp")
    fieldmesh_apply_common(fieldmesh-imgui-control-glfw)
    target_compile_definitions(fieldmesh-imgui-control-glfw PRIVATE FIELDMESH_WITH_IMGUI=1)
    target_include_directories(fieldmesh-imgui-control-glfw PRIVATE
        "${IMGUI_DIR}"
        "${IMGUI_DIR}/backends")
    target_link_libraries(fieldmesh-imgui-control-glfw PRIVATE OpenGL::GL)
    if(TARGET glfw)
        target_link_libraries(fieldmesh-imgui-control-glfw PRIVATE glfw)
    elseif(TARGET glfw3)
        target_link_libraries(fieldmesh-imgui-control-glfw PRIVATE glfw3)
    elseif(GLFW3_FOUND)
        target_include_directories(fieldmesh-imgui-control-glfw PRIVATE ${GLFW3_INCLUDE_DIRS})
        target_link_directories(fieldmesh-imgui-control-glfw PRIVATE ${GLFW3_LIBRARY_DIRS})
        target_link_libraries(fieldmesh-imgui-control-glfw PRIVATE ${GLFW3_LIBRARIES})
    endif()
    if(UNIX AND NOT APPLE)
        target_link_libraries(fieldmesh-imgui-control-glfw PRIVATE dl)
    endif()
endif()
