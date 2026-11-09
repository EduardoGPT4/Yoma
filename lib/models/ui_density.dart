enum UiDensity {
  compact,
  comfortable;

  String get label => switch (this) {
    UiDensity.compact => 'Compacta',
    UiDensity.comfortable => 'Cómoda',
  };

  static UiDensity fromName(String? raw) {
    return UiDensity.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => UiDensity.compact,
    );
  }
}
