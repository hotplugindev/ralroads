class GeocodingResult {
  const GeocodingResult({
    required this.name,
    this.city,
    this.state,
    this.country,
    this.street,
    this.houseNumber,
    required this.lat,
    required this.lon,
  });

  final String name;
  final String? city;
  final String? state;
  final String? country;
  final String? street;
  final String? houseNumber;
  final double lat;
  final double lon;

  String get subtitle {
    final parts = <String>[];
    if (street != null) {
      if (houseNumber != null) {
        parts.add('$street $houseNumber');
      } else {
        parts.add(street!);
      }
    }
    if (city != null) parts.add(city!);
    if (state != null) parts.add(state!);
    if (country != null) parts.add(country!);
    return parts.join(', ');
  }

  @override
  String toString() => name;
}
