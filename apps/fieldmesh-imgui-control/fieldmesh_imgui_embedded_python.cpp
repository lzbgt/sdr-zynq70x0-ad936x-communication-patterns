#include <cstddef>

#ifdef FIELDMESH_WITH_EMBEDDED_PYTHON
#include <Python.h>

namespace {

PyObject *py_browse_peers(PyObject *, PyObject *)
{
    return Py_BuildValue("{s:s,s:O}", "operation", "browse_peers", "ok", Py_True);
}

PyObject *py_select_board(PyObject *, PyObject *args)
{
    const char *device_eui = nullptr;
    if (!PyArg_ParseTuple(args, "s", &device_eui)) {
        return nullptr;
    }
    return Py_BuildValue("{s:s,s:s,s:O}", "operation", "select_board",
                         "device_eui", device_eui, "ok", Py_True);
}

PyObject *py_open_chat(PyObject *, PyObject *args)
{
    const char *peer_eui = nullptr;
    if (!PyArg_ParseTuple(args, "s", &peer_eui)) {
        return nullptr;
    }
    return Py_BuildValue("{s:s,s:s,s:O}", "operation", "open_chat",
                         "peer_eui", peer_eui, "ok", Py_True);
}

PyObject *py_send_message(PyObject *, PyObject *args)
{
    const char *peer_eui = nullptr;
    const char *text = nullptr;
    if (!PyArg_ParseTuple(args, "ss", &peer_eui, &text)) {
        return nullptr;
    }
    return Py_BuildValue("{s:s,s:s,s:s,s:O}", "operation", "send_message",
                         "peer_eui", peer_eui, "text", text, "ok", Py_True);
}

PyObject *py_publish_video(PyObject *, PyObject *args)
{
    const char *peer_eui = nullptr;
    if (!PyArg_ParseTuple(args, "s", &peer_eui)) {
        return nullptr;
    }
    return Py_BuildValue("{s:s,s:s,s:O}", "operation", "publish_video",
                         "peer_eui", peer_eui, "ok", Py_True);
}

PyObject *py_subscribe_video(PyObject *, PyObject *args)
{
    const char *peer_eui = nullptr;
    if (!PyArg_ParseTuple(args, "s", &peer_eui)) {
        return nullptr;
    }
    return Py_BuildValue("{s:s,s:s,s:O}", "operation", "subscribe_video",
                         "peer_eui", peer_eui, "ok", Py_True);
}

PyMethodDef kFieldMeshMethods[] = {
    {"browse_peers", py_browse_peers, METH_NOARGS,
     "Discover FieldMesh peers through the app process."},
    {"select_board", py_select_board, METH_VARARGS,
     "Select a provisioned board by runtime-discovered EUI."},
    {"open_chat", py_open_chat, METH_VARARGS,
     "Open a peer conversation."},
    {"send_message", py_send_message, METH_VARARGS,
     "Send a chat message through the app control/data plane."},
    {"publish_video", py_publish_video, METH_VARARGS,
     "Publish live video to a peer."},
    {"subscribe_video", py_subscribe_video, METH_VARARGS,
     "Subscribe to a peer live video stream."},
    {nullptr, nullptr, 0, nullptr},
};

PyModuleDef kFieldMeshModule = {
    PyModuleDef_HEAD_INIT,
    "fieldmesh_imgui",
    "Embedded FieldMesh IM app Python API.",
    -1,
    kFieldMeshMethods,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
};

}  // namespace

PyMODINIT_FUNC PyInit_fieldmesh_imgui(void)
{
    return PyModule_Create(&kFieldMeshModule);
}

extern "C" bool fieldmesh_imgui_start_embedded_python(void)
{
    if (PyImport_AppendInittab("fieldmesh_imgui", PyInit_fieldmesh_imgui) != 0) {
        return false;
    }
    Py_Initialize();
    return Py_IsInitialized() != 0;
}
#else
extern "C" const char *fieldmesh_imgui_embedded_python_contract(void)
{
    return "fieldmesh_imgui embedded_in_process python module: "
           "browse_peers select_board open_chat send_message "
           "publish_video subscribe_video";
}
#endif
