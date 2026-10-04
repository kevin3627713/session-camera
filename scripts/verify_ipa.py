"""Validate the real distribution bundle without extracting it."""
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    info = plistlib.loads(archive.read("Payload/Runner.app/Info.plist"))
    assert info["CFBundleIdentifier"] == "com.kevin3627713.sessioncamera"
    assert info["CFBundleDisplayName"] == "借拍"
    for key in (
        "NSCameraUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSPhotoLibraryUsageDescription",
        "NSPhotoLibraryAddUsageDescription",
    ):
        assert info.get(key), f"Missing permission text: {key}"
    assert info.get("PHPhotoLibraryPreventAutomaticLimitedAccessAlert") is True
    assert "Payload/Runner.app/Runner" in archive.namelist()
    assert "Payload/Runner.app/Frameworks/App.framework/App" in archive.namelist()
    assert "Payload/Runner.app/Frameworks/Flutter.framework/Flutter" in archive.namelist()
    assert archive.testzip() is None
print("IPA verified: correct bundle, executable, Flutter frameworks and permissions.")
