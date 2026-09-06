import 'package:driver_attune/app.dart';
import 'package:driver_attune/dev_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // HomeShell loads the driving record from shared_preferences on startup.
    SharedPreferences.setMockInitialValues({});
  });

  // Pump the app on a phone-sized surface. The default 800x600 test window is
  // too short once the bottom navigation bar is present and squeezes the camera
  // panel into an overflow.
  Future<void> pumpApp(
    WidgetTester tester, {
    Size physicalSize = const Size(1170, 2532),
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DriverAttuneApp());
  }

  testWidgets('shows drive session prototype controls', (tester) async {
    await pumpApp(tester);

    expect(find.text('Driver Attune'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Driving mode'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Summaries'), findsOneWidget);
    expect(find.text('Auto simulation'), findsNothing);
    expect(find.text('Calibrate (look at the road)'), findsOneWidget);
    expect(find.text('Simulate attentive'), findsNothing);
    expect(find.text('Simulate looking away'), findsNothing);
    expect(find.text('Next simulated event'), findsNothing);
    expect(
      find.text('Simulate moving'),
      kSimulateMoving ? findsOneWidget : findsNothing,
    );
    expect(find.byType(SingleChildScrollView), findsNothing);

    final preview = find.byKey(const Key('drive-camera-panel'));
    final initialPreviewRect = tester.getRect(preview);
    await tester.tap(find.text('Driving mode'));
    await tester.pump();
    expect(tester.getRect(preview), initialPreviewRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the drive session controls in landscape', (tester) async {
    await pumpApp(tester, physicalSize: const Size(2532, 1170));

    expect(find.text('Driver Attune'), findsNothing);
    expect(find.text('Driving mode'), findsOneWidget);
    expect(find.text('Calibrate (look at the road)'), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Drive'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Summaries'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offers an automatic Driving mode setting', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    final automaticModeSetting = find.text(
      'Automatically enable Driving mode when traveling by car',
    );
    await tester.scrollUntilVisible(
      automaticModeSetting,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      automaticModeSetting,
      findsOneWidget,
    );
    expect(find.byType(SwitchListTile), findsWidgets);
  });

  testWidgets('flags phone use when backgrounded while driving',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Driving mode'));
    await tester.pump();

    // Walk through the lifecycle states the OS sends when leaving the app.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();

    expect(find.text('Using phone'), findsOneWidget);
  });
}
