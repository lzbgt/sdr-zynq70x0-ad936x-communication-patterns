param(
    [string]$RepoRoot = "",
    [string]$ImguiDir = "",
    [string]$BuildDir = "",
    [string]$Config = "Release",
    [string]$Generator = "Visual Studio 17 2022",
    [string]$Platform = "x64",
    [string]$VcpkgToolchain = "",
    [switch]$HeadlessOnly,
    [switch]$NoPython
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
if ([string]::IsNullOrWhiteSpace($ImguiDir)) {
    $ImguiDir = Join-Path $RepoRoot ".config\third_party\imgui"
}
if ([string]::IsNullOrWhiteSpace($BuildDir)) {
    $BuildDir = Join-Path $RepoRoot ".config\fieldmesh\imgui-control-windows"
}

$AppDir = Join-Path $RepoRoot "apps\fieldmesh-imgui-control"
$BuildGlfw = if ($HeadlessOnly) { "OFF" } else { "ON" }
$EmbedPython = if ($NoPython) { "OFF" } else { "ON" }
$Target = if ($HeadlessOnly) { "fieldmesh-imgui-control-headless" } else { "fieldmesh-imgui-control-glfw" }

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw "cmake.exe was not found in PATH. Open a Visual Studio Developer PowerShell or install CMake."
}
if (($BuildGlfw -eq "ON") -and -not (Test-Path (Join-Path $ImguiDir "imgui.cpp"))) {
    throw "Dear ImGui checkout not found at '$ImguiDir'. Pass -ImguiDir C:\path\to\imgui."
}

$ConfigureArgs = @(
    "-S", $AppDir,
    "-B", $BuildDir,
    "-G", $Generator,
    "-A", $Platform,
    "-DFIELDMESH_IMGUI_BUILD_GLFW=$BuildGlfw",
    "-DFIELDMESH_IMGUI_EMBED_PYTHON=$EmbedPython",
    "-DIMGUI_DIR=$ImguiDir"
)
if (-not [string]::IsNullOrWhiteSpace($VcpkgToolchain)) {
    $ConfigureArgs += "-DCMAKE_TOOLCHAIN_FILE=$VcpkgToolchain"
}

cmake @ConfigureArgs
cmake --build $BuildDir --config $Config --target $Target --parallel

$Binary = if ($HeadlessOnly) {
    Join-Path $BuildDir "$Config\fieldmesh-imgui-control-headless.exe"
} else {
    Join-Path $BuildDir "$Config\fieldmesh-imgui-control-glfw.exe"
}

Write-Host "fieldmesh_windows_imgui_build=pass"
Write-Host "binary=$Binary"
