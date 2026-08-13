import 'package:driver_focus/features/driving_record/driving_record.dart';
import 'package:driver_focus/features/driving_record/driving_session_summary.dart';
import 'package:driver_focus/features/evidence/drowsiness_evidence_store.dart';
import 'package:driver_focus/features/records/records_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DrivingSessionSummary session(DateTime startedAt, int attentiveMinutes) {
    return DrivingSessionSummary(
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 10)),
      movingDuration: const Duration(minutes: 10),
      reliableObservationDuration: const Duration(minutes: 10),
      attentiveDuration: Duration(minutes: attentiveMinutes),
      lookingAwayDuration: Duration(minutes: 10 - attentiveMinutes),
      drowsinessEventCount: 0,
      attentionReminderCount: 0,
      possiblePhoneUseDuration: Duration.zero,
      faceNotVisibleDuration: Duration.zero,
      lowQualityDuration: Duration.zero,
    );
  }

  testWidgets('selects a record and resets to newest on the next visit',
      (tester) async {
    final newest = session(DateTime(2026, 1, 2, 9), 9);
    final older = session(DateTime(2026, 1, 1, 9), 5);
    final record = DrivingRecord()
      ..restore(
        distracted: Duration.zero,
        attentive: Duration.zero,
        sessions: [older, newest],
      );

    Widget app(int visitId) => MaterialApp(
          home: RecordsScreen(
            record: record,
            evidenceStore: DrowsinessEvidenceStore(),
            visitId: visitId,
          ),
        );

    await tester.pumpWidget(app(0));
    expect(find.text('90%'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<DateTime>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownMenuItem<DateTime>).last);
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);

    await tester.pumpWidget(app(1));
    await tester.pump();
    expect(find.text('90%'), findsOneWidget);
    expect(find.text('50%'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Drowsiness photos'), findsOneWidget);
  });
}
