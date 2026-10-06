import 'dart:convert';
import 'dart:io';

/// What the app remembers about the backup. Kept in `backup.json` next to the database, **not in
/// it**: a backup time inside the database would change the data fingerprint with every backup and
/// need a schema migration (ISSUE-008, step 5). Holds no secret — never the passphrase, never the
/// secret key; the recipient is a public key.
class BackupSettings {
  const BackupSettings({
    required this.recipient,
    required this.documentUri,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastFailure,
  });

  factory BackupSettings.fromJson(Map<String, Object?> json) => BackupSettings(
    recipient: json['recipient']! as String,
    documentUri: json['document_uri']! as String,
    lastSuccessAt: _time(json['last_success_at']),
    lastFailureAt: _time(json['last_failure_at']),
    lastFailure: json['last_failure'] as String?,
  );

  /// The X25519 public key the backup is encrypted to (`age1…`).
  final String recipient;

  /// The backup file the user picked in the system "save as" window, with a persisted permission.
  final String documentUri;

  /// When the provider (e.g. Google Drive) last accepted the whole file — not when it reached the
  /// cloud; the app cannot see that (ADR-004, Consequences).
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;

  /// Polish, for the screen; no family data, no secrets.
  final String? lastFailure;

  bool get lastAttemptFailed =>
      lastFailureAt != null &&
      (lastSuccessAt == null || lastFailureAt!.isAfter(lastSuccessAt!));

  BackupSettings succeeded(DateTime at) => BackupSettings(
    recipient: recipient,
    documentUri: documentUri,
    lastSuccessAt: at,
    lastFailureAt: lastFailureAt,
    lastFailure: lastFailure,
  );

  BackupSettings failed(DateTime at, String reason) => BackupSettings(
    recipient: recipient,
    documentUri: documentUri,
    lastSuccessAt: lastSuccessAt,
    lastFailureAt: at,
    lastFailure: reason,
  );

  Map<String, Object?> toJson() => {
    'recipient': recipient,
    'document_uri': documentUri,
    'last_success_at': lastSuccessAt?.toUtc().toIso8601String(),
    'last_failure_at': lastFailureAt?.toUtc().toIso8601String(),
    'last_failure': lastFailure,
  };

  static DateTime? _time(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

/// Reads and writes [BackupSettings] in one JSON file.
class BackupSettingsStore {
  const BackupSettingsStore(this.file);

  final File file;

  /// Null while the backup is not configured.
  Future<BackupSettings?> read() async {
    if (!await file.exists()) return null;
    return BackupSettings.fromJson(
      jsonDecode(await file.readAsString()) as Map<String, Object?>,
    );
  }

  /// Written next to the target and renamed over it, so a crash never leaves half a file.
  Future<void> write(BackupSettings settings) async {
    final File temporary = File('${file.path}.tmp');
    await temporary.parent.create(recursive: true);
    await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}
