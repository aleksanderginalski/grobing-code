import 'package:flutter/material.dart';

import '../../backup/backup_archive.dart' show BackupException;
import '../../backup/backup_service.dart';
import '../../backup/backup_settings.dart';
import '../../backup/restore_service.dart';
import '../../data/data_state.dart';
import '../../data/database.dart';
import '../../data/people.dart';
import '../backup_setup_screen.dart';
import '../data_state_screen.dart';
import '../people/me_picker_screen.dart';
import '../people/people_list.dart';
import '../photo/photos.dart';
import '../restore_screen.dart';
import '../theme.dart';
import '../widgets/title_bar.dart';
import 'export_placeholder_screen.dart';
import 'hand_over_note_screen.dart';

/// The app's version, as `pubspec.yaml` gives it (`version`, without the build number) — kept here so the
/// app needs no package to read it; a test holds the two together.
const String appVersion = '1.0.0';

/// When the last backup was made, the way the settings say it (05_DESIGN/ustawienia.md, element 2):
/// "dziś, 11:42", "wczoraj, 18:05", "03.10.2026, 09:30" — in the phone's time.
String backupWhen(DateTime time, {DateTime? now}) {
  final DateTime t = time.toLocal(), n = (now ?? DateTime.now()).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final String hour = '${two(t.hour)}:${two(t.minute)}';
  final DateTime day = DateTime(t.year, t.month, t.day);
  final DateTime today = DateTime(n.year, n.month, n.day);
  if (day == today) return 'dziś, $hour';
  if (day == DateTime(n.year, n.month, n.day - 1)) return 'wczoraj, $hour';
  return '${two(t.day)}.${two(t.month)}.${t.year}, $hour';
}

/// Where the backup file is, read from the provider of the file picked in the system "save as" window;
/// null for a provider without a known name — then the settings say nothing rather than guess.
String? backupPlace(String documentUri) {
  final String host = Uri.tryParse(documentUri)?.host ?? '';
  if (host.startsWith('com.google.android.apps.docs')) return 'Dysk Google';
  if (host == 'com.android.providers.downloads.documents') return 'Pobrane';
  if (host == 'com.android.externalstorage.documents') {
    return 'pamięć telefonu';
  }
  return null;
}

/// The settings under the gear (ISSUE-022; 05_DESIGN/ustawienia.md v1, D23 of SPIKE-004): "ja", the
/// backup, what is for the family and — a level down — "Stan danych". Not a tab, so without the bottom
/// bar (style-b.md rule 12).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.database,
    required this.location,
    required this.backup,
    this.restore,
    this.onRestored,
    this.photos,
  });

  final GrobingDatabase database;
  final DataLocation location;
  final BackupService backup;
  final RestoreService? restore;
  final Future<void> Function(String notice)? onRestored;
  final Photos? photos;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<BackupSettings?> _backup = widget.backup.readSettings();
  late final Stream<int?> _me = watchMe(widget.database);
  late final Stream<List<PersonListEntry>> _people = watchPeople(
    widget.database,
  );
  bool _backingUp = false;

  void _rereadBackup() =>
      setState(() => _backup = widget.backup.readSettings());

  Future<void> _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _backUpNow() async {
    setState(() => _backingUp = true);
    try {
      await widget.backup.backUpNow();
    } on BackupException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _backingUp = false;
          _backup = widget.backup.readSettings();
        });
      }
    }
  }

  Future<void> _setUpBackup() async {
    await _push(BackupSetupScreen(backup: widget.backup));
    if (mounted) _rereadBackup();
  }

  /// "Odtwórz z kopii" opens the restore at once (element 4, ui review of ISSUE-022): the rarest and most
  /// important way — a new phone — gets no second "Odtwórz z kopii" to find on "Stan danych", under
  /// "Skonfiguruj kopię od nowa". Without a restore (tests of other screens) it stays "Stan danych".
  Future<void> _openRestore() async {
    final RestoreService? restore = widget.restore;
    final Future<void> Function(String notice)? onRestored = widget.onRestored;
    if (restore == null || onRestored == null) return _openDataState();
    final DataState current = await readDataState(
      widget.database,
      mediaDir: widget.location.mediaDir,
    );
    if (!mounted) return;
    await _push(
      RestoreScreen(restore: restore, current: current, onRestored: onRestored),
    );
    if (mounted) _rereadBackup();
  }

  /// "Stan danych" as today (element 7).
  Future<void> _openDataState() async {
    await _push(
      DataStateScreen(
        database: widget.database,
        location: widget.location,
        backup: widget.backup,
        restore: widget.restore,
        onRestored: widget.onRestored,
      ),
    );
    if (mounted) _rereadBackup();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BackTitleBar('Ustawienia'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const _Section('Ty w drzewie'),
                _meRow(),
                const _Section('Kopia'),
                ..._backupRows(),
                _SettingRow(
                  leading: const _ActionIcon(Icons.settings_backup_restore),
                  title: 'Odtwórz z kopii',
                  subtitle: 'Nowy telefon albo utracone dane',
                  onTap: _backingUp ? null : _openRestore,
                  leadsOn: true,
                  dimmed: _backingUp,
                ),
                const _Section('Dla rodziny'),
                _SettingRow(
                  leading: const _ActionIcon(Icons.ios_share),
                  title: 'Eksport dla rodziny',
                  subtitle: 'HTML i PDF — otworzą się bez Grobing',
                  onTap: () => _push(const ExportPlaceholderScreen()),
                  leadsOn: true,
                ),
                _SettingRow(
                  leading: const _ActionIcon(Icons.description_outlined),
                  title: 'Notka przekazania',
                  subtitle:
                      'Gdzie jest kopia i jak ją otworzyć — na papierze, u rodziny',
                  onTap: () => _push(const HandOverNoteScreen()),
                  leadsOn: true,
                ),
                const _Section('Techniczne'),
                _SettingRow(
                  leading: const _InfoIcon(Icons.storage_outlined),
                  title: 'Stan danych',
                  subtitle: 'Wersja bazy, odcisk danych, liczby',
                  onTap: _backingUp ? null : _openDataState,
                  leadsOn: true,
                  dimmed: _backingUp,
                ),
                const _Section('O aplikacji'),
                const _SettingRow(
                  leading: _InfoIcon(Icons.info_outline),
                  title: 'Grobing $appVersion',
                  subtitle:
                      'Mapy: © autorzy OpenStreetMap (ODbL) · Natural Earth',
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  /// Element 1: who "ja" is — the chosen person's profile photo and name (ISSUE-022 D3), or "Ja" in amber.
  Widget _meRow() => StreamBuilder<int?>(
    stream: _me,
    builder: (context, me) => StreamBuilder<List<PersonListEntry>>(
      stream: _people,
      builder: (context, people) {
        PersonListEntry? chosen;
        for (final PersonListEntry p in people.data ?? const []) {
          if (p.id == me.data) chosen = p;
        }
        const String what =
            'Od tej osoby liczą się łańcuchy i nazwy pokrewieństwa';
        // Before the choice the line says what to do (ui review B1, style-b.md rule 9).
        return _SettingRow(
          leading: chosen?.profile != null && widget.photos != null
              ? PersonAvatar(person: chosen!, photos: widget.photos)
              : const ExcludeSemantics(
                  child: InitialsCircle(text: 'Ja', accent: true),
                ),
          title: 'Ja',
          subtitle:
              '${chosen == null ? chooseMeLine : listName(chosen)}\n$what',
          onTap: () => _push(
            MePickerScreen(database: widget.database, photos: widget.photos),
          ),
          leadsOn: true,
        );
      },
    ),
  );

  /// Elements 2 and 3, and the state "kopia nieskonfigurowana" (ustawienia.md → States).
  List<Widget> _backupRows() => [
    FutureBuilder<BackupSettings?>(
      future: _backup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: 56);
        }
        if (snapshot.hasError) {
          return const _SettingRow(
            leading: _ErrorIcon(Icons.error_outline),
            title: 'Nie udało się odczytać ustawień kopii',
          );
        }
        final BackupSettings? backup = snapshot.data;
        if (backup == null) {
          return Column(
            children: [
              const _SettingRow(
                leading: _InfoIcon(Icons.cloud_off_outlined),
                title: 'Kopia nie jest skonfigurowana',
                subtitle:
                    'Do jej otwarcia będą potrzebne: plik kopii, plik klucza i hasło',
              ),
              _SettingRow(
                leading: const _ActionIcon(Icons.backup_outlined),
                title: 'Skonfiguruj kopię',
                onTap: _setUpBackup,
                leadsOn: true,
              ),
            ],
          );
        }
        final String? place = backupPlace(backup.documentUri);
        final String lastSuccess = backup.lastSuccessAt == null
            ? 'jeszcze nie było'
            : [
                backupWhen(backup.lastSuccessAt!) +
                    (backup.lastSuccessInBackground ? ' (w tle)' : ''),
                ?place,
              ].join(' · ');
        // The state of the backup changes under the reader's finger: said aloud (SC 4.1.3, ui review B8).
        return Column(
          children: [
            if (backup.lastAttemptFailed)
              _SettingRow(
                leading: const _ErrorIcon(Icons.sync_problem),
                title: 'Ostatnia kopia się nie udała',
                liveRegion: true,
                subtitle:
                    '${backupWhen(backup.lastFailureAt!)} — ${backup.lastFailure}\n'
                    'Ostatnia udana: $lastSuccess',
              )
            else
              _SettingRow(
                leading: backup.lastSuccessAt == null
                    ? const _InfoIcon(Icons.cloud_queue)
                    : const Icon(
                        Icons.cloud_done_outlined,
                        color: GrobingColors.stateOk,
                      ),
                title: 'Ostatnia udana kopia',
                subtitle: lastSuccess,
                liveRegion: true,
              ),
            _SettingRow(
              leading: _backingUp
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const _ActionIcon(Icons.backup_outlined),
              title: _backingUp ? 'Robię kopię…' : 'Zrób kopię teraz',
              onTap: _backingUp ? null : _backUpNow,
              liveRegion: true,
            ),
          ],
        );
      },
    ),
  ];
}

/// A section's heading (13 sp, muted text).
class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Semantics(
      header: true,
      child: Text(
        title,
        style: const TextStyle(color: GrobingColors.textMuted, fontSize: 13),
      ),
    ),
  );
}

/// An action's icon — amber (style-b.md rule 3).
class _ActionIcon extends StatelessWidget {
  const _ActionIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(icon, color: GrobingColors.amber);
}

/// An information's icon — muted text (rule 3).
class _InfoIcon extends StatelessWidget {
  const _InfoIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, color: GrobingColors.textMuted);
}

/// A failure's icon — the error colour, always next to words (SC 1.4.1).
class _ErrorIcon extends StatelessWidget {
  const _ErrorIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(icon, color: GrobingColors.error);
}

/// One row of the list: ≥ 56 dp, the icon on the left, the title (16 sp, semibold), the description
/// (13 sp, muted), a chevron when it leads further ([leadsOn]) and a dividing line. A row that leads
/// on but cannot now (a backup in progress) is [dimmed], so it does not look like one that works.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.onTap,
    this.leadsOn = false,
    this.dimmed = false,
    this.liveRegion = false,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool leadsOn;
  final bool dimmed;

  /// A state that changes while the screen is open: a screen reader says the new one (SC 4.1.3).
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: GrobingColors.outline)),
    ),
    child: Semantics(
      liveRegion: liveRegion,
      child: MergeSemantics(
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  SizedBox(width: 40, child: Center(child: leading)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: dimmed
                                ? GrobingColors.textMuted
                                : GrobingColors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              color: GrobingColors.textMuted,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (leadsOn)
                    const Icon(
                      Icons.chevron_right,
                      color: GrobingColors.textMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
