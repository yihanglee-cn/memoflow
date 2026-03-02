import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/memo_relations.dart';
import '../core/tags.dart';
import '../data/api/server_api_profile.dart';
import '../data/db/app_database.dart';
import '../data/models/local_memo.dart';
import '../data/models/memo_location.dart';
import '../data/models/shortcut.dart';
import 'database_provider.dart';
import 'logging_provider.dart';
import 'memo_timeline_provider.dart';
import 'memos_providers.dart';
import 'reminder_scheduler.dart';
import 'session_provider.dart';
import 'user_settings_provider.dart';

class OutboxMemoStatus {
  const OutboxMemoStatus({required this.pending, required this.failed});
  const OutboxMemoStatus.empty()
    : pending = const <String>{},
      failed = const <String>{};

  final Set<String> pending;
  final Set<String> failed;
}

class MemosListPendingAttachment {
  const MemosListPendingAttachment({
    required this.uid,
    required this.filePath,
    required this.filename,
    required this.mimeType,
    required this.size,
  });

  final String uid;
  final String filePath;
  final String filename;
  final String mimeType;
  final int size;
}

class MemosListMemoResolveResult {
  const MemosListMemoResolveResult._({this.memo, this.error});
  const MemosListMemoResolveResult.found(LocalMemo memo)
    : this._(memo: memo);
  const MemosListMemoResolveResult.notFound() : this._();
  const MemosListMemoResolveResult.error(Object error)
    : this._(error: error);

  final LocalMemo? memo;
  final Object? error;

  bool get isFound => memo != null;
  bool get isNotFound => memo == null && error == null;
  bool get isError => error != null;
}

class MemosListShortcutHints {
  const MemosListShortcutHints({
    required this.useLocalShortcuts,
    required this.canCreateShortcut,
  });

  final bool useLocalShortcuts;
  final bool canCreateShortcut;
}

final memosListControllerProvider = Provider<MemosListController>((ref) {
  return MemosListController(ref);
});

final memosListOutboxStatusProvider = StreamProvider<OutboxMemoStatus>((ref) async* {
  final db = ref.watch(databaseProvider);

  Future<OutboxMemoStatus> load() async {
    final sqlite = await db.db;
    final rows = await sqlite.query(
      'outbox',
      columns: const ['type', 'payload', 'state'],
      where: 'state IN (?, ?, ?, ?)',
      whereArgs: const [
        AppDatabase.outboxStatePending,
        AppDatabase.outboxStateRunning,
        AppDatabase.outboxStateRetry,
        AppDatabase.outboxStateError,
      ],
      orderBy: 'id ASC',
    );
    final pending = <String>{};
    final failed = <String>{};

    for (final row in rows) {
      final type = row['type'];
      final payload = row['payload'];
      final state = row['state'];
      if (type is! String || payload is! String) continue;

      final decoded = _decodeOutboxPayload(payload);
      final uid = _extractOutboxMemoUid(type, decoded);
      if (uid == null || uid.trim().isEmpty) continue;
      final normalized = uid.trim();

      final stateCode = switch (state) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v.trim()),
        _ => null,
      };
      if (stateCode == AppDatabase.outboxStateError) {
        failed.add(normalized);
        pending.remove(normalized);
      } else {
        if (!failed.contains(normalized)) {
          pending.add(normalized);
        }
      }
    }

    return OutboxMemoStatus(pending: pending, failed: failed);
  }

  yield await load();
  await for (final _ in db.changes) {
    yield await load();
  }
});

final memosListNormalMemoCountProvider = StreamProvider<int>((ref) async* {
  final db = ref.watch(databaseProvider);

  Future<int> load() async {
    final sqlite = await db.db;
    final rows = await sqlite.rawQuery('''
      SELECT COUNT(*) AS memo_count
      FROM memos
      WHERE state = 'NORMAL'
    ''');
    if (rows.isEmpty) return 0;
    final raw = rows.first['memo_count'];
    return switch (raw) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value.trim()) ?? 0,
      _ => 0,
    };
  }

  yield await load();
  await for (final _ in db.changes) {
    yield await load();
  }
});

final memosListShortcutHintsProvider = Provider<MemosListShortcutHints>((ref) {
  final account = ref.watch(appSessionProvider).valueOrNull?.currentAccount;
  if (account == null) {
    return const MemosListShortcutHints(
      useLocalShortcuts: true,
      canCreateShortcut: false,
    );
  }
  final api = ref.watch(memosApiProvider);
  final useLocalShortcuts =
      api.usesLegacySearchFilterDialect || api.shortcutsSupportedHint == false;
  final canCreateShortcut =
      useLocalShortcuts || api.shortcutsSupportedHint != false;
  return MemosListShortcutHints(
    useLocalShortcuts: useLocalShortcuts,
    canCreateShortcut: canCreateShortcut,
  );
});

final memosListDebugApiVersionTextProvider = Provider<String>((ref) {
  final account = ref.watch(appSessionProvider).valueOrNull?.currentAccount;
  final resolution = account == null
      ? null
      : MemosServerApiProfiles.resolve(
          manualVersionOverride: account.serverVersionOverride,
          detectedVersion: account.instanceProfile.version,
        );
  return _buildDebugApiVersionText(resolution);
});

class MemosListController {
  MemosListController(this._ref);

  final Ref _ref;

  Future<void> logEmptyViewDiagnostics({
    required String queryKey,
    required String state,
    required int providerCount,
    required int animatedCount,
    required String searchQuery,
    required String? resolvedTag,
    required bool useShortcutFilter,
    required bool useQuickSearch,
    required bool useRemoteSearch,
    required int? startTimeSec,
    required int? endTimeSecExclusive,
    required String shortcutFilter,
    required QuickSearchKind? quickSearchKind,
  }) async {
    try {
      final db = _ref.read(databaseProvider);
      final allRows = await db.listMemosForExport(includeArchived: true);
      var dbNormal = 0;
      var dbArchived = 0;
      for (final row in allRows) {
        final state = (row['state'] as String? ?? '').trim().toUpperCase();
        if (state == 'ARCHIVED') {
          dbArchived++;
        } else {
          dbNormal++;
        }
      }
      final tag = resolvedTag?.trim();
      final normalizedSearch = searchQuery.trim();
      final previewRows = await db.listMemos(
        searchQuery: normalizedSearch.isEmpty ? null : normalizedSearch,
        state: state,
        tag: (tag == null || tag.isEmpty) ? null : tag,
        startTimeSec: startTimeSec,
        endTimeSecExclusive: endTimeSecExclusive,
        limit: 5,
      );
      final previewUids = previewRows
          .map((row) => row['uid'])
          .whereType<String>()
          .toList(growable: false);
      _ref
          .read(logManagerProvider)
          .info(
            'Memos list: empty_view_diagnostic',
            context: <String, Object?>{
              'queryKey': queryKey,
              'state': state,
              'providerCount': providerCount,
              'animatedCount': animatedCount,
              'searchLength': normalizedSearch.length,
              if (tag != null && tag.isNotEmpty) 'tag': tag,
              'useShortcutFilter': useShortcutFilter,
              if (shortcutFilter.trim().isNotEmpty)
                'shortcutFilter': shortcutFilter.trim(),
              'useQuickSearch': useQuickSearch,
              if (quickSearchKind != null)
                'quickSearchKind': quickSearchKind.name,
              'useRemoteSearch': useRemoteSearch,
              if (startTimeSec != null) 'startTimeSec': startTimeSec,
              if (endTimeSecExclusive != null)
                'endTimeSecExclusive': endTimeSecExclusive,
              'dbTotal': allRows.length,
              'dbNormal': dbNormal,
              'dbArchived': dbArchived,
              'dbPreviewCount': previewRows.length,
              if (previewUids.isNotEmpty) 'dbPreviewUids': previewUids,
            },
          );
    } catch (e, stackTrace) {
      _ref
          .read(logManagerProvider)
          .warn(
            'Memos list: empty_view_diagnostic_failed',
            error: e,
            stackTrace: stackTrace,
            context: <String, Object?>{'queryKey': queryKey},
          );
    }
  }

  Future<void> createQuickInputMemo({
    required String uid,
    required String content,
    required String visibility,
    required int nowSec,
    required List<String> tags,
  }) async {
    final db = _ref.read(databaseProvider);
    await db.upsertMemo(
      uid: uid,
      content: content,
      visibility: visibility,
      pinned: false,
      state: 'NORMAL',
      createTimeSec: nowSec,
      updateTimeSec: nowSec,
      tags: tags,
      attachments: const <Map<String, dynamic>>[],
      location: null,
      relationCount: 0,
      syncState: 1,
    );

    await db.enqueueOutbox(
      type: 'create_memo',
      payload: {
        'uid': uid,
        'content': content,
        'visibility': visibility,
        'pinned': false,
        'has_attachments': false,
      },
    );
  }

  Future<int> retryOutboxErrors({required String memoUid}) async {
    final db = _ref.read(databaseProvider);
    return db.retryOutboxErrors(memoUid: memoUid);
  }

  Future<void> createInlineComposeMemo({
    required String uid,
    required String content,
    required String visibility,
    required int nowSec,
    required List<String> tags,
    required List<Map<String, dynamic>> attachments,
    required MemoLocation? location,
    required List<Map<String, dynamic>> relations,
    required List<MemosListPendingAttachment> pendingAttachments,
  }) async {
    final db = _ref.read(databaseProvider);
    await db.upsertMemo(
      uid: uid,
      content: content,
      visibility: visibility,
      pinned: false,
      state: 'NORMAL',
      createTimeSec: nowSec,
      updateTimeSec: nowSec,
      tags: tags,
      attachments: attachments,
      location: location,
      relationCount: 0,
      syncState: 1,
    );

    final hasAttachments = pendingAttachments.isNotEmpty;
    await db.enqueueOutbox(
      type: 'create_memo',
      payload: {
        'uid': uid,
        'content': content,
        'visibility': visibility,
        'pinned': false,
        'has_attachments': hasAttachments,
        if (location != null) 'location': location.toJson(),
        if (relations.isNotEmpty) 'relations': relations,
      },
    );

    for (final attachment in pendingAttachments) {
      await db.enqueueOutbox(
        type: 'upload_attachment',
        payload: {
          'uid': attachment.uid,
          'memo_uid': uid,
          'file_path': attachment.filePath,
          'filename': attachment.filename,
          'mime_type': attachment.mimeType,
          'file_size': attachment.size,
        },
      );
    }
  }

  Future<void> updateMemo(
    LocalMemo memo, {
    bool? pinned,
    String? state,
  }) async {
    final now = DateTime.now();
    final db = _ref.read(databaseProvider);

    await db.upsertMemo(
      uid: memo.uid,
      content: memo.content,
      visibility: memo.visibility,
      pinned: pinned ?? memo.pinned,
      state: state ?? memo.state,
      createTimeSec: memo.createTime.toUtc().millisecondsSinceEpoch ~/ 1000,
      updateTimeSec: now.toUtc().millisecondsSinceEpoch ~/ 1000,
      tags: memo.tags,
      attachments: memo.attachments
          .map((a) => a.toJson())
          .toList(growable: false),
      location: memo.location,
      relationCount: memo.relationCount,
      syncState: 1,
      lastError: null,
    );

    await db.enqueueOutbox(
      type: 'update_memo',
      payload: {
        'uid': memo.uid,
        if (pinned != null) 'pinned': pinned,
        if (state != null) 'state': state,
      },
    );
  }

  Future<void> updateMemoContent(
    LocalMemo memo,
    String content, {
    bool preserveUpdateTime = false,
  }) async {
    if (content == memo.content) return;
    final updateTime = preserveUpdateTime ? memo.updateTime : DateTime.now();
    final db = _ref.read(databaseProvider);
    final timelineService = _ref.read(memoTimelineServiceProvider);
    final tags = extractTags(content);

    await timelineService.captureMemoVersion(memo);

    await db.upsertMemo(
      uid: memo.uid,
      content: content,
      visibility: memo.visibility,
      pinned: memo.pinned,
      state: memo.state,
      createTimeSec: memo.createTime.toUtc().millisecondsSinceEpoch ~/ 1000,
      updateTimeSec: updateTime.toUtc().millisecondsSinceEpoch ~/ 1000,
      tags: tags,
      attachments: memo.attachments
          .map((a) => a.toJson())
          .toList(growable: false),
      location: memo.location,
      relationCount: memo.relationCount,
      syncState: 1,
      lastError: null,
    );

    await db.enqueueOutbox(
      type: 'update_memo',
      payload: {
        'uid': memo.uid,
        'content': content,
        'visibility': memo.visibility,
      },
    );
  }

  Future<void> deleteMemo(
    LocalMemo memo, {
    void Function()? onMovedToRecycleBin,
  }) async {
    final db = _ref.read(databaseProvider);
    final timelineService = _ref.read(memoTimelineServiceProvider);
    await timelineService.moveMemoToRecycleBin(memo);
    onMovedToRecycleBin?.call();
    await db.deleteMemoByUid(memo.uid);
    await db.enqueueOutbox(
      type: 'delete_memo',
      payload: {'uid': memo.uid, 'force': false},
    );
    await _ref.read(reminderSchedulerProvider).rescheduleAll();
  }

  Future<bool> hasAnyLocalMemos() async {
    final db = _ref.read(databaseProvider);
    final existing = await db.listMemos(limit: 1);
    return existing.isNotEmpty;
  }

  Future<MemosListMemoResolveResult> resolveMemoForOpen({
    required String uid,
  }) async {
    final db = _ref.read(databaseProvider);
    final row = await db.getMemoByUid(uid);
    LocalMemo? memo = row == null ? null : LocalMemo.fromDb(row);

    if (memo == null) {
      final account = _ref.read(appSessionProvider).valueOrNull?.currentAccount;
      if (account != null) {
        try {
          final api = _ref.read(memosApiProvider);
          final remote = await api.getMemo(memoUid: uid);
          final remoteUid = remote.uid.isNotEmpty ? remote.uid : uid;
          await db.upsertMemo(
            uid: remoteUid,
            content: remote.content,
            visibility: remote.visibility,
            pinned: remote.pinned,
            state: remote.state,
            createTimeSec:
                remote.createTime.toUtc().millisecondsSinceEpoch ~/ 1000,
            updateTimeSec:
                remote.updateTime.toUtc().millisecondsSinceEpoch ~/ 1000,
            tags: remote.tags,
            attachments: remote.attachments
                .map((a) => a.toJson())
                .toList(growable: false),
            location: remote.location,
            relationCount: countReferenceRelations(
              memoUid: remoteUid,
              relations: remote.relations,
            ),
            syncState: 0,
          );
          final refreshed = await db.getMemoByUid(remoteUid);
          if (refreshed != null) {
            memo = LocalMemo.fromDb(refreshed);
          }
        } catch (e) {
          return MemosListMemoResolveResult.error(e);
        }
      }
    }

    if (memo == null) {
      return const MemosListMemoResolveResult.notFound();
    }
    return MemosListMemoResolveResult.found(memo);
  }

  Future<Shortcut> createShortcut({
    required String title,
    required String filter,
  }) async {
    final account = _ref.read(appSessionProvider).valueOrNull?.currentAccount;
    if (account == null) {
      throw StateError('Not authenticated');
    }
    final api = _ref.read(memosApiProvider);
    await api.ensureServerHintsLoaded();
    final useLocalShortcuts =
        api.usesLegacySearchFilterDialect || api.shortcutsSupportedHint == false;
    return useLocalShortcuts
        ? await _ref
              .read(localShortcutsRepositoryProvider)
              .create(title: title, filter: filter)
        : await api.createShortcut(
            userName: account.user.name,
            title: title,
            filter: filter,
          );
  }
}

Map<String, dynamic> _decodeOutboxPayload(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
  } catch (_) {}
  return <String, dynamic>{};
}

String? _extractOutboxMemoUid(String type, Map<String, dynamic> payload) {
  return switch (type) {
    'create_memo' ||
    'update_memo' ||
    'delete_memo' => payload['uid'] as String?,
    'upload_attachment' ||
    'delete_attachment' => payload['memo_uid'] as String?,
    _ => null,
  };
}

String _apiVersionBandLabel(MemosVersionNumber? version) {
  if (version == null) return '-';
  if (version.major == 0 && version.minor >= 20 && version.minor < 30) {
    return '0.2x';
  }
  return '${version.major}.${version.minor}x';
}

String _buildDebugApiVersionText(MemosVersionResolution? resolution) {
  if (resolution == null) return 'API -';
  final band = _apiVersionBandLabel(resolution.parsedVersion);
  final effective = resolution.effectiveVersion.trim();
  if (effective.isEmpty) return 'API $band';
  return 'API $band ($effective)';
}
