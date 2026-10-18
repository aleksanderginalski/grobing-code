import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/theme.dart';
import 'package:grobing/app/widgets/glyphs.dart';
import 'package:grobing/app/widgets/grobing_icon.dart';

import '../support/glyphs.dart';

// ISSUE-046 — the app's icons (style-b.md rules 3 and 8): Material Symbols Rounded at weight 300 in two tones from
// the app's own font, growing with the text next to words, and the launcher icon with its monochrome layer.

/// The two text layers of one [GrobingIcon]: the fill underneath, then the outline.
List<TextStyle> _layers(WidgetTester tester, Finder icon) => [
  for (final RichText t in tester.widgetList<RichText>(
    find.descendant(of: icon, matching: find.byType(RichText)),
  ))
    (t.text as TextSpan).style!,
];

double _axis(TextStyle style, String tag) =>
    style.fontVariations!.firstWhere((FontVariation v) => v.axis == tag).value;

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: GrobingTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

/// The code points a TrueType font's cmap maps (formats 4 and 12).
Set<int> _cmap(Uint8List bytes) {
  final ByteData d = ByteData.sublistView(bytes);
  final int tables = d.getUint16(4);
  int? cmap;
  for (int i = 0; i < tables; i++) {
    final int rec = 12 + 16 * i;
    if (String.fromCharCodes(bytes.sublist(rec, rec + 4)) == 'cmap') {
      cmap = d.getUint32(rec + 8);
    }
  }
  final Set<int> out = {};
  final int n = d.getUint16(cmap! + 2);
  for (int i = 0; i < n; i++) {
    final int s = cmap + d.getUint32(cmap + 4 + 8 * i + 4);
    final int format = d.getUint16(s);
    if (format == 4) {
      final int segs = d.getUint16(s + 6) ~/ 2;
      final int ends = s + 14, starts = ends + 2 * segs + 2;
      final int deltas = starts + 2 * segs, offsets = deltas + 2 * segs;
      for (int k = 0; k < segs; k++) {
        final int start = d.getUint16(starts + 2 * k);
        final int end = d.getUint16(ends + 2 * k);
        if (start == 0xFFFF) continue;
        final int delta = d.getInt16(deltas + 2 * k);
        final int range = d.getUint16(offsets + 2 * k);
        for (int cp = start; cp <= end; cp++) {
          final int gid = range == 0
              ? (cp + delta) & 0xFFFF
              : d.getUint16(offsets + 2 * k + range + 2 * (cp - start));
          if (gid != 0) out.add(cp);
        }
      }
    } else if (format == 12) {
      final int groups = d.getUint32(s + 12);
      for (int g = 0; g < groups; g++) {
        final int a = d.getUint32(s + 16 + 12 * g);
        final int b = d.getUint32(s + 20 + 12 * g);
        for (int cp = a; cp <= b; cp++) {
          out.add(cp);
        }
      }
    }
  }
  return out;
}

(int, int) _pngSize(File f) {
  final ByteData d = ByteData.sublistView(f.readAsBytesSync());
  return (d.getUint32(16), d.getUint32(20));
}

void main() {
  group('GrobingIcon (style-b.md rule 3)', () {
    testWidgets(
      'two tones: the same glyph filled at 25% under its outline, Material Symbols weight 300 from the app font',
      (tester) async {
        await _pump(
          tester,
          const GrobingIcon(Glyphs.map, color: GrobingColors.amber),
        );
        final List<TextStyle> layers = _layers(tester, findGlyph(Glyphs.map));
        expect(layers, hasLength(2));
        final TextStyle fill = layers[0], outline = layers[1];
        for (final TextStyle s in layers) {
          expect(s.fontFamily, GrobingIcon.fontFamily);
          expect(_axis(s, 'wght'), 300);
          expect(_axis(s, 'GRAD'), 0);
        }
        expect(_axis(fill, 'FILL'), 1);
        expect(_axis(outline, 'FILL'), 0);
        expect(outline.color, GrobingColors.amber);
        expect(fill.color!.a, closeTo(GrobingColors.amber.a * 0.25, 1e-6));
        expect(fill.color!.withValues(alpha: 1), GrobingColors.amber);
      },
    );

    testWidgets(
      'colour and size come from the IconTheme, as with Icon (buttons and selected states keep working)',
      (tester) async {
        await _pump(
          tester,
          const IconTheme(
            data: IconThemeData(color: GrobingColors.textMuted, size: 18),
            child: GrobingIcon(Glyphs.search),
          ),
        );
        expect(
          _layers(tester, findGlyph(Glyphs.search))[1].color,
          GrobingColors.textMuted,
        );
        expect(tester.getSize(findGlyph(Glyphs.search)), const Size(18, 18));
      },
    );

    testWidgets(
      'next to text it grows with the system text size (decision 2); a standalone control passes '
      'applyTextScaling: false and stays',
      (tester) async {
        await _pump(
          tester,
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GrobingIcon(Glyphs.home, size: 20),
              GrobingIcon(Glyphs.settings, applyTextScaling: false),
            ],
          ),
          textScale: 2,
        );
        expect(tester.getSize(findGlyph(Glyphs.home)), const Size(40, 40));
        expect(tester.getSize(findGlyph(Glyphs.settings)), const Size(24, 24));
      },
    );

    testWidgets(
      "an icon from the author's sheet draws its fill glyph under its line glyph (decision 1')",
      (tester) async {
        await _pump(
          tester,
          const GrobingIcon(Glyphs.nature, color: GrobingColors.amber),
        );
        final List<String> chars = [
          for (final RichText t in tester.widgetList<RichText>(
            find.descendant(
              of: findGlyph(Glyphs.nature),
              matching: find.byType(RichText),
            ),
          ))
            (t.text as TextSpan).text!,
        ];
        expect(chars, [
          String.fromCharCode(Glyphs.nature.fill!),
          String.fromCharCode(Glyphs.nature.codePoint),
        ]);
      },
    );

    testWidgets('one label for a screen reader, not one per tone', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await _pump(
        tester,
        const GrobingIcon(Glyphs.cast, semanticLabel: 'Telewizor'),
      );
      expect(find.bySemanticsLabel('Telewizor'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets(
      "Flutter's own back button draws the app's arrow, 24 dp also at 200% (a standalone control)",
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: GrobingTheme.dark,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(appBar: AppBar(leading: const BackButton())),
            ),
          ),
        );
        expect(findGlyph(Glyphs.arrowBack), findsOneWidget);
        expect(tester.getSize(findGlyph(Glyphs.arrowBack)), const Size(24, 24));
      },
    );
  });

  group('one family of icons (AC-2)', () {
    test(
      'no Material icon in lib/: no Icons.* and no Icon( — Flutter would cut their font and the two tones '
      'would not be there',
      () {
        final RegExp material = RegExp(r'(?<![\w])(Icons\.\w+|Icon\()');
        final List<String> found = [
          for (final FileSystemEntity f in Directory(
            'lib',
          ).listSync(recursive: true))
            if (f is File && f.path.endsWith('.dart'))
              for (final (int i, String line) in f.readAsLinesSync().indexed)
                if (material.hasMatch(line) &&
                    !line.trimLeft().startsWith('//'))
                  '${f.path}:${i + 1}',
        ];
        expect(found, isEmpty);
      },
    );

    test(
      'an icon in a WidgetSpan does not scale itself: Flutter already scales a span\'s child with the text, so a '
      'second scale stood it 3.2 × at 200% (ui review)',
      () {
        final List<String> twice = [];
        for (final FileSystemEntity f in Directory(
          'lib',
        ).listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('.dart')) continue;
          final String src = f.readAsStringSync();
          for (final RegExpMatch m in RegExp(r'WidgetSpan\(').allMatches(src)) {
            // The span's own arguments: up to its closing parenthesis.
            int depth = 1, i = m.end;
            while (depth > 0 && i < src.length) {
              if (src[i] == '(') depth++;
              if (src[i] == ')') depth--;
              i++;
            }
            final String span = src.substring(m.start, i);
            if (span.contains('GrobingIcon(') &&
                !span.contains('applyTextScaling: false')) {
              final int line = src.substring(0, m.start).split('\n').length;
              twice.add('${f.path}:$line');
            }
          }
        }
        expect(twice, isEmpty);
      },
    );

    test('every Glyphs constant is in the font (cmap) and the list in tool/icons/glyphs.txt matches it; the font keeps '
        'its four axes', () {
      final Uint8List font = File(
        'assets/fonts/grobing-symbols.ttf',
      ).readAsBytesSync();
      final Set<int> mapped = _cmap(font);
      // A Material Symbol has one code point; an icon from the author's sheet has its line and its fill glyph.
      final Map<String, List<int>> glyphs = {
        for (final RegExpMatch m in RegExp(
          r'static const Glyph (\w+) = Glyph\(0x([0-9a-f]+)(?:, fill: 0x([0-9a-f]+))?\);',
        ).allMatches(File('lib/app/widgets/glyphs.dart').readAsStringSync()))
          m.group(1)!: [
            int.parse(m.group(2)!, radix: 16),
            if (m.group(3) != null) int.parse(m.group(3)!, radix: 16),
          ],
      };
      final int listed = File('tool/icons/glyphs.txt')
          .readAsLinesSync()
          .where((l) => l.split('#').first.trim().isNotEmpty)
          .length;
      // The Material names of glyphs.txt, plus the author's candle in two tones and solid (style-b.md rule 8).
      expect(glyphs, hasLength(listed + 2));
      expect(glyphs.keys, containsAll(['candle', 'candleSolid']));
      expect(
        glyphs.keys.where((k) => !glyphs[k]!.every(mapped.contains)),
        isEmpty,
      );
      // Decision 1' — the nine icons of the author's sheet, each with its fill, and the candle in two tones.
      expect(
        glyphs.entries.where((e) => e.value.length == 2).map((e) => e.key),
        unorderedEquals([
          'map',
          'group',
          'nature',
          'search',
          'settings',
          'addPhotoAlternate',
          'addLocationAlt',
          'inkPen',
          'cast',
          'candle',
        ]),
      );
      final String tags = String.fromCharCodes(font);
      for (final String axis in [
        'fvar',
        'gvar',
        'FILL',
        'GRAD',
        'opsz',
        'wght',
      ]) {
        expect(tags.contains(axis), isTrue, reason: axis);
      }
    });
  });

  group('the launcher icon (AC-1, decision 4 — the candle L1)', () {
    test(
      'adaptive with the background colour, the foreground and the monochrome layer for themed icons',
      () {
        final String xml = File(
          'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
        ).readAsStringSync();
        expect(
          xml,
          contains('<background android:drawable="@color/grobing_background"'),
        );
        expect(
          xml,
          contains(
            '<foreground android:drawable="@mipmap/ic_launcher_foreground"',
          ),
        );
        expect(
          xml,
          contains(
            '<monochrome android:drawable="@mipmap/ic_launcher_monochrome"',
          ),
        );
        expect(
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
          contains('android:icon="@mipmap/ic_launcher"'),
        );
      },
    );

    test(
      'every density has its layers at 108 dp and the Android 7 icon at 48 dp',
      () {
        const Map<String, double> densities = {
          'mdpi': 1,
          'hdpi': 1.5,
          'xhdpi': 2,
          'xxhdpi': 3,
          'xxxhdpi': 4,
        };
        for (final MapEntry<String, double> e in densities.entries) {
          final String dir = 'android/app/src/main/res/mipmap-${e.key}';
          final int layer = (108 * e.value).round(),
              legacy = (48 * e.value).round();
          expect(_pngSize(File('$dir/ic_launcher_foreground.png')), (
            layer,
            layer,
          ), reason: e.key);
          expect(_pngSize(File('$dir/ic_launcher_monochrome.png')), (
            layer,
            layer,
          ), reason: e.key);
          expect(_pngSize(File('$dir/ic_launcher.png')), (
            legacy,
            legacy,
          ), reason: e.key);
        }
      },
    );
  });
}
