import '../driving/driving_session_coordinator.dart';
export '../driving/driving_session_coordinator.dart';

class DrivingSessionController extends DrivingSessionCoordinator {
  DrivingSessionController({
    required super.tripRepository,
    required super.attemptRepository,
    required super.validatorService,
    required super.settings,
  });
}
