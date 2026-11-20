import 'package:check_d/features/calendar/domain/calendar_models.dart';
import 'package:check_d/features/calendar/presentation/calendar_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('short timed event reduces detail without a layout overflow', (
    tester,
  ) async {
    final item = CalendarOccurrence(
      id: 'short-course',
      type: CalendarOccurrenceType.course,
      title: '英语',
      subtitle: 'A301 · 第1节',
      date: DateTime(2026, 9, 8),
      colorValue: 0xFF8BA9F0,
      startMinute: 13 * 60 + 20,
      endMinute: 13 * 60 + 45,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 42,
            height: 27,
            child: CalendarWeekEventBlock(item: item),
          ),
        ),
      ),
    );

    expect(find.text('英语'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact course block keeps its tap target', (tester) async {
    var tapped = false;
    final item = CalendarOccurrence(
      id: 'compact-course',
      type: CalendarOccurrenceType.course,
      title: '数学',
      date: DateTime(2026, 9, 8),
      colorValue: 0xFF8BA9F0,
      startMinute: 8 * 60,
      endMinute: 8 * 60 + 20,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 42,
            height: 12,
            child: CalendarWeekEventBlock(
              item: item,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CalendarWeekEventBlock));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow timetable blocks render common course names in full', (
    tester,
  ) async {
    for (final title in ['高等数学', '交互设计基础']) {
      for (final size in const [Size(33, 35), Size(36, 33), Size(42, 30)]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox.fromSize(
                size: size,
                child: CalendarWeekEventBlock(
                  item: CalendarOccurrence(
                    id: 'course',
                    type: CalendarOccurrenceType.course,
                    title: title,
                    date: DateTime(2026, 11, 20),
                    colorValue: 0xFF8BA9F0,
                  ),
                ),
              ),
            ),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(title),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$title at $size');
        final bounds = tester.getRect(find.byType(CalendarWeekEventBlock));
        final text = tester.getRect(find.text(title));
        expect(text.left, greaterThanOrEqualTo(bounds.left));
        expect(text.right, lessThanOrEqualTo(bounds.right));
        expect(text.top, greaterThanOrEqualTo(bounds.top));
        expect(text.bottom, lessThanOrEqualTo(bounds.bottom));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('long course names remain available on long press', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const title = '人工智能导论与机器学习算法设计及计算机视觉综合实验（跨学科项目实践课程）';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 33,
            height: 27,
            child: CalendarWeekEventBlock(
              item: CalendarOccurrence(
                id: 'long-course',
                type: CalendarOccurrenceType.course,
                title: title,
                date: DateTime(2026, 11, 20),
                colorValue: 0xFF8BA9F0,
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('calendar-course-title-marquee')),
      findsOneWidget,
    );
    final originalBlock = tester.getRect(find.byType(CalendarWeekEventBlock));
    final originalTitle = tester.getTopLeft(find.text(title));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text(title)), originalTitle);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getTopLeft(find.text(title)).dx, lessThan(originalTitle.dx));
    expect(tester.getRect(find.byType(CalendarWeekEventBlock)), originalBlock);
    await tester.longPress(find.byType(CalendarWeekEventBlock));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(title), findsNWidgets(2));
    final fullName = find.text(title).last;
    expect(
      tester.renderObject<RenderParagraph>(fullName).didExceedMaxLines,
      isFalse,
    );
    final fullNameBounds = tester.getRect(fullName);
    expect(fullNameBounds.left, greaterThanOrEqualTo(0));
    expect(fullNameBounds.right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('larger text stays inside a short course block', (tester) async {
    for (final height in [20.0, 34.0]) {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 36,
              height: height,
              child: CalendarWeekEventBlock(
                item: CalendarOccurrence(
                  id: 'large-text-course',
                  type: CalendarOccurrenceType.course,
                  title: '交互设计基础',
                  date: DateTime(2026, 11, 20),
                  colorValue: 0xFF8BA9F0,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion keeps long course titles static', (tester) async {
    const title = '人工智能导论与机器学习算法设计及综合实验';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 33,
            height: 27,
            child: CalendarWeekEventBlock(
              item: CalendarOccurrence(
                id: 'reduced-motion-course',
                type: CalendarOccurrenceType.course,
                title: title,
                date: DateTime(2026, 11, 20),
                colorValue: 0xFF8BA9F0,
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('calendar-course-title-marquee')),
      findsNothing,
    );
    final initialTitle = tester.getTopLeft(find.text(title));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.getTopLeft(find.text(title)), initialTitle);
    expect(find.byTooltip(title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
