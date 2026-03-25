part of 'memos_providers.dart';

class TagStat {
  const TagStat({
    required this.tag,
    required this.count,
    this.tagId,
    this.parentId,
    this.pinned = false,
    this.colorHex,
    this.lastUsedTimeSec,
    String? path,
  }) : path = path ?? tag;

  final String tag;
  final int count;
  final int? tagId;
  final int? parentId;
  final bool pinned;
  final String? colorHex;
  final int? lastUsedTimeSec;
  final String path;
}

final tagStatsProvider = StreamProvider<List<TagStat>>((ref) async* {
  final db = ref.watch(databaseProvider);

  Future<List<TagStat>> load() async {
    int readInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim()) ?? 0;
      return 0;
    }

    final sqlite = await db.db;
    final list = <TagStat>[];
    final seenPaths = <String>{};
    try {
      final rows = await sqlite.rawQuery('''
SELECT t.id, t.parent_id, t.path, t.pinned, t.color_hex,
       COALESCE(ts.memo_count, 0) AS memo_count,
       MAX(m.update_time) AS last_used_time
FROM tags t
LEFT JOIN tag_stats_cache ts ON ts.tag = t.path
LEFT JOIN memo_tags mt ON mt.tag_id = t.id
LEFT JOIN memos m ON m.uid = mt.memo_uid AND m.state = 'NORMAL'
GROUP BY t.id, t.parent_id, t.path, t.pinned, t.color_hex, ts.memo_count;
''');
      for (final row in rows) {
        final path = row['path'];
        if (path is! String || path.trim().isEmpty) continue;
        final count = readInt(row['memo_count']);
        final lastUsedTimeSec = readInt(row['last_used_time']);
        final tagId = readInt(row['id']);
        final parentId = readInt(row['parent_id']);
        final pinned = readInt(row['pinned']) == 1;
        final colorHex = row['color_hex'] as String?;
        final trimmedPath = path.trim();
        list.add(
          TagStat(
            tag: trimmedPath,
            path: trimmedPath,
            count: count,
            tagId: tagId == 0 ? null : tagId,
            parentId: parentId == 0 ? null : parentId,
            pinned: pinned,
            colorHex: colorHex,
            lastUsedTimeSec: lastUsedTimeSec == 0 ? null : lastUsedTimeSec,
          ),
        );
        seenPaths.add(trimmedPath);
      }

      final statsRows = await sqlite.query(
        'tag_stats_cache',
        columns: const ['tag', 'memo_count'],
      );
      for (final row in statsRows) {
        final tag = row['tag'];
        if (tag is! String || tag.trim().isEmpty) continue;
        final trimmed = tag.trim();
        if (seenPaths.contains(trimmed)) continue;
        final count = readInt(row['memo_count']);
        list.add(TagStat(tag: trimmed, count: count, path: trimmed));
      }
    } catch (_) {
      final rows = await sqlite.query(
        'tag_stats_cache',
        columns: const ['tag', 'memo_count'],
      );
      for (final row in rows) {
        final tag = row['tag'];
        if (tag is! String || tag.trim().isEmpty) continue;
        final count = readInt(row['memo_count']);
        list.add(TagStat(tag: tag.trim(), count: count));
      }
    }

    list.sort((a, b) {
      if (a.pinned != b.pinned) {
        return a.pinned ? -1 : 1;
      }
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return a.tag.compareTo(b.tag);
    });
    return list;
  }

  yield await load();
  await for (final _ in db.changes) {
    yield await load();
  }
});
