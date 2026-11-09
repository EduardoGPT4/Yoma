import '../data/library_store.dart';

class AutomationSettings {
  final bool updates, autoDownload, wifiOnly, chargingOnly, backups;
  final int batteryMinimum, aheadCount, budgetMiB, backupRetention;
  const AutomationSettings({
    this.updates = false,
    this.autoDownload = false,
    this.wifiOnly = true,
    this.chargingOnly = false,
    this.backups = true,
    this.batteryMinimum = 20,
    this.aheadCount = 0,
    this.budgetMiB = 512,
    this.backupRetention = 7,
  });
  factory AutomationSettings.fromMap(Map<String, dynamic> m) =>
      AutomationSettings(
        updates: m['updates'] == true,
        autoDownload: m['autoDownload'] == true,
        wifiOnly: m['wifiOnly'] != false,
        chargingOnly: m['chargingOnly'] == true,
        backups: m['backups'] != false,
        batteryMinimum: ((m['batteryMinimum'] as num?)?.toInt() ?? 20).clamp(
          10,
          90,
        ),
        aheadCount: ((m['aheadCount'] as num?)?.toInt() ?? 0).clamp(0, 10),
        budgetMiB: ((m['budgetMiB'] as num?)?.toInt() ?? 512).clamp(32, 8192),
        backupRetention: ((m['backupRetention'] as num?)?.toInt() ?? 7).clamp(
          2,
          30,
        ),
      );
  Map<String, dynamic> toMap() => {
    'updates': updates,
    'autoDownload': autoDownload,
    'wifiOnly': wifiOnly,
    'chargingOnly': chargingOnly,
    'backups': backups,
    'batteryMinimum': batteryMinimum,
    'aheadCount': aheadCount,
    'budgetMiB': budgetMiB,
    'backupRetention': backupRetention,
  };
  static Future<AutomationSettings> load() async => AutomationSettings.fromMap(
    await (await LibraryStore.ensureInitialized()).getRecord(
          'automation',
          'settings',
        ) ??
        {},
  );
  Future<void> save() async => (await LibraryStore.ensureInitialized())
      .putRecord('automation', 'settings', toMap());
}
