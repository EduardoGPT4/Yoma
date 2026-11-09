int naturalCompare(String a, String b) {
  final aParts = _splitParts(a);
  final bParts = _splitParts(b);
  final count = aParts.length < bParts.length ? aParts.length : bParts.length;

  for (var i = 0; i < count; i++) {
    final aPart = aParts[i];
    final bPart = bParts[i];
    final aNum = int.tryParse(aPart);
    final bNum = int.tryParse(bPart);

    if (aNum != null && bNum != null) {
      if (aNum != bNum) {
        return aNum.compareTo(bNum);
      }
    } else {
      final cmp = aPart.toLowerCase().compareTo(bPart.toLowerCase());
      if (cmp != 0) {
        return cmp;
      }
    }
  }

  return aParts.length.compareTo(bParts.length);
}

List<String> _splitParts(String value) {
  return RegExp(r'\d+|\D+')
      .allMatches(value)
      .map((match) => match.group(0) ?? '')
      .where((part) => part.isNotEmpty)
      .toList();
}
