import 'package:driver_focus/features/driving_record/driving_record.dart';
import 'package:driver_focus/features/driving_record/driving_session_summary.dart';
import 'package:driver_focus/features/summaries/summaries_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a seven-day report for recent sessions', (tester) async {
    final startedAt = DateTime.now().subtract(const Duration(days: 1));
    final record = DrivingRecord(enabled: true)
      ..restore(
        distracted: const Duration(minutes: 2),
        attentive: const Duration(minutes: 18),
        sessions: [
          DrivingSessionSummary(
            startedAt: startedAt,
            endedAt: startedAt.add(const Duration(minutes: 20)),
            movingDuration: const Duration(minutes: 20),
            reliableObservationDuration: const Duration(minutes: 18),
            attentiveDuration: const Duration(minutes: 16),
            lookingAwayDuration: const Duration(minutes: 2),
            drowsinessEventCount: 1,
            attentionReminderCount: 2,
            possiblePhoneUseDuration: const Duration(seconds: 10),
            faceNotVisibleDuration: const Duration(minutes: 1),
            lowQualityDuration: const Duration(minutes: 1),
          ),
        ],
      );

    await tester.pumpWidget(
      MaterialApp(
        home: SummariesScreen(
          record: record,
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.text('Seven-day report'), findsOneWidget);
    expect(find.text('Driving days'), findsOneWidget);
    expect(find.text('Attention trend'), findsOneWidget);
    expect(find.text('Daily consistency'), findsOneWidget);
    expect(find.text('Drowsiness photos'), findsNothing);
    expect(find.text('Drive record'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
