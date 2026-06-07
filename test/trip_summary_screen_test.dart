import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/repositories/trip_repository.dart';
import 'package:ralroads/screens/trip_summary_screen.dart';

void main() {
  testWidgets('TripSummaryScreen handles empty point list', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = TripRepository(database);
    addTearDown(database.close);

    await repository.startTrip(
      id: 'trip-empty',
      startedAt: DateTime(2026, 1, 1, 12),
      name: 'Empty trip',
    );
    await repository.finishTrip(
      tripId: 'trip-empty',
      endedAt: DateTime(2026, 1, 1, 12, 5),
      distanceMeters: 0,
      cleanEligible: true,
    );

    await tester.pumpWidget(_summaryApp(repository, 'trip-empty'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Empty trip'), findsWidgets);
    expect(find.text('0 m'), findsWidgets);
    expect(find.text('GPS points'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Speed profile'), findsNothing);

    await _disposeSummaryApp(tester);
  });

  testWidgets('TripSummaryScreen reacts to trip rename', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = TripRepository(database);
    addTearDown(database.close);

    await repository.startTrip(
      id: 'trip-rename',
      startedAt: DateTime(2026, 1, 1, 12),
      name: 'Morning drive',
    );

    await tester.pumpWidget(_summaryApp(repository, 'trip-rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Morning drive'), findsWidgets);

    await repository.renameTrip('trip-rename', 'Evening drive');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Evening drive'), findsWidgets);

    await _disposeSummaryApp(tester);
  });

  testWidgets('TripSummaryScreen reacts to new trip points', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = TripRepository(database);
    addTearDown(database.close);

    await repository.startTrip(
      id: 'trip-points',
      startedAt: DateTime(2026, 1, 1, 12),
      name: 'Point stream',
    );

    await tester.pumpWidget(_summaryApp(repository, 'trip-points'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('0'), findsOneWidget);

    await repository.appendTripPoints('trip-points', [
      TripRecordingPoint(
        recordedAt: DateTime(2026, 1, 1, 12),
        lat: 46,
        lon: 11,
        accuracyMeters: 4,
        speedMps: 8,
        speedLimitKmh: 50,
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1'), findsOneWidget);

    await _disposeSummaryApp(tester);
  });
}

Widget _summaryApp(TripRepository repository, String tripId) {
  return MaterialApp(
    home: TripSummaryScreen(repository: repository, tripId: tripId),
  );
}

Future<void> _disposeSummaryApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}
