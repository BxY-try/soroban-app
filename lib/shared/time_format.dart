/// Formats a duration in milliseconds as `mm:ss`, for on-screen clocks,
/// split cards, and record badges.
String formatTimeMs(int ms) {
  final totalSeconds = ms ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
