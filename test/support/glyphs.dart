import 'package:flutter_test/flutter_test.dart';
import 'package:grobing/app/widgets/grobing_icon.dart';

/// The app's icons are [GrobingIcon]s drawn from its own font (ISSUE-046), not `Icon`s, so `find.byIcon` does not
/// see them: this finds the icon showing [glyph].
Finder findGlyph(Glyph glyph) =>
    find.byWidgetPredicate((w) => w is GrobingIcon && w.icon == glyph);
