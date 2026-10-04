import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_camera/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('session_camera/native');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('launches the native camera once after the first frame', (
    tester,
  ) async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    await tester.pumpWidget(const SessionCameraApp());
    await tester.pump();
    expect(calls, ['openCamera']);
    await tester.pump();
    expect(calls, ['openCamera']);
  });

  testWidgets('failed native startup offers a working retry', (tester) async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      attempts++;
      throw PlatformException(code: 'no_controller', message: '相机启动失败');
    });
    await tester.pumpWidget(const SessionCameraApp());
    await tester.pump();
    expect(find.text('相机启动失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(attempts, 2);
  });
}
