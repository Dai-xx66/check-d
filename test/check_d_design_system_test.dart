import 'package:check_d/core/theme/app_theme.dart';
import 'package:check_d/shared/widgets/check_d_design.dart';
import 'package:check_d/shared/widgets/mascot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile floating layer metrics include the device safe area', (
    tester,
  ) async {
    late double bottomNavigationExtent;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 34)),
        child: Builder(
          builder: (context) {
            bottomNavigationExtent = CheckDLayout.mobileBottomNavigationExtent(
              context,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(bottomNavigationExtent, 108);
    expect(CheckDLayout.mobileFloatingLayerGap, 12);
  });

  test('six sheep states use six distinct presentation assets', () {
    expect(checkDSheepAssets.keys.toSet(), SheepState.values.toSet());
    expect(
      checkDSheepAssets.values.toSet(),
      hasLength(SheepState.values.length),
    );
    for (final asset in checkDSheepAssets.values) {
      expect(asset, startsWith('assets/images/sheep_'));
      expect(asset, endsWith('.png'));
    }
  });

  testWidgets('all six sheep state assets are bundled and loadable', (
    tester,
  ) async {
    for (final asset in checkDSheepAssets.values) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(0), reason: asset);
    }
  });

  testWidgets('missing state artwork falls back without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: CheckDSheep(
            state: SheepState.idle,
            assetOverrideForTesting: 'assets/images/missing-sheep.png',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == checkDSheepFallbackAsset,
      ),
      findsOneWidget,
    );
  });

  test('sheep state resolver keeps execution priorities stable', () {
    expect(resolveCheckDSheepState(), SheepState.idle);
    expect(resolveCheckDSheepState(hasRunningTimer: true), SheepState.focus);
    expect(resolveCheckDSheepState(hasPausedTimer: true), SheepState.paused);
    expect(resolveCheckDSheepState(hasCurrentCourse: true), SheepState.course);
    expect(
      resolveCheckDSheepState(hasCurrentCourse: true, isCourseBreak: true),
      SheepState.breakTime,
    );
    expect(
      resolveCheckDSheepState(allTasksComplete: true),
      SheepState.complete,
    );
    expect(
      resolveCheckDSheepState(hasCurrentCourse: true, hasRunningTimer: true),
      SheepState.course,
    );
  });

  testWidgets('six sheep states expose stable semantic labels', (tester) async {
    for (final state in SheepState.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CheckDSheep(state: state)),
        ),
      );
      expect(
        find.byKey(ValueKey('check-d-sheep-${state.name}')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('小羊状态：')), findsOneWidget);
    }
  });

  testWidgets('plain surfaces stay crisp and glass surfaces own the blur', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              CheckDSurface(child: Text('普通内容')),
              CheckDSurface(
                level: CheckDSurfaceLevel.glassFloating,
                child: Text('悬浮状态'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('普通内容'), findsOneWidget);
    expect(find.text('悬浮状态'), findsOneWidget);
  });

  testWidgets('surface hierarchy keeps blur limited to three glass levels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              CheckDSurface(
                key: ValueKey('plain-surface'),
                child: Text('plain'),
              ),
              CheckDSurface(
                key: ValueKey('raised-surface'),
                level: CheckDSurfaceLevel.raised,
                child: Text('raised'),
              ),
              CheckDSurface(
                level: CheckDSurfaceLevel.glassSoft,
                child: Text('soft'),
              ),
              CheckDSurface(
                level: CheckDSurfaceLevel.glassFloating,
                child: Text('floating'),
              ),
              CheckDSurface(
                level: CheckDSurfaceLevel.glassActive,
                child: Text('active'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('plain-surface')),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('raised-surface')),
        matching: find.byType(BackdropFilter),
      ),
      findsNothing,
    );
  });

  testWidgets('reduced motion removes sheep entrance animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: CheckDSheep(state: SheepState.focus)),
        ),
      ),
    );

    final sheep = find.byType(CheckDSheep);
    expect(
      find.descendant(of: sheep, matching: find.byType(SlideTransition)),
      findsNothing,
    );
    expect(
      find.descendant(of: sheep, matching: find.byType(ScaleTransition)),
      findsNothing,
    );
    expect(
      find.descendant(of: sheep, matching: find.byType(FadeTransition)),
      findsOneWidget,
    );
  });

  testWidgets('sheep state change crossfades to its matching asset', (
    tester,
  ) async {
    var state = SheepState.idle;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(body: CheckDSheep(state: state));
          },
        ),
      ),
    );

    update(() => state = SheepState.focus);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('check-d-sheep-idle')), findsOneWidget);
    expect(find.byKey(const ValueKey('check-d-sheep-focus')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('check-d-sheep-idle')), findsNothing);
    expect(find.byKey(const ValueKey('check-d-sheep-focus')), findsOneWidget);
  });

  testWidgets('timer-like same-state rebuild does not restart sheep motion', (
    tester,
  ) async {
    var revision = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: Column(
                children: [
                  Text('$revision'),
                  const CheckDSheep(state: SheepState.idle),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    update(() => revision++);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('complete sheep feedback settles after one presentation', (
    tester,
  ) async {
    var state = SheepState.focus;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(body: CheckDSheep(state: state));
          },
        ),
      ),
    );

    update(() => state = SheepState.complete);
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('section title survives narrow width and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: CheckDSectionTitle(
                title: '今日待完成',
                count: 12,
                trailing: Icon(Icons.chevron_right_rounded),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('pressable scales on pointer down and restores on release', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CheckDPressable(
            onTap: () {},
            child: const SizedBox(
              key: ValueKey('press-target'),
              width: 100,
              height: 40,
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('press-target'))),
    );
    await tester.pump(AppMotion.quick);
    final pressed = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(pressed.scale, lessThan(1));

    await gesture.up();
    await tester.pumpAndSettle();
    final released = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(released.scale, 1);
  });
}
