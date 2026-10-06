import 'package:flutter/material.dart';

import '../backup/backup_archive.dart';
import '../backup/backup_service.dart';
import 'theme.dart';

/// One-time backup setup (ISSUE-008): passphrase twice, then two "save as" windows — the key file,
/// then the backup file — and the first backup. A technical screen in the base theme, like
/// "Stan danych"; the product's visual guidelines are NT-006.
class BackupSetupScreen extends StatefulWidget {
  const BackupSetupScreen({
    super.key,
    required this.backup,
    this.replacesExisting = false,
  });

  final BackupService backup;

  /// Setting up again makes a new key: the old key file will not open new backups.
  final bool replacesExisting;

  @override
  State<BackupSetupScreen> createState() => _BackupSetupScreenState();
}

class _BackupSetupScreenState extends State<BackupSetupScreen> {
  final TextEditingController _passphrase = TextEditingController();
  final TextEditingController _repeat = TextEditingController();
  BackupSetupStep? _step;
  String? _problem;

  static const Map<BackupSetupStep, String> _stepLabels = {
    BackupSetupStep.protectingKey: 'Zabezpieczam klucz hasłem (ok. 15 s)…',
    BackupSetupStep.savingKey:
        'Wybierz miejsce na plik klucza: Dysk Google, folder na kopię.',
    BackupSetupStep.savingBackup:
        'Wybierz miejsce na plik kopii: ten sam folder w Dysku Google.',
    BackupSetupStep.firstBackup: 'Robię pierwszą kopię…',
  };

  @override
  void dispose() {
    _passphrase.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_passphrase.text.isEmpty) {
      setState(() => _problem = 'Wpisz hasło.');
      return;
    }
    if (_passphrase.text != _repeat.text) {
      setState(() => _problem = 'Hasła się różnią.');
      return;
    }
    setState(() {
      _problem = null;
      _step = BackupSetupStep.protectingKey;
    });
    try {
      final configured = await widget.backup.setUp(
        _passphrase.text,
        onStep: (step) {
          if (mounted) setState(() => _step = step);
        },
      );
      if (!mounted) return;
      if (configured == null) {
        setState(
          () => _problem = 'Przerwano — konfiguracja kopii nie powstała.',
        );
      } else {
        Navigator.of(context).pop(true);
      }
    } on BackupException catch (e) {
      if (mounted) setState(() => _problem = e.message);
    } on Exception catch (e) {
      // No details on screen: they could carry paths; the type is enough to report.
      if (mounted) {
        setState(
          () => _problem = 'Konfiguracja nie powiodła się (${e.runtimeType}).',
        );
      }
    } finally {
      if (mounted) setState(() => _step = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool busy = _step != null;
    const TextStyle body = TextStyle(color: GrobingColors.text, height: 1.4);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Konfiguracja kopii'),
          backgroundColor: GrobingColors.background,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Kopia to jeden zaszyfrowany plik w Twoim Dysku Google, nadpisywany przy każdej '
              'kopii. Szyfruje go telefon, więc Dysk przechowuje tylko szyfrogram.',
              style: body,
            ),
            const SizedBox(height: 12),
            const Text(
              'Do otwarcia kopii potrzebne są trzy rzeczy: plik kopii, plik klucza i hasło. '
              'Utrata hasła albo pliku klucza oznacza utratę kopii — hasła nie da się odzyskać. '
              'Hasło zapisz w notce przekazania, na papierze, nie w Dysku.',
              style: body,
            ),
            const SizedBox(height: 12),
            const Text(
              'System dwa razy zapyta, gdzie zapisać plik: najpierw plik klucza, potem plik '
              'kopii. Wybierz Dysk Google, ten sam folder.',
              style: body,
            ),
            if (widget.replacesExisting) ...[
              const SizedBox(height: 12),
              const Text(
                'Nowa konfiguracja tworzy nowy klucz. Poprzedni plik klucza nie otworzy nowych '
                'kopii — zaktualizuj notkę przekazania.',
                style: TextStyle(color: GrobingColors.amber, height: 1.4),
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              controller: _passphrase,
              enabled: !busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(labelText: 'Hasło'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _repeat,
              enabled: !busy,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(labelText: 'Powtórz hasło'),
            ),
            if (_problem != null) ...[
              const SizedBox(height: 16),
              Text(
                _problem!,
                style: const TextStyle(color: GrobingColors.amber),
              ),
            ],
            if (busy) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_stepLabels[_step]!, style: body)),
                ],
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: busy ? null : _start,
              child: const Text('Utwórz klucz i pierwszą kopię'),
            ),
          ],
        ),
      ),
    );
  }
}
