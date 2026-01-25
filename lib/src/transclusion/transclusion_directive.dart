import 'package:org_parser/org_parser.dart';

/// Represents a parsed `#+transclude:` directive with its link and properties.
///
/// Example: `#+transclude: [[id:uuid::*heading][desc]] :no-first-heading :level 2`
class TransclusionDirective {
  TransclusionDirective({
    required this.meta,
    required this.link,
    required this.description,
    this.noFirstHeading = false,
    this.onlyContents = false,
    this.level,
    this.excludeElements = const [],
  });

  /// The original OrgMeta node (for identification)
  final OrgMeta meta;

  /// The parsed link (id:uuid::*heading or file:path)
  final OrgFileLink link;

  /// Optional description from [[link][description]]
  final String? description;

  /// :no-first-heading - Remove the top-level headline from transcluded content
  final bool noFirstHeading;

  /// :only-contents - Include only the section body, not subsections
  final bool onlyContents;

  /// :level N - Adjust headline levels to start at N
  final int? level;

  /// :exclude-elements "(...)" - Elements to exclude from transclusion
  final List<String> excludeElements;

  /// Unique identifier for this transclusion (used for caching and toggle state)
  String get id => meta.hashCode.toString();

  /// Try to parse an OrgMeta node as a transclusion directive.
  /// Returns null if not a valid transclusion directive.
  static TransclusionDirective? tryParse(OrgMeta meta) {
    // Check if this is a transclusion directive
    if (meta.key.toLowerCase() != '#+transclude:') return null;
    if (meta.value == null) return null;

    final value = meta.value!.toMarkup().trim();
    if (value.isEmpty) return null;

    // Parse the link: [[link][description]] or [[link]]
    final linkMatch = _linkPattern.firstMatch(value);
    if (linkMatch == null) return null;

    final linkLocation = linkMatch.namedGroup('link')!;
    final description = linkMatch.namedGroup('desc');

    // Parse the link location
    OrgFileLink link;
    try {
      link = OrgFileLink.parse(linkLocation);
    } on Exception {
      return null;
    }

    // Parse properties after the link
    final propsStr = value.substring(linkMatch.end).trim();

    // Parse :no-first-heading
    final noFirstHeading = _noFirstHeadingPattern.hasMatch(propsStr);

    // Parse :only-contents
    final onlyContents = _onlyContentsPattern.hasMatch(propsStr);

    // Parse :level N
    int? level;
    final levelMatch = _levelPattern.firstMatch(propsStr);
    if (levelMatch != null) {
      level = int.tryParse(levelMatch.namedGroup('level')!);
    }

    // Parse :exclude-elements "(elem1 elem2)"
    final excludeElements = <String>[];
    final excludeMatch = _excludeElementsPattern.firstMatch(propsStr);
    if (excludeMatch != null) {
      final elements = excludeMatch.namedGroup('elements')!;
      excludeElements.addAll(elements.split(RegExp(r'\s+')));
    }

    return TransclusionDirective(
      meta: meta,
      link: link,
      description: description,
      noFirstHeading: noFirstHeading,
      onlyContents: onlyContents,
      level: level,
      excludeElements: excludeElements,
    );
  }

  @override
  String toString() => 'TransclusionDirective('
      'link: $link, '
      'noFirstHeading: $noFirstHeading, '
      'onlyContents: $onlyContents, '
      'level: $level)';
}

// Pattern for [[link][description]] or [[link]]
final _linkPattern = RegExp(
  r'\[\[(?<link>[^\]]+)\](?:\[(?<desc>[^\]]*)\])?\]',
);

// Property patterns
final _noFirstHeadingPattern = RegExp(r':no-first-heading\b', caseSensitive: false);
final _onlyContentsPattern = RegExp(r':only-contents\b', caseSensitive: false);
final _levelPattern = RegExp(r':level\s+(?<level>\d+)', caseSensitive: false);
final _excludeElementsPattern = RegExp(
  r':exclude-elements\s+"?\((?<elements>[^)]+)\)"?',
  caseSensitive: false,
);

/// Extract all transclusion directives from an OrgTree.
List<TransclusionDirective> extractTransclusions(OrgTree tree) {
  final results = <TransclusionDirective>[];
  tree.visit<OrgMeta>((meta) {
    final directive = TransclusionDirective.tryParse(meta);
    if (directive != null) {
      results.add(directive);
    }
    return true; // Continue visiting
  });
  return results;
}

/// Check if a tree contains any transclusion directives.
bool hasTransclusions(OrgTree tree) {
  var found = false;
  tree.visit<OrgMeta>((meta) {
    if (meta.key.toLowerCase() == '#+transclude:') {
      found = true;
      return false; // Stop visiting
    }
    return true;
  });
  return found;
}
