"""Validate the real distribution bundle without extracting it."""
import json
import plistlib
import sys
import zipfile

diagnostics_enabled = "--widget-diagnostics" in sys.argv[2:]
with zipfile.ZipFile(sys.argv[1]) as archive:
    info = plistlib.loads(archive.read("Payload/Runner.app/Info.plist"))
    assert info["CFBundleIdentifier"] == "com.kevin3627713.sessioncamera"
    assert info["CFBundleDisplayName"] == "借拍"
    for key in (
        "NSCameraUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSPhotoLibraryUsageDescription",
        "NSPhotoLibraryAddUsageDescription",
        "NSFaceIDUsageDescription",
    ):
        assert info.get(key), f"Missing permission text: {key}"
    assert info.get("PHPhotoLibraryPreventAutomaticLimitedAccessAlert") is True
    assert "Payload/Runner.app/Runner" in archive.namelist()
    executable = archive.read("Payload/Runner.app/Runner")
    assert b"ui-preview-" not in executable, "Simulator demo data leaked into release"
    assert b"CameraUIPreview" not in executable, "Simulator host leaked into release"
    assert "Payload/Runner.app/Frameworks/App.framework/App" in archive.namelist()
    assert "Payload/Runner.app/Frameworks/Flutter.framework/Flutter" in archive.namelist()
    assert info.get("FlutterDeepLinkingEnabled") is False
    assert "photos-navigation" in info.get("LSApplicationQueriesSchemes", [])
    assert b"photos-navigation" in executable
    assert any("sessioncamera" in entry.get("CFBundleURLSchemes", []) for entry in info.get("CFBundleURLTypes", []))
    extension_root = "Payload/Runner.app/PlugIns/SessionWidgets.appex/"
    widget_info = plistlib.loads(archive.read(extension_root + "Info.plist"))
    assert widget_info["CFBundleIdentifier"] == info["CFBundleIdentifier"] + ".widgets"
    assert widget_info["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.widgetkit-extension"
    assert widget_info["CFBundleShortVersionString"] == info["CFBundleShortVersionString"]
    assert widget_info["CFBundleVersion"] == info["CFBundleVersion"]
    assert widget_info["MinimumOSVersion"] == "18.0"
    assert widget_info.get("NSPhotoLibraryUsageDescription")
    widget_executable = archive.read(extension_root + widget_info["CFBundleExecutable"])
    for kind in (b"SessionCamera.Clear", b"SessionCamera.Blank", b"SessionCamera.Blur", b"SessionCamera.Standard"):
        assert kind in widget_executable, f"Missing legacy-compatible widget kind: {kind!r}"
    metadata = [name for name in archive.namelist() if name.startswith(extension_root + "Metadata.appintents/") and name.endswith(".actionsdata")]
    assert metadata, "Missing App Intents metadata; widget editing/actions will not work"
    definitions = json.loads(archive.read(next(name for name in metadata if name.endswith("/extract.actionsdata"))))
    configuration = definitions["actions"]["CameraWidgetConfiguration"]
    assert "com.apple.link.systemProtocol.WidgetConfiguration" in configuration["systemProtocolMetadata"]
    parameters = {item["name"]: item for item in configuration["parameters"]}
    expected_parameters = {"style", "tapBehavior", "source", "intervalMinutes", "identity"}
    if diagnostics_enabled:
        expected_parameters.add("photoDiagnostic")
    assert set(parameters) == expected_parameters
    assert parameters["tapBehavior"]["typeSpecificMetadata"][1]["string"]["wrapper"] == "none"
    assert parameters["intervalMinutes"]["typeSpecificMetadata"][1]["int"]["wrapper"] == 60
    if diagnostics_enabled:
        assert parameters["photoDiagnostic"]["typeSpecificMetadata"][1]["string"]["wrapper"] == "off"
    else:
        assert all(item["identifier"] != "PhotoWidgetDiagnosticMode" for item in definitions["enums"])
        for marker in (b"WidgetPhotoDiagnostics", b"PhotoPipeline", "绘制测试通过".encode(), "照片请求完成".encode()):
            assert marker not in widget_executable, "Photo diagnostics leaked into the normal IPA"
    assert definitions["actions"]["KeepWidgetOnHomeScreen"]["openAppWhenRun"] is False
    styles = next(item for item in definitions["enums"] if item["identifier"] == "CameraWidgetStyle")
    assert {item["identifier"] for item in styles["cases"]} - {"preset"} == {"clear", "blank", "blur", "standard", "photos"}
    taps = next(item for item in definitions["enums"] if item["identifier"] == "WidgetTapBehavior")
    assert {item["identifier"] for item in taps["cases"]} == {"none", "camera", "photos"}
    assert b"suggestedCropForTargetSize:" in widget_executable
    assert b"VNGenerateAttentionBasedSaliencyImageRequest" not in widget_executable
    for entity, query in (("PhotoSourceEntity", "PhotoSourceQuery"), ("WidgetIdentityEntity", "WidgetIdentityQuery")):
        assert definitions["entities"][entity]["defaultQueryIdentifier"] == "SessionWidgets." + query
        assert definitions["queries"][query]["defaultQueryForEntity"] is True
    assert b"FakeFetchResult" not in widget_executable
    for test_marker in (b"WidgetPhotoIntegration", b"Widget root fixture"):
        assert test_marker not in widget_executable and test_marker not in executable, "Photos test host leaked into release"
    assert widget_executable[:4] == bytes.fromhex("cffaedfe"), "Widget executable must be Mach-O 64-bit"
    assert int.from_bytes(widget_executable[4:8], "little") == 0x0100000C, "Widget must contain device arm64 code"
    for selector in (b"getAllCurrentDescriptorsWithCompletion:", b"setTransparent:", b"setPreferredBackgroundStyle:"):
        assert selector in widget_executable, f"Missing widget hook selector: {selector!r}"
        assert selector not in executable, "Widget hook leaked into camera process"
    assert len([name for name in archive.namelist() if name.startswith("Payload/Runner.app/PlugIns/") and name.endswith(".appex/Info.plist")]) == 1
    assert archive.testzip() is None
print("IPA verified: camera + one arm64 WidgetKit extension, matching versions, isolated hook, URL, permissions and frameworks.")
