String resolveRemoteMediaUrl(Iterable<dynamic> candidates) {
  for (final candidate in candidates) {
    final value = (candidate ?? '').toString().trim();
    if (value.isEmpty) continue;
    if (isRemoteMediaUrl(value)) {
      return value;
    }
  }
  return '';
}

bool isRemoteMediaUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return false;

  final uri = Uri.tryParse(value);
  final scheme = (uri?.scheme ?? '').toLowerCase();
  return scheme == 'http' || scheme == 'https' || scheme == 'gs';
}
