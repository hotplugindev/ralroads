import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ralroads/database/app_database.dart';
import 'package:ralroads/repositories/app_repositories.dart';
import 'package:ralroads/repositories/attempt_repository.dart';
import 'package:ralroads/repositories/profile_repository.dart';
import 'package:ralroads/models/route_point.dart';
import 'package:ralroads/repositories/segment_repository.dart';
import 'package:ralroads/services/secure_credential_service.dart';
import 'package:ralroads/services/device_identity_service.dart';
import 'package:ralroads/services/route_storage_service.dart';

void main() {
  group('AttemptRepository Validator Attestations', () {
    late AppDatabase database;
    late AppRepositories repositories;
    late DeviceIdentityService identityService;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      repositories = AppRepositories(
        routeStorage: RouteStorageService(),
        database: database,
      );
      identityService = DeviceIdentityService(
        secureCredentials: SecureCredentialService(
          store: MemorySecureCredentialStore(),
        ),
      );
      await identityService.initializeIdentity();

      // Insert common segment to satisfy foreign key constraints
      await repositories.segments.createLocalSegment(
        const LocalSegmentInput(
          id: 'seg-1',
          versionId: 'seg-version-1',
          name: 'Test segment',
          distanceMeters: 1000,
          safetyStatus: 'suitable',
          contentHash: 'hash-abc',
          geometry: [
            RoutePoint(lat: 46, lon: 11, distanceFromStart: 0),
          ],
        ),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('verifies, saves and updates eligibility for a valid clean attestation', () async {
      final now = DateTime.now();

      // Create profile and attempt
      await repositories.profiles.createOrUpdateLocalProfile(
        const LocalProfileInput(id: 'prof-1', displayName: 'Driver'),
      );
      await repositories.attempts.createAttempt(
        id: 'att-1',
        segmentId: 'seg-1',
        startedAt: now,
        profileId: 'prof-1',
      );
      await repositories.attempts.finishAttempt(
        attemptId: 'att-1',
        finishedAt: now.add(const Duration(minutes: 5)),
        status: 'recording_stopped',
      );

      // Persist local validation result
      const resultHash = 'result-hash-123';
      await repositories.attempts.persistValidationResult(
        const AttemptValidationInput(
          id: 'val-res-1',
          attemptId: 'att-1',
          engineVersion: '0.1.0',
          status: 'valid_clean',
          resultHash: resultHash,
          durationSeconds: 300.0,
          routeMatchScore: 0.95,
          gpsQualityScore: 0.9,
        ),
      );

      // Reconstruct validator canonical message
      final validatorPublicKey = await identityService.getPublicKey();
      const validatorId = 'val-device-1';
      const status = 'valid_clean';
      const durationMs = 300000;
      const engineVersion = '0.1.0';

      final canonicalMessage = 'att-1|$resultHash|$status|$durationMs|$engineVersion|$validatorId|$validatorPublicKey';
      final signature = await identityService.signMessage(canonicalMessage);

      final attestationInput = ValidatorAttestationInput(
        id: 'attest-1',
        attemptId: 'att-1',
        validatorId: validatorId,
        validatorPublicKey: validatorPublicKey,
        status: status,
        engineVersion: engineVersion,
        resultHash: resultHash,
        signature: signature,
      );

      // Verify and save
      final success = await repositories.attempts.verifyAndSaveAttestation(
        input: attestationInput,
        identityService: identityService,
      );

      expect(success, isTrue);

      // Check attestation persisted
      final attestations = await repositories.attempts.getAttestationsForAttempt('att-1');
      expect(attestations, hasLength(1));
      expect(attestations.first.id, 'attest-1');
      expect(attestations.first.signature, signature);

      // Check attempt eligibility updated
      final attempt = await (database.select(database.segmentAttempts)
            ..where((row) => row.id.equals('att-1')))
          .getSingle();
      expect(attempt.officialEligible, isTrue);
      expect(attempt.status, 'valid_clean');
    });

    test('rejects attestation with invalid signature', () async {
      final now = DateTime.now();

      await repositories.profiles.createOrUpdateLocalProfile(
        const LocalProfileInput(id: 'prof-1', displayName: 'Driver'),
      );
      await repositories.attempts.createAttempt(
        id: 'att-2',
        segmentId: 'seg-1',
        startedAt: now,
        profileId: 'prof-1',
      );
      await repositories.attempts.persistValidationResult(
        const AttemptValidationInput(
          id: 'val-res-2',
          attemptId: 'att-2',
          engineVersion: '0.1.0',
          status: 'valid_clean',
          resultHash: 'hash-abc',
          durationSeconds: 120.0,
        ),
      );

      final validatorPublicKey = await identityService.getPublicKey();

      final attestationInput = ValidatorAttestationInput(
        id: 'attest-2',
        attemptId: 'att-2',
        validatorId: 'val-device-1',
        validatorPublicKey: validatorPublicKey,
        status: 'valid_clean',
        engineVersion: '0.1.0',
        resultHash: 'hash-abc',
        signature: 'invalid-signature-hex',
      );

      final success = await repositories.attempts.verifyAndSaveAttestation(
        input: attestationInput,
        identityService: identityService,
      );

      expect(success, isFalse);

      final attestations = await repositories.attempts.getAttestationsForAttempt('att-2');
      expect(attestations, isEmpty);

      final attempt = await (database.select(database.segmentAttempts)
            ..where((row) => row.id.equals('att-2')))
          .getSingle();
      expect(attempt.officialEligible, isFalse);
    });
  });
}
