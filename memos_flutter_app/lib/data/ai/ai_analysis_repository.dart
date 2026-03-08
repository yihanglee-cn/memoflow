import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import 'ai_analysis_models.dart';
import '../repositories/ai_settings_repository.dart';

class AiAnalysisRepository {
  AiAnalysisRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  Future<Database> get _db => _appDatabase.db;

  Future<void> upsertMemoPolicy({
    required String memoUid,
    required bool allowAi,
  }) async {
    final trimmedUid = memoUid.trim();
    if (trimmedUid.isEmpty) return;
    final db = await _db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.insert('ai_memo_policy', <String, Object?>{
      'memo_uid': trimmedUid,
      'allow_ai': allowAi ? 1 : 0,
      'updated_time': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> getMemoAllowAi(String memoUid) async {
    final trimmedUid = memoUid.trim();
    if (trimmedUid.isEmpty) return true;
    final db = await _db;
    final rows = await db.query(
      'ai_memo_policy',
      columns: const ['allow_ai'],
      where: 'memo_uid = ?',
      whereArgs: <Object?>[trimmedUid],
      limit: 1,
    );
    if (rows.isEmpty) return true;
    return ((rows.first['allow_ai'] as int?) ?? 1) == 1;
  }

  Future<List<Map<String, dynamic>>> listMemoRowsForAi({
    int? startTimeSec,
    int? endTimeSecExclusive,
    bool includeArchived = false,
  }) async {
    final db = await _db;
    final whereClauses = <String>[];
    final whereArgs = <Object?>[];
    if (!includeArchived) {
      whereClauses.add("m.state = 'NORMAL'");
    }
    if (startTimeSec != null) {
      whereClauses.add('m.create_time >= ?');
      whereArgs.add(startTimeSec);
    }
    if (endTimeSecExclusive != null) {
      whereClauses.add('m.create_time < ?');
      whereArgs.add(endTimeSecExclusive);
    }
    final whereSql = whereClauses.isEmpty
        ? ''
        : 'WHERE ${whereClauses.join(' AND ')}';
    return db.rawQuery('''
SELECT m.*, COALESCE(p.allow_ai, 1) AS allow_ai
FROM memos m
LEFT JOIN ai_memo_policy p ON p.memo_uid = m.uid
$whereSql
ORDER BY m.create_time DESC, m.id DESC;
''', whereArgs);
  }

  Future<Map<String, dynamic>?> getMemoRowForAi(String memoUid) async {
    final trimmedUid = memoUid.trim();
    if (trimmedUid.isEmpty) return null;
    final db = await _db;
    final rows = await db.rawQuery(
      '''
SELECT m.*, COALESCE(p.allow_ai, 1) AS allow_ai
FROM memos m
LEFT JOIN ai_memo_policy p ON p.memo_uid = m.uid
WHERE m.uid = ?
LIMIT 1;
''',
      <Object?>[trimmedUid],
    );
    return rows.firstOrNull;
  }

  Future<int> enqueueIndexJob({
    required String? memoUid,
    required AiIndexJobReason reason,
    required String memoContentHash,
    required String embeddingProfileKey,
    int priority = 100,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return db.insert('ai_index_jobs', <String, Object?>{
      'memo_uid': memoUid?.trim(),
      'reason': aiIndexJobReasonToStorage(reason),
      'memo_content_hash': memoContentHash,
      'embedding_profile_key': embeddingProfileKey,
      'status': aiIndexJobStatusToStorage(AiIndexJobStatus.queued),
      'attempt_count': 0,
      'priority': priority,
      'created_time': now,
    });
  }

  Future<List<Map<String, dynamic>>> listPendingIndexJobs({
    required String embeddingProfileKey,
    int limit = 50,
  }) async {
    final db = await _db;
    return db.query(
      'ai_index_jobs',
      where: 'embedding_profile_key = ? AND status IN (?, ?)',
      whereArgs: <Object?>[
        embeddingProfileKey,
        aiIndexJobStatusToStorage(AiIndexJobStatus.queued),
        aiIndexJobStatusToStorage(AiIndexJobStatus.failed),
      ],
      orderBy: 'priority ASC, created_time ASC, id ASC',
      limit: limit,
    );
  }

  Future<void> updateIndexJobStatus(
    int jobId, {
    required AiIndexJobStatus status,
    int? attemptCount,
    String? errorText,
    bool markStarted = false,
    bool markFinished = false,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'status': aiIndexJobStatusToStorage(status),
      'error_text': errorText,
    };
    if (attemptCount != null) {
      values['attempt_count'] = attemptCount;
    }
    if (markStarted) {
      values['started_time'] = now;
    }
    if (markFinished) {
      values['finished_time'] = now;
    }
    await db.update(
      'ai_index_jobs',
      values,
      where: 'id = ?',
      whereArgs: <Object?>[jobId],
    );
  }

  Future<void> invalidateActiveChunksForMemo(String memoUid) async {
    final trimmedUid = memoUid.trim();
    if (trimmedUid.isEmpty) return;
    final db = await _db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'ai_chunks',
        columns: const ['id'],
        where: 'memo_uid = ? AND is_active = 1',
        whereArgs: <Object?>[trimmedUid],
      );
      final chunkIds = rows
          .map((row) => row['id'] as int?)
          .whereType<int>()
          .toList(growable: false);
      await txn.update(
        'ai_chunks',
        <String, Object?>{
          'is_active': 0,
          'invalidated_time': now,
          'updated_time': now,
        },
        where: 'memo_uid = ? AND is_active = 1',
        whereArgs: <Object?>[trimmedUid],
      );
      if (chunkIds.isNotEmpty) {
        final placeholders = List.filled(chunkIds.length, '?').join(', ');
        await txn.rawUpdate(
          'UPDATE ai_embeddings SET status = ?, updated_time = ? WHERE chunk_id IN ($placeholders) AND status != ?',
          <Object?>[
            aiEmbeddingStatusToStorage(AiEmbeddingStatus.stale),
            now,
            ...chunkIds,
            aiEmbeddingStatusToStorage(AiEmbeddingStatus.stale),
          ],
        );
      }
    });
    await markResultsStaleForMemo(trimmedUid);
  }

  Future<List<Map<String, dynamic>>> listActiveChunkRowsForMemo(
    String memoUid,
  ) async {
    final trimmedUid = memoUid.trim();
    if (trimmedUid.isEmpty) return const <Map<String, dynamic>>[];
    final db = await _db;
    return db.query(
      'ai_chunks',
      where: 'memo_uid = ? AND is_active = 1',
      whereArgs: <Object?>[trimmedUid],
      orderBy: 'chunk_index ASC, id ASC',
    );
  }

  Future<bool> memoHasFreshIndex({
    required String memoUid,
    required String memoContentHash,
    required String baseUrl,
    required String model,
  }) async {
    final activeRows = await listActiveChunkRowsForMemo(memoUid);
    if (activeRows.isEmpty) return false;
    for (final row in activeRows) {
      if (((row['memo_content_hash'] as String?) ?? '') != memoContentHash) {
        return false;
      }
    }
    final db = await _db;
    for (final row in activeRows) {
      final chunkId = row['id'] as int?;
      if (chunkId == null) return false;
      final embeddings = await db.query(
        'ai_embeddings',
        columns: const ['status'],
        where: 'chunk_id = ? AND base_url = ? AND model = ?',
        whereArgs: <Object?>[chunkId, baseUrl, model],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (embeddings.isEmpty) return false;
      final status = aiEmbeddingStatusFromStorage(
        (embeddings.first['status'] as String?) ?? 'failed',
      );
      if (status != AiEmbeddingStatus.ready) return false;
    }
    return true;
  }

  Future<List<int>> insertActiveChunks({
    required String memoUid,
    required List<AiChunkDraft> chunks,
  }) async {
    final trimmedUid = memoUid.trim();
    if (trimmedUid.isEmpty || chunks.isEmpty) return const <int>[];
    final db = await _db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final ids = <int>[];
    await db.transaction((txn) async {
      for (final chunk in chunks) {
        final id = await txn.insert('ai_chunks', <String, Object?>{
          'memo_uid': trimmedUid,
          'chunk_index': chunk.chunkIndex,
          'content': chunk.content,
          'content_hash': chunk.contentHash,
          'memo_content_hash': chunk.memoContentHash,
          'char_start': chunk.charStart,
          'char_end': chunk.charEnd,
          'token_estimate': chunk.tokenEstimate,
          'memo_create_time': chunk.memoCreateTime,
          'memo_update_time': chunk.memoUpdateTime,
          'memo_visibility': chunk.memoVisibility,
          'is_active': 1,
          'created_time': now,
          'updated_time': now,
        });
        ids.add(id);
      }
    });
    return ids;
  }

  Future<void> insertEmbeddingRecord({
    required int chunkId,
    required AiEmbeddingProfile profile,
    required AiEmbeddingStatus status,
    Float32List? vector,
    String? errorText,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    Uint8List? vectorBlob;
    var dimensions = 0;
    if (vector != null && vector.isNotEmpty) {
      vectorBlob = vector.buffer.asUint8List(
        vector.offsetInBytes,
        vector.lengthInBytes,
      );
      dimensions = vector.length;
    }
    await db.insert('ai_embeddings', <String, Object?>{
      'chunk_id': chunkId,
      'backend_kind': _backendKindToStorage(profile.backendKind),
      'provider_kind': _providerKindToStorage(profile.providerKind),
      'base_url': profile.baseUrl,
      'model': profile.model,
      'model_version': '',
      'dimensions': dimensions,
      'vector_blob': vectorBlob,
      'status': aiEmbeddingStatusToStorage(status),
      'error_text': errorText,
      'created_time': now,
      'updated_time': now,
    });
  }

  Future<Map<String, dynamic>> countCandidateChunkStatuses({
    required int startTimeSec,
    required int endTimeSecExclusive,
    required bool includePublic,
    required bool includePrivate,
    required bool includeProtected,
    required String baseUrl,
    required String model,
  }) async {
    final db = await _db;
    final visibilityClauses = <String>[];
    if (!includePublic) {
      visibilityClauses.add("c.memo_visibility != 'PUBLIC'");
    }
    if (!includePrivate) {
      visibilityClauses.add("c.memo_visibility != 'PRIVATE'");
    }
    if (!includeProtected) {
      visibilityClauses.add("c.memo_visibility != 'PROTECTED'");
    }
    final visibilitySql = visibilityClauses.isEmpty
        ? ''
        : 'AND ${visibilityClauses.join(' AND ')}';
    final rows = await db.rawQuery(
      '''
SELECT
  COUNT(DISTINCT c.memo_uid) AS memo_count,
  COUNT(*) AS chunk_count,
  SUM(CASE WHEN e.status = 'ready' THEN 1 ELSE 0 END) AS ready_count,
  SUM(CASE WHEN e.status = 'pending' THEN 1 ELSE 0 END) AS pending_count,
  SUM(CASE WHEN e.status = 'failed' THEN 1 ELSE 0 END) AS failed_count
FROM ai_chunks c
LEFT JOIN ai_memo_policy p ON p.memo_uid = c.memo_uid
LEFT JOIN ai_embeddings e
  ON e.chunk_id = c.id
 AND e.base_url = ?
 AND e.model = ?
WHERE c.is_active = 1
  AND c.memo_create_time >= ?
  AND c.memo_create_time < ?
  AND COALESCE(p.allow_ai, 1) = 1
  $visibilitySql;
''',
      <Object?>[baseUrl, model, startTimeSec, endTimeSecExclusive],
    );
    return rows.firstOrNull ?? const <String, Object?>{};
  }

  Future<List<Map<String, dynamic>>> listCandidateChunkRows({
    required int startTimeSec,
    required int endTimeSecExclusive,
    required bool includePublic,
    required bool includePrivate,
    required bool includeProtected,
    required String baseUrl,
    required String model,
    int limit = 3000,
  }) async {
    final db = await _db;
    final whereClauses = <String>[
      'c.is_active = 1',
      'c.memo_create_time >= ?',
      'c.memo_create_time < ?',
      'COALESCE(p.allow_ai, 1) = 1',
    ];
    final args = <Object?>[startTimeSec, endTimeSecExclusive];
    if (!includePublic) {
      whereClauses.add("c.memo_visibility != 'PUBLIC'");
    }
    if (!includePrivate) {
      whereClauses.add("c.memo_visibility != 'PRIVATE'");
    }
    if (!includeProtected) {
      whereClauses.add("c.memo_visibility != 'PROTECTED'");
    }
    final rows = await db.rawQuery(
      '''
SELECT
  c.*, 
  e.id AS embedding_id,
  e.status AS embedding_status,
  e.vector_blob,
  e.dimensions,
  e.error_text
FROM ai_chunks c
LEFT JOIN ai_memo_policy p ON p.memo_uid = c.memo_uid
LEFT JOIN ai_embeddings e
  ON e.chunk_id = c.id
 AND e.base_url = ?
 AND e.model = ?
WHERE ${whereClauses.join(' AND ')}
ORDER BY c.memo_create_time DESC, c.chunk_index ASC
LIMIT ?;
''',
      <Object?>[baseUrl, model, ...args, limit],
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> listPreviewSampleChunks({
    required int startTimeSec,
    required int endTimeSecExclusive,
    required bool includePublic,
    required bool includePrivate,
    required bool includeProtected,
    required String baseUrl,
    required String model,
    int limit = 5,
  }) async {
    final rows = await listCandidateChunkRows(
      startTimeSec: startTimeSec,
      endTimeSecExclusive: endTimeSecExclusive,
      includePublic: includePublic,
      includePrivate: includePrivate,
      includeProtected: includeProtected,
      baseUrl: baseUrl,
      model: model,
      limit: limit,
    );
    return rows;
  }

  Future<int> createAnalysisTask({
    required String taskUid,
    required AiAnalysisType analysisType,
    required AiTaskStatus status,
    required int rangeStart,
    required int rangeEndExclusive,
    required bool includePrivate,
    required bool includeProtected,
    required String promptTemplate,
    required String generationProfileKey,
    required String embeddingProfileKey,
    required Map<String, dynamic> retrievalProfile,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return db.insert('ai_analysis_tasks', <String, Object?>{
      'task_uid': taskUid,
      'analysis_type': aiAnalysisTypeToStorage(analysisType),
      'status': aiTaskStatusToStorage(status),
      'range_start': rangeStart,
      'range_end_exclusive': rangeEndExclusive,
      'include_private': includePrivate ? 1 : 0,
      'include_protected': includeProtected ? 1 : 0,
      'prompt_template': promptTemplate,
      'generation_profile_key': generationProfileKey,
      'embedding_profile_key': embeddingProfileKey,
      'retrieval_profile_json': jsonEncode(retrievalProfile),
      'mailbox_delivery_state': 'hidden',
      'mailbox_open_state': 'unread',
      'reply_animation_state': 'idle',
      'created_time': now,
      'updated_time': now,
    });
  }

  Future<void> updateAnalysisTaskStatus(
    int taskId, {
    required AiTaskStatus status,
    String? errorText,
    bool markCompleted = false,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.update(
      'ai_analysis_tasks',
      <String, Object?>{
        'status': aiTaskStatusToStorage(status),
        'error_text': errorText,
        'updated_time': now,
        if (markCompleted) 'completed_time': now,
      },
      where: 'id = ?',
      whereArgs: <Object?>[taskId],
    );
  }

  Future<void> saveAnalysisResult({
    required int taskId,
    required AiStructuredAnalysisResult result,
  }) async {
    final db = await _db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final resultId = await txn.insert(
        'ai_analysis_results',
        <String, Object?>{
          'task_id': taskId,
          'schema_version': result.schemaVersion,
          'analysis_type': aiAnalysisTypeToStorage(result.analysisType),
          'summary': result.summary,
          'follow_up_suggestions_json': jsonEncode(result.followUpSuggestions),
          'raw_response_text': result.rawResponseText,
          'normalized_result_json': result.normalizedResultJson,
          'is_stale': 0,
          'created_time': now,
          'updated_time': now,
        },
      );
      final sectionIdByKey = <String, int>{};
      for (var index = 0; index < result.sections.length; index++) {
        final section = result.sections[index];
        final sectionId = await txn
            .insert('ai_analysis_sections', <String, Object?>{
              'result_id': resultId,
              'section_key': section.sectionKey,
              'section_order': index,
              'title': section.title,
              'body': section.body,
              'created_time': now,
            });
        sectionIdByKey[section.sectionKey] = sectionId;
      }
      for (var index = 0; index < result.evidences.length; index++) {
        final evidence = result.evidences[index];
        final sectionId = sectionIdByKey[evidence.sectionKey];
        if (sectionId == null) continue;
        await txn.insert('ai_analysis_evidences', <String, Object?>{
          'result_id': resultId,
          'section_id': sectionId,
          'evidence_order': index,
          'memo_uid': evidence.memoUid,
          'chunk_id': evidence.chunkId,
          'quote_text': evidence.quoteText,
          'char_start': evidence.charStart,
          'char_end': evidence.charEnd,
          'relevance_score': evidence.relevanceScore,
          'created_time': now,
        });
      }
    });
  }

  Future<void> markResultsStaleForMemo(String memoUid) async {
    final trimmedUid = memoUid.trim();
    if (trimmedUid.isEmpty) return;
    final db = await _db;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.rawUpdate(
      '''
UPDATE ai_analysis_results
SET is_stale = 1,
    updated_time = ?
WHERE id IN (
  SELECT DISTINCT result_id
  FROM ai_analysis_evidences
  WHERE memo_uid = ?
);
''',
      <Object?>[now, trimmedUid],
    );
  }

  Future<AiSavedAnalysisReport?> loadLatestAnalysisReport({
    required AiAnalysisType analysisType,
  }) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
SELECT
  t.id AS task_id,
  t.task_uid,
  t.status,
  r.id AS result_id,
  r.summary,
  r.follow_up_suggestions_json,
  r.is_stale
FROM ai_analysis_tasks t
JOIN ai_analysis_results r ON r.task_id = t.id
WHERE t.analysis_type = ?
ORDER BY t.created_time DESC
LIMIT 1;
''',
      <Object?>[aiAnalysisTypeToStorage(analysisType)],
    );
    final taskRow = rows.firstOrNull;
    if (taskRow == null) return null;
    final taskId = (taskRow['task_id'] as int?) ?? 0;
    final resultId = (taskRow['result_id'] as int?) ?? 0;
    final sectionRows = await db.query(
      'ai_analysis_sections',
      where: 'result_id = ?',
      whereArgs: <Object?>[resultId],
      orderBy: 'section_order ASC, id ASC',
    );
    final evidenceRows = await db.query(
      'ai_analysis_evidences',
      where: 'result_id = ?',
      whereArgs: <Object?>[resultId],
      orderBy: 'section_id ASC, evidence_order ASC, id ASC',
    );
    final sectionIdToKey = <int, String>{
      for (final row in sectionRows)
        ((row['id'] as int?) ?? 0): ((row['section_key'] as String?) ?? ''),
    };
    final sections = sectionRows
        .map((row) {
          final sectionId = (row['id'] as int?) ?? 0;
          final relatedKeys = evidenceRows
              .where(
                (evidence) =>
                    ((evidence['section_id'] as int?) ?? 0) == sectionId,
              )
              .map((evidence) => 'e${(evidence['id'] as int?) ?? 0}')
              .toList(growable: false);
          return AiAnalysisSectionData(
            sectionKey: (row['section_key'] as String?) ?? '',
            title: (row['title'] as String?) ?? '',
            body: (row['body'] as String?) ?? '',
            evidenceKeys: relatedKeys,
          );
        })
        .toList(growable: false);
    final evidences = <AiAnalysisEvidenceData>[];
    for (final row in evidenceRows) {
      evidences.add(
        AiAnalysisEvidenceData(
          evidenceKey: 'e${(row['id'] as int?) ?? 0}',
          sectionKey: sectionIdToKey[(row['section_id'] as int?) ?? 0] ?? '',
          memoUid: (row['memo_uid'] as String?) ?? '',
          chunkId: (row['chunk_id'] as int?) ?? 0,
          quoteText: (row['quote_text'] as String?) ?? '',
          charStart: (row['char_start'] as int?) ?? 0,
          charEnd: (row['char_end'] as int?) ?? 0,
          relevanceScore: ((row['relevance_score'] as num?) ?? 0).toDouble(),
        ),
      );
    }
    final suggestionsJson =
        (taskRow['follow_up_suggestions_json'] as String?) ?? '[]';
    List<String> suggestions = const <String>[];
    try {
      final decoded = jsonDecode(suggestionsJson);
      if (decoded is List) {
        suggestions = decoded
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return AiSavedAnalysisReport(
      taskId: taskId,
      taskUid: (taskRow['task_uid'] as String?) ?? '',
      status: aiTaskStatusFromStorage(
        (taskRow['status'] as String?) ?? 'failed',
      ),
      summary: (taskRow['summary'] as String?) ?? '',
      sections: sections,
      evidences: evidences,
      followUpSuggestions: suggestions,
      isStale: ((taskRow['is_stale'] as int?) ?? 0) == 1,
    );
  }
}

String _backendKindToStorage(AiBackendKind value) => switch (value) {
  AiBackendKind.remoteApi => 'remote_api',
  AiBackendKind.localApi => 'local_api',
};

String _providerKindToStorage(AiProviderKind value) => switch (value) {
  AiProviderKind.openAiCompatible => 'openai_compatible',
  AiProviderKind.anthropicCompatible => 'anthropic_compatible',
};

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
