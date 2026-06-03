String formatDistance(double meters) {
  if (meters >= 1000) {
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
  return '${meters.round()} m';
}

String formatSpeed(double metersPerSecond) {
  return '${(metersPerSecond * 3.6).toStringAsFixed(0)} km/h';
}

String formatCurrentSpeed(double metersPerSecond) {
  return (metersPerSecond * 3.6).round().toString();
}

String formatDate(DateTime date) {
  final local = date.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}
