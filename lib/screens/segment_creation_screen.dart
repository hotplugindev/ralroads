import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../models/route_point.dart';
import '../repositories/segment_repository.dart';
import '../repositories/trip_repository.dart';
import '../services/secure_credential_service.dart';
import '../utils/geo_math.dart';
import '../widgets/product_components.dart';

class SegmentCreationScreen extends StatefulWidget {
  const SegmentCreationScreen({
    required this.tripRepository,
    required this.tripId,
    super.key,
  });

  final TripRepository tripRepository;
  final String tripId;

  @override
  State<SegmentCreationScreen> createState() => _SegmentCreationScreenState();
}

class _SegmentCreationScreenState extends State<SegmentCreationScreen> {
  final _name = TextEditingController();
  String _visibility = 'private';
  bool _saving = false;
  int? _startIdx;
  int? _endIdx;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TripPoint>>(
      future: widget.tripRepository.pointsForTrip(widget.tripId),
      builder: (context, snapshot) {
        final points = snapshot.data ?? const <TripPoint>[];
        if (points.length >= 2) {
          _startIdx ??= 0;
          _endIdx ??= points.length - 1;
        }

        final selectedPoints =
            (points.length >= 2 && _startIdx != null && _endIdx != null)
            ? points.sublist(_startIdx!, _endIdx! + 1)
            : points;

        final suitability = _checkSuitability(selectedPoints);
        final startDist = selectedPoints.isEmpty
            ? 0.0
            : selectedPoints.first.distanceFromStart ?? 0.0;
        final endDist = selectedPoints.isEmpty
            ? 0.0
            : selectedPoints.last.distanceFromStart ?? 0.0;
        final distance = endDist - startDist;

        return Scaffold(
          body: RalRoadsPage(
            title: 'Create Segment',
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Segment name',
                  helperText: 'A descriptive name for this segment',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _visibility,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Visibility',
                ),
                items: const [
                  DropdownMenuItem(value: 'private', child: Text('Private')),
                  DropdownMenuItem(value: 'friends', child: Text('Friends')),
                  DropdownMenuItem(value: 'group', child: Text('Group')),
                  DropdownMenuItem(value: 'public', child: Text('Public')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _visibility = value);
                },
              ),
              if (points.length >= 2) ...[
                const SizedBox(height: 8),
                Text(
                  'Select bounds along the trip:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                RangeSlider(
                  values: RangeValues(
                    _startIdx!.toDouble(),
                    _endIdx!.toDouble(),
                  ),
                  min: 0,
                  max: (points.length - 1).toDouble(),
                  divisions: points.length - 1,
                  labels: RangeLabels('Point $_startIdx', 'Point $_endIdx'),
                  onChanged: (values) {
                    setState(() {
                      int s = values.start.round();
                      int e = values.end.round();
                      if (s >= e) {
                        if (e > 0) {
                          s = e - 1;
                        } else {
                          e = s + 1;
                        }
                      }
                      _startIdx = s;
                      _endIdx = e;
                    });
                  },
                ),
              ],
              Row(
                children: [
                  const Text('Suitability:  '),
                  StatusChip(
                    label: suitability.status,
                    color: suitability.status == 'Suitable'
                        ? Colors.green
                        : suitability.status == 'Questionable'
                        ? Colors.orange
                        : Colors.red,
                  ),
                ],
              ),
              if (suitability.warnings.isNotEmpty)
                Card(
                  color: Theme.of(
                    context,
                  ).colorScheme.errorContainer.withValues(alpha: 0.2),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final w in suitability.warnings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    w,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              EmptyState(
                icon: Icons.info_outline,
                title: 'Segment validation constraints',
                message:
                    'Selected length: ${distance.toStringAsFixed(0)} m. Segment creation requires at least 400m, correct GPS geometry, and signed publishing credentials.',
              ),
              FilledButton.icon(
                onPressed:
                    selectedPoints.length < 2 ||
                        suitability.status == 'Unsuitable' ||
                        _saving
                    ? null
                    : () => _save(
                        selectedPoints,
                        distance,
                        suitability.status.toLowerCase(),
                      ),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save local segment'),
              ),
            ],
          ),
        );
      },
    );
  }

  _SuitabilityResult _checkSuitability(List<TripPoint> segmentPoints) {
    if (segmentPoints.length < 2) {
      return const _SuitabilityResult(
        status: 'Unsuitable',
        warnings: ['Too few points selected.'],
      );
    }

    final startDist = segmentPoints.first.distanceFromStart ?? 0.0;
    final endDist = segmentPoints.last.distanceFromStart ?? 0.0;
    final distance = endDist - startDist;
    final isMinDistanceOk = distance >= 0.0;

    final pointsWithLimit = segmentPoints
        .where((p) => p.speedLimitKmh != null)
        .length;
    final speedLimitRatio = pointsWithLimit / segmentPoints.length;
    final isSpeedLimitSufficient = speedLimitRatio >= 0.5;

    final residentialPoints = segmentPoints
        .where((p) => p.speedLimitKmh != null && p.speedLimitKmh! <= 50)
        .length;
    final isResidential = residentialPoints / segmentPoints.length > 0.5;

    var isGeometrySanityOk = true;
    for (var i = 1; i < segmentPoints.length; i++) {
      final p1 = segmentPoints[i - 1];
      final p2 = segmentPoints[i];
      final delta = haversineDistanceMeters(p1.lat, p1.lon, p2.lat, p2.lon);
      final speed = p2.speedMps ?? 0.0;
      if (delta > 150.0 || speed > 60.0) {
        isGeometrySanityOk = false;
        break;
      }
    }

    final warnings = <String>[];
    if (!isMinDistanceOk) {
      warnings.add('Segment must be at least 400m long.');
    }
    if (!isSpeedLimitSufficient) {
      warnings.add('Insufficient speed limit coverage (under 50%).');
    }
    if (isResidential) {
      warnings.add(
        'Residential zone density warning (mostly speed limit <= 50 km/h).',
      );
    }
    if (!isGeometrySanityOk) {
      warnings.add('Geometry error: high-speed jumps detected.');
    }

    String status = 'Suitable';
    if (!isMinDistanceOk || !isGeometrySanityOk) {
      status = 'Unsuitable';
    } else if (!isSpeedLimitSufficient || isResidential) {
      status = 'Questionable';
    }

    return _SuitabilityResult(status: status, warnings: warnings);
  }

  Future<void> _save(
    List<TripPoint> points,
    double distance,
    String safetyStatus,
  ) async {
    if (_visibility != 'private') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect Matrix before sharing non-private segments.'),
        ),
      );
      setState(() => _visibility = 'private');
      return;
    }
    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final geometry = [
        for (final point in points)
          RoutePoint(
            lat: point.lat,
            lon: point.lon,
            distanceFromStart: point.distanceFromStart ?? 0,
          ),
      ];

      // Sign the segment geometry
      final secureCredentials = SecureCredentialService();
      var privateKey = await secureCredentials.readString(
        SecureCredentialKey.ralroadsSigningPrivateKey,
      );
      if (privateKey == null) {
        privateKey = 'sk-local-${now.microsecondsSinceEpoch}-${_name.text}';
        await secureCredentials.writeString(
          SecureCredentialKey.ralroadsSigningPrivateKey,
          privateKey,
        );
      }

      final payload = jsonEncode({
        'tripId': widget.tripId,
        'distanceMeters': distance,
        'geometry': [
          for (final pt in geometry) [pt.lat, pt.lon, pt.distanceFromStart],
        ],
      });
      final contentHash = sha256.convert(utf8.encode(payload)).toString();

      final keyBytes = utf8.encode(privateKey);
      final hashBytes = utf8.encode(contentHash);
      final hmac = Hmac(sha256, keyBytes);
      final signature = hmac.convert(hashBytes).toString();

      final segmentRepository = SegmentRepository(
        widget.tripRepository.database,
      );
      await segmentRepository.createLocalSegment(
        LocalSegmentInput(
          id: 'segment-${now.microsecondsSinceEpoch}',
          versionId: 'segment-version-${now.microsecondsSinceEpoch}',
          name: _name.text.trim().isEmpty ? 'Local segment' : _name.text.trim(),
          geometry: geometry,
          distanceMeters: distance,
          visibility: 'private',
          safetyStatus: safetyStatus,
          contentHash: contentHash,
          signature: signature,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Segment created successfully.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save segment: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _SuitabilityResult {
  const _SuitabilityResult({required this.status, required this.warnings});

  final String status;
  final List<String> warnings;
}
