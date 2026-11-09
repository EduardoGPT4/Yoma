String formatTimeAgo(int milliseconds) {
  if (milliseconds <= 0) {
    return '';
  }

  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final diff = DateTime.now().difference(date);

  if (diff.inMinutes < 1) {
    return 'Hace un momento';
  }
  if (diff.inHours < 1) {
    return 'Hace ${diff.inMinutes} min';
  }
  if (diff.inDays < 1) {
    return 'Hace ${diff.inHours} h';
  }
  if (diff.inDays < 30) {
    return diff.inDays == 1 ? 'Hace 1 día' : 'Hace ${diff.inDays} días';
  }
  if (diff.inDays < 365) {
    final months = (diff.inDays / 30).floor();
    return months <= 1 ? 'Hace 1 mes' : 'Hace $months meses';
  }

  final years = (diff.inDays / 365).floor();
  return years <= 1 ? 'Hace 1 año' : 'Hace $years años';
}
