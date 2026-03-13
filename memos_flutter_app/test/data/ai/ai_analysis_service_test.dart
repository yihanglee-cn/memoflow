import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/data/ai/ai_analysis_models.dart';
import 'package:memos_flutter_app/data/ai/ai_analysis_repository.dart';
import 'package:memos_flutter_app/data/ai/ai_analysis_service.dart';
import 'package:memos_flutter_app/data/ai/ai_task_runtime.dart';
import 'package:memos_flutter_app/data/models/app_preferences.dart';
import 'package:memos_flutter_app/data/repositories/ai_settings_repository.dart';

class _FakeAiAnalysisRepository implements AiAnalysisRepository {
  _FakeAiAnalysisRepository(this._memoRows);

  final List<Map<String, dynamic>> _memoRows;
  final List<Map<String, dynamic>> _jobs = <Map<String, dynamic>>[];
  int _nextJobId = 1;
  int _nextChunkId = 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<List<Map<String, dynamic>>> listMemoRowsForAi({
    int? startTimeSec,
    int? endTimeSecExclusive,
    bool includeArchived = false,
  }) async {
    return _memoRows;
  }

  @override
  Future<bool> memoHasFreshIndex({
    required String memoUid,
    required String memoContentHash,
    required String baseUrl,
    required String model,
  }) async {
    return false;
  }

  @override
  Future<int> enqueueIndexJob({
    required String? memoUid,
    required AiIndexJobReason reason,
    required String memoContentHash,
    required String embeddingProfileKey,
    int priority = 100,
  }) async {
    final jobId = _nextJobId++;
    _jobs.add(<String, dynamic>{
      'id': jobId,
      'memo_uid': memoUid,
      'attempt_count': 0,
      'embedding_profile_key': embeddingProfileKey,
      'status': AiIndexJobStatus.queued,
    });
    return jobId;
  }

  @override
  Future<List<Map<String, dynamic>>> listPendingIndexJobs({
    required String embeddingProfileKey,
    int limit = 50,
  }) async {
    return _jobs
        .where(
          (job) =>
              job['embedding_profile_key'] == embeddingProfileKey &&
              (job['status'] == AiIndexJobStatus.queued ||
                  job['status'] == AiIndexJobStatus.failed),
        )
        .take(limit)
        .map((job) => Map<String, dynamic>.from(job))
        .toList(growable: false);
  }

  @override
  Future<void> updateIndexJobStatus(
    int jobId, {
    required AiIndexJobStatus status,
    int? attemptCount,
    String? errorText,
    bool markStarted = false,
    bool markFinished = false,
  }) async {
    final job = _jobs.firstWhere((item) => item['id'] == jobId);
    job['status'] = status;
    if (attemptCount != null) {
      job['attempt_count'] = attemptCount;
    }
    job['error_text'] = errorText;
  }

  @override
  Future<Map<String, dynamic>?> getMemoRowForAi(String memoUid) async {
    for (final row in _memoRows) {
      if (row['uid'] == memoUid) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<void> invalidateActiveChunksForMemo(String memoUid) async {}

  @override
  Future<List<int>> insertActiveChunks({
    required String memoUid,
    required List<AiChunkDraft> chunks,
  }) async {
    return List<int>.generate(chunks.length, (_) => _nextChunkId++);
  }

  @override
  Future<void> insertEmbeddingRecord({
    required int chunkId,
    required AiEmbeddingProfile profile,
    required AiEmbeddingStatus status,
    Float32List? vector,
    String? errorText,
  }) async {}
}

class _FailingEmbeddingRuntime extends AiTaskRuntime {
  _FailingEmbeddingRuntime() : super(registry: AiProviderRegistry.defaults());

  int embedCalls = 0;

  @override
  AiResolvedTaskRoute? resolveEmbeddingRoute(AiSettings settings) {
    return AiRouteResolver.resolveTaskRoute(
      services: settings.services,
      bindings: settings.taskRouteBindings,
      routeId: AiTaskRouteId.embeddingRetrieval,
      capability: AiCapability.embedding,
    );
  }

  @override
  Future<List<double>> embed({
    required AiSettings settings,
    required String input,
  }) async {
    embedCalls += 1;
    throw StateError(
      'Unsupported model `qwen3-vl-embedding` for OpenAI compatibility mode.',
    );
  }
}

void main() {
  test('looksLikeGeneratedAiSummaryMemo detects saved letter memos', () {
    expect(
      looksLikeGeneratedAiSummaryMemo(
        '# Letter Back\n2026-02-01 — 2026-03-12\n\nThis letter drew on these note fragments:\n- "A quoted line"',
      ),
      isTrue,
    );
    expect(
      looksLikeGeneratedAiSummaryMemo(
        'Met a friend for coffee and took a long walk today.',
      ),
      isFalse,
    );
  });

  test('buildEmotionMapPreview ignores saved AI letter memos', () async {
    final now = DateTime.utc(2026, 3, 11);
    final timestamp = now.millisecondsSinceEpoch ~/ 1000;
    final repository = _FakeAiAnalysisRepository(<Map<String, dynamic>>[
      <String, dynamic>{
        'uid': 'memo_note',
        'content':
            'Met a friend for coffee and felt much calmer after the walk.',
        'visibility': 'PRIVATE',
        'allow_ai': 1,
        'state': 'NORMAL',
        'create_time': timestamp,
        'update_time': timestamp,
      },
      <String, dynamic>{
        'uid': 'memo_ai_letter',
        'content':
            '# Letter Back\n2026-02-01 — 2026-03-11\n\nThis letter drew on these note fragments:\n- "A quoted line"',
        'visibility': 'PRIVATE',
        'allow_ai': 1,
        'state': 'NORMAL',
        'create_time': timestamp,
        'update_time': timestamp,
      },
    ]);
    final service = AiAnalysisService(repository: repository);

    final payload = await service.buildEmotionMapPreview(
      language: AppLanguage.en,
      settings: AiSettings.defaultsFor(AppLanguage.en),
      range: DateTimeRange(start: now, end: now),
      includePrivate: true,
    );

    expect(payload.totalMatchingMemos, 1);
  });

  test(
    'buildEmotionMapPreview stops after five consecutive embedding failures',
    () async {
      final runtime = _FailingEmbeddingRuntime();
      final now = DateTime.utc(2026, 3, 11);
      final timestamp = now.millisecondsSinceEpoch ~/ 1000;
      final memoRows = List<Map<String, dynamic>>.generate(
        10,
        (index) => <String, dynamic>{
          'uid': 'memo_$index',
          'content': 'Memo content $index',
          'visibility': 'PRIVATE',
          'allow_ai': 1,
          'state': 'NORMAL',
          'create_time': timestamp,
          'update_time': timestamp,
        },
      );
      final repository = _FakeAiAnalysisRepository(memoRows);
      const embeddingService = AiServiceInstance(
        serviceId: 'svc_embed',
        templateId: aiTemplateCustomOpenAi,
        adapterKind: AiProviderAdapterKind.openAiCompatible,
        displayName: 'Embedding Service',
        enabled: true,
        baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        apiKey: 'test-key',
        customHeaders: <String, String>{},
        models: <AiModelEntry>[
          AiModelEntry(
            modelId: 'mdl_embed',
            displayName: 'qwen3-vl-embedding',
            modelKey: 'qwen3-vl-embedding',
            capabilities: <AiCapability>[AiCapability.embedding],
            source: AiModelSource.manual,
            enabled: true,
          ),
        ],
        lastValidatedAt: null,
        lastValidationStatus: AiValidationStatus.unknown,
        lastValidationMessage: null,
      );
      final settings = AiSettings.defaultsFor(AppLanguage.en).copyWith(
        services: const <AiServiceInstance>[embeddingService],
        taskRouteBindings: const <AiTaskRouteBinding>[
          AiTaskRouteBinding(
            routeId: AiTaskRouteId.embeddingRetrieval,
            serviceId: 'svc_embed',
            modelId: 'mdl_embed',
            capability: AiCapability.embedding,
          ),
        ],
        generationProfiles: const <AiGenerationProfile>[
          AiGenerationProfile.unconfigured,
        ],
        selectedGenerationProfileKey: '',
        embeddingProfiles: const <AiEmbeddingProfile>[
          AiEmbeddingProfile(
            profileKey: 'embed_profile',
            displayName: 'Embedding Service',
            backendKind: AiBackendKind.remoteApi,
            providerKind: AiProviderKind.openAiCompatible,
            baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
            apiKey: 'test-key',
            model: 'qwen3-vl-embedding',
            enabled: true,
          ),
        ],
        selectedEmbeddingProfileKey: 'embed_profile',
      );
      final service = AiAnalysisService(
        repository: repository,
        runtime: runtime,
      );

      final future = service.buildEmotionMapPreview(
        language: AppLanguage.en,
        settings: settings,
        range: DateTimeRange(start: now, end: now),
        includePrivate: true,
      );

      await expectLater(
        future,
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('failed 5 times in a row'),
          ),
        ),
      );
      expect(runtime.embedCalls, 5);
    },
  );
}
