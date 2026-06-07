import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/repositories/trip_repository.dart';

void main() {
  late AppDatabase database;
  late TripRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = TripRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('records and finishes a local trip', () async {
    final startedAt = DateTime.utc(2026, 6, 7, 9);
    final finishedAt = startedAt.add(const Duration(minutes: 12));

    await repository.startTrip(
      id: 'trip-1',
      startedAt: startedAt,
      name: 'Local test trip',
    );
    await repository.appendTripPoints('trip-1', [
      TripRecordingPoint(
        recordedAt: startedAt,
        lat: 46.0,
        lon: 11.0,
        accuracyMeters: 4,
        speedMps: 8,
        speedLimitKmh: 50,
        speedCompliant: true,
        distanceFromStart: 0,
      ),
      TripRecordingPoint(
        recordedAt: startedAt.add(const Duration(seconds: 10)),
        lat: 46.001,
        lon: 11.001,
        accuracyMeters: 5,
        speedMps: 9,
        speedLimitKmh: 50,
        speedCompliant: true,
        distanceFromStart: 120,
      ),
    ]);
    await repository.finishTrip(
      tripId: 'trip-1',
      endedAt: finishedAt,
      distanceMeters: 120,
      cleanEligible: true,
    );

    final trips = await repository.recentTrips();
    final points = await database.select(database.tripPoints).get();

    expect(trips, hasLength(1));
    expect(trips.single.name, 'Local test trip');
    expect(trips.single.status, 'finished');
    expect(trips.single.cleanEligible, isTrue);
    expect(points, hasLength(2));
    expect(points.last.pointIndex, 1);
  });
}
