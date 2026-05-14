#ifndef FIELDMESH_IMGUI_EMBEDDED_RESOURCES_H
#define FIELDMESH_IMGUI_EMBEDDED_RESOURCES_H

namespace fieldmesh_imgui_resources {

static constexpr const char kCommandCaCertificatePem[] =
    "-----BEGIN CERTIFICATE-----\n"
    "MIIBdemoFieldMeshCommandCAPublicTrustAnchorOnly\n"
    "subject=CN=FieldMesh Demo Command CA,O=FieldMesh Demo\n"
    "key-usage=keyCertSign,cRLSign,digitalSignature\n"
    "fingerprint=sha256:5d7f8c4d6b71f0c4b1d6a6e37e24f17a0e9af4b8a3c0d6f1e5a8c2b49e6d31aa\n"
    "-----END CERTIFICATE-----\n";

static constexpr const char kDemoDeviceCertificatePem[] =
    "-----BEGIN CERTIFICATE-----\n"
    "MIIBdemoFieldMeshDerivedDeviceCertificatePublicTemplateOnly\n"
    "subject=CN=FIELD_MESH_DEVICE_EUI,O=FieldMesh Demo Device\n"
    "issuer=CN=FieldMesh Demo Command CA,O=FieldMesh Demo\n"
    "extended-key-usage=clientAuth,serverAuth\n"
    "authorization=peer_discovery,control_plane,messaging,live_video\n"
    "private-key=not-bundled\n"
    "-----END CERTIFICATE-----\n";

static constexpr const char kProfileSchemaJson[] = R"json({
  "schema": "fieldmesh-im-runtime-profile-v1",
  "daemon_protocol": "fieldmesh-eth-sdk",
  "daemon_protocol_version": 1,
  "identity_source": "discovery_or_external_profile",
  "device_eui_rule": "must_not_be_compiled_into_app",
  "endpoint_rule": "must_not_be_compiled_into_app"
})json";

static constexpr const char kAuthPolicyJson[] = R"json({
  "security_model": "command_ca_derived_mutual_auth",
  "command_ca_private_key_bundled": false,
  "device_private_key_source": "os_keystore_or_board_secure_storage",
  "required_scopes": [
    "peer_discovery",
    "control_plane",
    "messaging",
    "live_video"
  ],
  "production_requires_mutual_auth": true,
  "production_requires_authorization": true
})json";

static constexpr const char kCodecPresetJson[] = R"json({
  "camera_capture": {
    "windows": "ffmpeg dshow h264",
    "linux": "ffmpeg v4l2 h264",
    "macos": "ffmpeg avfoundation h264"
  },
  "preview": {
    "windows": "ffplay pipe h264",
    "linux": "ffplay pipe h264",
    "macos": "ffplay pipe h264"
  },
  "default_target_fps": 30,
  "default_target_bitrate_kbps": 1800,
  "max_chunk_bytes": 1200
})json";

static constexpr const char *kEmbeddedResourceNames[] = {
    "command_ca_certificate_pem",
    "demo_device_certificate_pem",
    "runtime_profile_schema_json",
    "auth_policy_json",
    "codec_preset_json",
};

static constexpr unsigned kEmbeddedResourceCount =
    sizeof(kEmbeddedResourceNames) / sizeof(kEmbeddedResourceNames[0]);

}  // namespace fieldmesh_imgui_resources

#endif  // FIELDMESH_IMGUI_EMBEDDED_RESOURCES_H
