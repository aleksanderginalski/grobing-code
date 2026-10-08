import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/title_bar.dart';

/// "Notka przekazania" (ISSUE-022 D4; 05_DESIGN/ustawienia.md, element 6, D3): what the paper note kept
/// by the family must say — the note itself lives outside the app (NT-007). General words only: the
/// app knows neither where the note is nor the passphrase, and never shows the key.
class HandOverNoteScreen extends StatelessWidget {
  const HandOverNoteScreen({super.key});

  static const List<String> _points = [
    'Że kopia istnieje. Grobing robi ją sam, kilka minut po zmianach.',
    'Gdzie leży kopia: folder i nazwy obu plików — kopii '
        '(np. grobing-kopia.age) i klucza (np. grobing-klucz.age).',
    'Hasło do pliku klucza — nigdy w tej samej chmurze co kopia. '
        'Zgubione hasło albo plik klucza to utracona kopia.',
    'Jak otworzyć kopię bez Grobing: program age (age-encryption.org) '
        'odszyfrowuje plik, w środku jest archiwum tar z bazą SQLite i zdjęciami.',
    'Gdzie leży eksport dla rodziny — otworzy się w zwykłej przeglądarce.',
  ];

  static const TextStyle _text = TextStyle(
    color: GrobingColors.text,
    fontSize: 16,
    height: 1.4,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BackTitleBar('Notka przekazania'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const Text(
                  'Kartka u rodziny — poza telefonem i poza chmurą. Bez niej rodzina '
                  'nie otworzy kopii. Na kartce:',
                  style: _text,
                ),
                const SizedBox(height: 12),
                for (final (int i, String point) in _points.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            '${i + 1}.',
                            style: _text.copyWith(
                              color: GrobingColors.textMuted,
                            ),
                          ),
                        ),
                        Expanded(child: Text(point, style: _text)),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  '„Skonfiguruj kopię od nowa” tworzy nowy klucz — wtedy notkę trzeba '
                  'wymienić. Zmiana telefonu jej nie zmienia.',
                  style: TextStyle(
                    color: GrobingColors.textMuted,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
