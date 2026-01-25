import 'package:org_parser/org_parser.dart';
import 'package:orgro/src/transclusion/transclusion_directive.dart';

/// Cache for resolved transclusions to avoid repeated file loading.
class TransclusionCache {
  TransclusionCache({this.maxSize = 50});

  final int maxSize;
  final Map<String, TransclusionCacheEntry> _cache = {};
  final List<String> _accessOrder = [];

  /// Get cached result for a directive.
  TransclusionCacheEntry? get(TransclusionDirective directive) {
    final key = _cacheKey(directive);
    final entry = _cache[key];
    if (entry != null) {
      // Move to end of access order (LRU)
      _accessOrder.remove(key);
      _accessOrder.add(key);
    }
    return entry;
  }

  /// Cache a result for a directive.
  void put(TransclusionDirective directive, OrgTree content, String sourceId) {
    final key = _cacheKey(directive);

    // Evict oldest if at capacity
    if (_cache.length >= maxSize && !_cache.containsKey(key)) {
      final oldest = _accessOrder.removeAt(0);
      _cache.remove(oldest);
    }

    _cache[key] = TransclusionCacheEntry(
      content: content,
      sourceId: sourceId,
      loadedAt: DateTime.now(),
    );
    _accessOrder.remove(key);
    _accessOrder.add(key);
  }

  /// Invalidate all cached entries for a specific file.
  void invalidate(String sourceId) {
    final keysToRemove = <String>[];
    _cache.forEach((key, entry) {
      if (entry.sourceId == sourceId) {
        keysToRemove.add(key);
      }
    });
    for (final key in keysToRemove) {
      _cache.remove(key);
      _accessOrder.remove(key);
    }
  }

  /// Clear all cached entries.
  void clear() {
    _cache.clear();
    _accessOrder.clear();
  }

  /// Number of cached entries.
  int get length => _cache.length;

  /// Generate cache key from directive.
  /// Key is based on link location + extra (search option) + properties.
  String _cacheKey(TransclusionDirective directive) {
    final link = directive.link;
    return '${link.scheme ?? ''}${link.body}::${link.extra ?? ''}'
        ':nfh=${directive.noFirstHeading}'
        ':oc=${directive.onlyContents}'
        ':lvl=${directive.level}';
  }
}

/// Entry in the transclusion cache.
class TransclusionCacheEntry {
  TransclusionCacheEntry({
    required this.content,
    required this.sourceId,
    required this.loadedAt,
  });

  /// The resolved and transformed content.
  final OrgTree content;

  /// Identifier of the source file (for invalidation).
  final String sourceId;

  /// When this entry was loaded.
  final DateTime loadedAt;
}
