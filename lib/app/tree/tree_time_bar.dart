import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Element 6 (05_DESIGN/drzewo.md v1.12; US-010, ISSUE-037): the time row in the tree's card — ▶ / ❚❚, the
/// slider's first year, the slider, the year ("dziś" at the end). With system text from 150 % the two years
/// stand in a row above ▶ and the slider (D20), so nothing is cut at 200 % on 360 dp.
class TreeTimeBar extends StatelessWidget {
  const TreeTimeBar({
    super.key,
    required this.start,
    required this.now,
    required this.year,
    required this.playing,
    required this.onPlay,
    required this.onYear,
  });

  /// The slider's first year (D34) and this year — its end, "dziś".
  final int start;
  final int now;

  /// Null: "dziś".
  final int? year;
  final bool playing;

  /// ▶ / ❚❚.
  final VoidCallback onPlay;

  /// A year chosen by hand — dragging, or the screen reader's increase and decrease; null for "dziś". Stops ▶.
  final ValueChanged<int?> onYear;

  /// The screen reader moves the slider by a decade: a year at a time is up to 166 gestures (element 6, D5).
  static const int readerStep = 10;

  int get _shown => year ?? now;

  String _label(int y) => y >= now ? 'dziś' : '$y';

  int? _clamp(int y) {
    final int v = y.clamp(start, now);
    return v >= now ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final bool large = MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.5;
    final Widget play = IconButton(
      onPressed: onPlay,
      tooltip: playing ? 'Zatrzymaj' : 'Odtwórz historię',
      padding: EdgeInsets.zero,
      icon: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: GrobingColors.amber,
          shape: BoxShape.circle,
        ),
        child: Icon(
          playing ? Icons.pause : Icons.play_arrow,
          color: GrobingColors.background,
        ),
      ),
    );
    final Widget first = Text(
      '$start',
      style: const TextStyle(
        color: GrobingColors.textMuted,
        fontSize: 13,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
    const TextStyle yearStyle = TextStyle(
      color: GrobingColors.amber,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    // As wide as the widest of "dziś" and a year, whichever is shown: else the slider's track changed its
    // length when "dziś" turned into a year, and the thumb jumped under the finger (found on the emulator).
    final Widget shown = ExcludeSemantics(
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          for (final String room in const ['dziś', '8888'])
            Visibility.maintain(
              visible: false,
              child: Text(room, style: yearStyle),
            ),
          Text(_label(_shown), style: yearStyle),
        ],
      ),
    );
    // The slider's own steps for a screen reader are a hundredth of its range, or one division; a decade is
    // its own action here (D5). The finger drags year by year.
    final Widget slider = Semantics(
      slider: true,
      label: 'Rok',
      value: _label(_shown),
      increasedValue: _label(math.min(now, _shown + readerStep)),
      decreasedValue: _label(math.max(start, _shown - readerStep)),
      onIncrease: () => onYear(_clamp(_shown + readerStep)),
      onDecrease: () => onYear(_clamp(_shown - readerStep)),
      excludeSemantics: true,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: GrobingColors.amber,
          inactiveTrackColor: GrobingColors.outline,
          thumbColor: GrobingColors.amber,
          overlayColor: GrobingColors.amber.withValues(alpha: 0.12),
        ),
        child: Slider(
          value: _shown.toDouble().clamp(start.toDouble(), now.toDouble()),
          min: start.toDouble(),
          max: now.toDouble(),
          onChanged: (v) => onYear(_clamp(v.round())),
        ),
      ),
    );
    if (large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [first, const Spacer(), shown]),
          ),
          Row(
            children: [
              play,
              Expanded(child: slider),
            ],
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          play,
          const SizedBox(width: 4),
          first,
          Expanded(child: slider),
          shown,
        ],
      ),
    );
  }
}
