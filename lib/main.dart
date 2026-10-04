import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

void main() => runApp(const SessionCameraApp());

// Flutter supplies the template's build pipeline. The camera UI is native iOS.
class SessionCameraApp extends StatelessWidget {
  const SessionCameraApp({super.key});

  @override
  Widget build(BuildContext context) => const CupertinoApp(
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(brightness: Brightness.dark),
        home: _NativeCameraLauncher(),
      );
}

class _NativeCameraLauncher extends StatefulWidget {
  const _NativeCameraLauncher();

  @override
  State<_NativeCameraLauncher> createState() => _NativeCameraLauncherState();
}

class _NativeCameraLauncherState extends State<_NativeCameraLauncher> {
  static const _channel = MethodChannel('session_camera/native');
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  Future<void> _launch() async {
    try {
      await _channel.invokeMethod<void>('openCamera');
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on MissingPluginException {
      if (mounted) {
        setState(() => _error = '借拍需要安装在 iPhone 上运行。');
      }
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
        backgroundColor: CupertinoColors.black,
        child: Center(
          child: _error == null
              ? const CupertinoActivityIndicator()
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.camera, size: 52),
                      const SizedBox(height: 20),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      CupertinoButton(
                          onPressed: _launch, child: const Text('重试')),
                    ],
                  ),
                ),
        ),
      );
}
