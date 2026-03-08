import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/app_localization.dart';
import '../../core/uid.dart';
import '../models/app_preferences.dart';
import '../models/content_fingerprint.dart';
import '../repositories/ai_settings_repository.dart';
import 'ai_analysis_models.dart';
import 'ai_analysis_repository.dart';

class AiAnalysisService {
  AiAnalysisService({required AiAnalysisRepository repository, Dio? dio})
    : _repository = repository,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
              receiveTimeout: const Duration(seconds: 180),
            ),
          );

  static const _candidateChunkLimit = 3000;
  static const _topChunksPerIntent = 8;
  static const _maxMergedChunks = 20;
  static const _maxChunksPerMemo = 3;
  static const _schemaVersion = 1;

  static const _sectionOrder = <String>[
    'emotion_curve',
    'stress_trigger',
    'recovery_signal',
    'relationship_theme',
  ];

  final AiAnalysisRepository _repository;
  final Dio _dio;

  Future<AiRetrievalPreviewPayload> buildEmotionMapPreview({
    required AppLanguage language,
    required AiSettings settings,
    required DateTimeRange range,
    bool includePublic = true,
    required bool includePrivate,
    bool includeProtected = false,
  }) async {
    final startTimeSec = _rangeStart(range);
    final endTimeSecExclusive = _rangeEndExclusive(range);
    final embeddingProfile = _resolveEmbeddingProfile(settings);

    if (embeddingProfile == null ||
        embeddingProfile.baseUrl.trim().isEmpty ||
        embeddingProfile.model.trim().isEmpty) {
      final memoRows = await _repository.listMemoRowsForAi(
        startTimeSec: startTimeSec,
        endTimeSecExclusive: endTimeSecExclusive,
      );
      final filtered = memoRows.where(
        (row) => _memoRowAllowed(
          row,
          includePublic: includePublic,
          includePrivate: includePrivate,
          includeProtected: includeProtected,
        ),
      );
      return AiRetrievalPreviewPayload(
        totalMatchingMemos: filtered.length,
        candidateChunks: 0,
        embeddingReady: 0,
        embeddingPending: 0,
        embeddingFailed: 0,
        isSampled: false,
        items: const <AiRetrievalPreviewItem>[],
      );
    }

    await _ensureIndexesForRange(
      settings: settings,
      profile: embeddingProfile,
      startTimeSec: startTimeSec,
      endTimeSecExclusive: endTimeSecExclusive,
    );

    final counts = await _repository.countCandidateChunkStatuses(
      startTimeSec: startTimeSec,
      endTimeSecExclusive: endTimeSecExclusive,
      includePublic: includePublic,
      includePrivate: includePrivate,
      includeProtected: includeProtected,
      baseUrl: embeddingProfile.baseUrl,
      model: embeddingProfile.model,
    );
    final sampleRows = await _repository.listPreviewSampleChunks(
      startTimeSec: startTimeSec,
      endTimeSecExclusive: endTimeSecExclusive,
      includePublic: includePublic,
      includePrivate: includePrivate,
      includeProtected: includeProtected,
      baseUrl: embeddingProfile.baseUrl,
      model: embeddingProfile.model,
      limit: 5,
    );

    final items = sampleRows
        .map((row) => _previewItemFromRow(row))
        .toList(growable: false);
    final candidateChunks = (counts['chunk_count'] as int?) ?? 0;
    return AiRetrievalPreviewPayload(
      totalMatchingMemos: (counts['memo_count'] as int?) ?? 0,
      candidateChunks: candidateChunks,
      embeddingReady: (counts['ready_count'] as int?) ?? 0,
      embeddingPending: (counts['pending_count'] as int?) ?? 0,
      embeddingFailed: (counts['failed_count'] as int?) ?? 0,
      isSampled: candidateChunks >= _candidateChunkLimit,
      items: items,
    );
  }

  Future<AiSavedAnalysisReport> generateEmotionMap({
    required AppLanguage language,
    required AiSettings settings,
    required DateTimeRange range,
    bool includePublic = true,
    required bool includePrivate,
    bool includeProtected = false,
    String promptTemplate = '',
  }) async {
    final generationProfile = _resolveGenerationProfile(settings);
    final embeddingProfile = _resolveEmbeddingProfile(settings);
    if (generationProfile == null ||
        generationProfile.baseUrl.trim().isEmpty ||
        generationProfile.model.trim().isEmpty) {
      throw StateError(
        trByLanguage(
          language: language,
          zh: '请先配置可用的生成模型。',
          en: 'Please configure a generation model first.',
        ),
      );
    }
    if (embeddingProfile == null ||
        embeddingProfile.baseUrl.trim().isEmpty ||
        embeddingProfile.model.trim().isEmpty) {
      throw StateError(
        trByLanguage(
          language: language,
          zh: '请先配置 embedding provider 和 model。',
          en: 'Please configure an embedding provider and model first.',
        ),
      );
    }

    final startTimeSec = _rangeStart(range);
    final endTimeSecExclusive = _rangeEndExclusive(range);
    await _ensureIndexesForRange(
      settings: settings,
      profile: embeddingProfile,
      startTimeSec: startTimeSec,
      endTimeSecExclusive: endTimeSecExclusive,
    );

    final taskUid = generateUid();
    final taskId = await _repository.createAnalysisTask(
      taskUid: taskUid,
      analysisType: AiAnalysisType.emotionMap,
      status: AiTaskStatus.draft,
      rangeStart: startTimeSec,
      rangeEndExclusive: endTimeSecExclusive,
      includePrivate: includePrivate,
      includeProtected: includeProtected,
      promptTemplate: promptTemplate.trim(),
      generationProfileKey: generationProfile.profileKey,
      embeddingProfileKey: embeddingProfile.profileKey,
      retrievalProfile: <String, dynamic>{
        'candidate_limit': _candidateChunkLimit,
        'top_per_intent': _topChunksPerIntent,
        'max_merged_chunks': _maxMergedChunks,
        'max_chunks_per_memo': _maxChunksPerMemo,
        'include_public': includePublic,
        'include_private': includePrivate,
        'include_protected': includeProtected,
      },
    );

    try {
      await _repository.updateAnalysisTaskStatus(
        taskId,
        status: AiTaskStatus.queued,
      );
      await _repository.updateAnalysisTaskStatus(
        taskId,
        status: AiTaskStatus.retrieving,
      );
      final retrieval = await _retrieveEmotionMapEvidence(
        language: language,
        profile: embeddingProfile,
        startTimeSec: startTimeSec,
        endTimeSecExclusive: endTimeSecExclusive,
        includePublic: includePublic,
        includePrivate: includePrivate,
        includeProtected: includeProtected,
      );
      if (retrieval.candidates.isEmpty) {
        throw StateError(
          trByLanguage(
            language: language,
            zh: '当前时间范围内没有可用于分析的证据片段。',
            en: 'No evidence chunks are available for this analysis range.',
          ),
        );
      }

      await _repository.updateAnalysisTaskStatus(
        taskId,
        status: AiTaskStatus.generating,
      );
      final structured = await _generateEmotionMapResult(
        language: language,
        settings: settings,
        generationProfile: generationProfile,
        candidates: retrieval.candidates,
        promptTemplate: promptTemplate,
        range: range,
      );
      await _repository.saveAnalysisResult(taskId: taskId, result: structured);
      await _repository.updateAnalysisTaskStatus(
        taskId,
        status: AiTaskStatus.completed,
        markCompleted: true,
      );
      return (await _repository.loadLatestAnalysisReport(
            analysisType: AiAnalysisType.emotionMap,
          )) ??
          AiSavedAnalysisReport(
            taskId: taskId,
            taskUid: taskUid,
            status: AiTaskStatus.completed,
            summary: structured.summary,
            sections: structured.sections,
            evidences: structured.evidences,
            followUpSuggestions: structured.followUpSuggestions,
            isStale: false,
          );
    } catch (error) {
      await _repository.updateAnalysisTaskStatus(
        taskId,
        status: AiTaskStatus.failed,
        errorText: error.toString(),
      );
      rethrow;
    }
  }

  Future<void> _ensureIndexesForRange({
    required AiSettings settings,
    required AiEmbeddingProfile profile,
    required int startTimeSec,
    required int endTimeSecExclusive,
  }) async {
    final memoRows = await _repository.listMemoRowsForAi(
      startTimeSec: startTimeSec,
      endTimeSecExclusive: endTimeSecExclusive,
    );
    for (final row in memoRows) {
      final memoUid = (row['uid'] as String?)?.trim() ?? '';
      if (memoUid.isEmpty) continue;
      final allowAi = ((row['allow_ai'] as int?) ?? 1) == 1;
      if (!allowAi) {
        await _repository.invalidateActiveChunksForMemo(memoUid);
        continue;
      }
      final memoContentHash = _computeMemoContentHash(row);
      final hasFreshIndex = await _repository.memoHasFreshIndex(
        memoUid: memoUid,
        memoContentHash: memoContentHash,
        baseUrl: profile.baseUrl,
        model: profile.model,
      );
      if (hasFreshIndex) continue;
      await _repository.enqueueIndexJob(
        memoUid: memoUid,
        reason: AiIndexJobReason.memoUpdated,
        memoContentHash: memoContentHash,
        embeddingProfileKey: profile.profileKey,
      );
    }
    await _processPendingIndexJobs(settings: settings, profile: profile);
  }

  Future<void> _processPendingIndexJobs({
    required AiSettings settings,
    required AiEmbeddingProfile profile,
  }) async {
    final jobs = await _repository.listPendingIndexJobs(
      embeddingProfileKey: profile.profileKey,
      limit: 200,
    );
    for (final job in jobs) {
      final jobId = (job['id'] as int?) ?? 0;
      final memoUid = (job['memo_uid'] as String?)?.trim() ?? '';
      if (jobId <= 0 || memoUid.isEmpty) continue;
      final attemptCount = ((job['attempt_count'] as int?) ?? 0) + 1;
      await _repository.updateIndexJobStatus(
        jobId,
        status: AiIndexJobStatus.running,
        attemptCount: attemptCount,
        markStarted: true,
      );
      try {
        await _rebuildMemoIndex(
          memoUid: memoUid,
          settings: settings,
          profile: profile,
        );
        await _repository.updateIndexJobStatus(
          jobId,
          status: AiIndexJobStatus.completed,
          attemptCount: attemptCount,
          markFinished: true,
        );
      } catch (error) {
        await _repository.updateIndexJobStatus(
          jobId,
          status: AiIndexJobStatus.failed,
          attemptCount: attemptCount,
          errorText: error.toString(),
          markFinished: true,
        );
      }
    }
  }

  Future<void> _rebuildMemoIndex({
    required String memoUid,
    required AiSettings settings,
    required AiEmbeddingProfile profile,
  }) async {
    final memoRow = await _repository.getMemoRowForAi(memoUid);
    if (memoRow == null) {
      await _repository.invalidateActiveChunksForMemo(memoUid);
      return;
    }
    final allowAi = ((memoRow['allow_ai'] as int?) ?? 1) == 1;
    final state =
        (memoRow['state'] as String?)?.trim().toUpperCase() ?? 'NORMAL';
    if (!allowAi || state != 'NORMAL') {
      await _repository.invalidateActiveChunksForMemo(memoUid);
      return;
    }

    final chunks = _chunkMemo(memoRow);
    if (chunks.isEmpty) {
      await _repository.invalidateActiveChunksForMemo(memoUid);
      return;
    }

    final embeddingResults = <_EmbeddingBuildResult>[];
    Object? firstFailure;
    for (final chunk in chunks) {
      try {
        final vector = await _createEmbedding(
          profile: profile,
          input: chunk.content,
        );
        embeddingResults.add(
          _EmbeddingBuildResult(
            status: AiEmbeddingStatus.ready,
            vector: vector,
          ),
        );
      } catch (error) {
        firstFailure ??= error;
        embeddingResults.add(
          _EmbeddingBuildResult(
            status: AiEmbeddingStatus.failed,
            errorText: error.toString(),
          ),
        );
      }
    }

    await _repository.invalidateActiveChunksForMemo(memoUid);
    final chunkIds = await _repository.insertActiveChunks(
      memoUid: memoUid,
      chunks: chunks,
    );
    for (
      var index = 0;
      index < math.min(chunkIds.length, embeddingResults.length);
      index++
    ) {
      final record = embeddingResults[index];
      await _repository.insertEmbeddingRecord(
        chunkId: chunkIds[index],
        profile: profile,
        status: record.status,
        vector: record.vector,
        errorText: record.errorText,
      );
    }
    if (firstFailure != null) {
      throw StateError(firstFailure.toString());
    }
  }

  Future<_RetrievalBundle> _retrieveEmotionMapEvidence({
    required AppLanguage language,
    required AiEmbeddingProfile profile,
    required int startTimeSec,
    required int endTimeSecExclusive,
    required bool includePublic,
    required bool includePrivate,
    required bool includeProtected,
  }) async {
    final rows = await _repository.listCandidateChunkRows(
      startTimeSec: startTimeSec,
      endTimeSecExclusive: endTimeSecExclusive,
      includePublic: includePublic,
      includePrivate: includePrivate,
      includeProtected: includeProtected,
      baseUrl: profile.baseUrl,
      model: profile.model,
      limit: _candidateChunkLimit,
    );
    final candidates = rows
        .map(_candidateChunkFromRow)
        .where(
          (item) =>
              item.embeddingStatus == AiEmbeddingStatus.ready &&
              item.vector != null,
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      return const _RetrievalBundle(candidates: <AiEvidenceCandidate>[]);
    }

    final merged = <String, AiEvidenceCandidate>{};
    final perMemoCount = <String, int>{};
    var evidenceCounter = 0;

    for (final intent in _emotionMapIntents(language)) {
      final queryVector = await _createEmbedding(
        profile: profile,
        input: intent.query,
      );
      final scored =
          candidates
              .map(
                (item) => (
                  item: item,
                  score: _cosineSimilarity(queryVector, item.vector!),
                ),
              )
              .where((entry) => entry.score > 0)
              .toList(growable: false)
            ..sort((a, b) => b.score.compareTo(a.score));

      for (final entry in scored.take(_topChunksPerIntent)) {
        if (merged.containsKey('${entry.item.chunkId}')) continue;
        final currentMemoCount = perMemoCount[entry.item.memoUid] ?? 0;
        if (currentMemoCount >= _maxChunksPerMemo) continue;
        if (merged.length >= _maxMergedChunks) break;
        evidenceCounter += 1;
        final evidence = AiEvidenceCandidate(
          evidenceKey: 'e$evidenceCounter',
          sectionKey: intent.sectionKey,
          memoUid: entry.item.memoUid,
          chunkId: entry.item.chunkId,
          quoteText: entry.item.content,
          charStart: entry.item.charStart,
          charEnd: entry.item.charEnd,
          relevanceScore: entry.score,
          memoCreateTime: entry.item.memoCreateTime,
          memoVisibility: entry.item.memoVisibility,
        );
        merged['${entry.item.chunkId}'] = evidence;
        perMemoCount[entry.item.memoUid] = currentMemoCount + 1;
      }
    }

    return _RetrievalBundle(candidates: merged.values.toList(growable: false));
  }

  Future<AiStructuredAnalysisResult> _generateEmotionMapResult({
    required AppLanguage language,
    required AiSettings settings,
    required AiGenerationProfile generationProfile,
    required List<AiEvidenceCandidate> candidates,
    required String promptTemplate,
    required DateTimeRange range,
  }) async {
    final candidateMap = <String, AiEvidenceCandidate>{
      for (final item in candidates) item.evidenceKey: item,
    };
    Object? lastError;
    String? previousOutput;
    for (var attempt = 0; attempt < 2; attempt++) {
      final rawResponse = await _callGenerationBackend(
        language: language,
        profile: generationProfile,
        systemPrompt: _buildSystemPrompt(language: language),
        userPrompt: _buildEmotionMapUserPrompt(
          language: language,
          settings: settings,
          candidates: candidates,
          promptTemplate: promptTemplate,
          range: range,
          attempt: attempt,
          previousOutput: previousOutput,
          previousError: lastError?.toString(),
        ),
      );
      previousOutput = rawResponse;
      try {
        return _normalizeStructuredResult(
          rawResponseText: rawResponse,
          candidateMap: candidateMap,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(lastError.toString());
  }

  Future<String> _callGenerationBackend({
    required AppLanguage language,
    required AiGenerationProfile profile,
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final normalizedBase = _normalizeBase(profile.baseUrl, ensureV1: true);
    if (profile.providerKind == AiProviderKind.anthropicCompatible) {
      final response = await _dio.post(
        _resolveEndpoint(normalizedBase, 'messages'),
        options: Options(
          headers: <String, Object?>{
            if (profile.apiKey.trim().isNotEmpty)
              'x-api-key': profile.apiKey.trim(),
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
        ),
        data: <String, Object?>{
          'model': profile.model,
          'max_tokens': 1400,
          'temperature': 0.3,
          'system': systemPrompt,
          'messages': [
            <String, Object?>{'role': 'user', 'content': userPrompt},
          ],
        },
      );
      final data = response.data;
      if (data is Map && data['content'] is List) {
        final buffer = StringBuffer();
        for (final item in data['content'] as List) {
          if (item is Map && item['text'] is String) {
            buffer.write(item['text']);
          }
        }
        final text = buffer.toString().trim();
        if (text.isNotEmpty) return text;
      }
      throw StateError(
        trByLanguage(
          language: language,
          zh: '生成接口返回为空。',
          en: 'Generation API returned empty content.',
        ),
      );
    }

    final response = await _dio.post(
      _resolveEndpoint(normalizedBase, 'chat/completions'),
      options: Options(
        headers: <String, Object?>{
          if (profile.apiKey.trim().isNotEmpty)
            'Authorization': 'Bearer ${profile.apiKey.trim()}',
          'Content-Type': 'application/json',
        },
      ),
      data: <String, Object?>{
        'model': profile.model,
        'temperature': 0.3,
        'messages': [
          <String, Object?>{'role': 'system', 'content': systemPrompt},
          <String, Object?>{'role': 'user', 'content': userPrompt},
        ],
      },
    );
    final data = response.data;
    if (data is Map &&
        data['choices'] is List &&
        (data['choices'] as List).isNotEmpty) {
      final first = (data['choices'] as List).first;
      if (first is Map) {
        final message = first['message'];
        if (message is Map && message['content'] is String) {
          return (message['content'] as String).trim();
        }
        if (first['text'] is String) {
          return (first['text'] as String).trim();
        }
      }
    }
    throw StateError(
      trByLanguage(
        language: language,
        zh: '生成接口返回为空。',
        en: 'Generation API returned empty content.',
      ),
    );
  }

  Future<Float32List> _createEmbedding({
    required AiEmbeddingProfile profile,
    required String input,
  }) async {
    final normalizedInput = input.trim();
    if (normalizedInput.isEmpty) {
      throw StateError('Empty embedding input');
    }
    final response = await _dio.post(
      _resolveEndpoint(
        _normalizeBase(profile.baseUrl, ensureV1: true),
        'embeddings',
      ),
      options: Options(
        headers: <String, Object?>{
          if (profile.apiKey.trim().isNotEmpty)
            'Authorization': 'Bearer ${profile.apiKey.trim()}',
          'Content-Type': 'application/json',
        },
      ),
      data: <String, Object?>{'model': profile.model, 'input': normalizedInput},
    );
    final data = response.data;
    if (data is Map &&
        data['data'] is List &&
        (data['data'] as List).isNotEmpty) {
      final first = (data['data'] as List).first;
      if (first is Map && first['embedding'] is List) {
        final raw = first['embedding'] as List;
        return Float32List.fromList(
          raw.map((item) => (item as num).toDouble()).toList(growable: false),
        );
      }
    }
    throw StateError('Embedding API returned empty vector');
  }

  AiStructuredAnalysisResult _normalizeStructuredResult({
    required String rawResponseText,
    required Map<String, AiEvidenceCandidate> candidateMap,
  }) {
    final decoded = _decodeJsonObject(rawResponseText);
    final analysisType = (decoded['analysis_type'] as String?)?.trim() ?? '';
    if (analysisType != 'emotion_map') {
      throw const FormatException('analysis_type must be emotion_map');
    }
    final sectionsRaw = decoded['sections'];
    final followUpRaw = decoded['follow_up_suggestions'];
    if (sectionsRaw is! List || followUpRaw is! List) {
      throw const FormatException('sections/follow_up_suggestions missing');
    }

    final evidences = <AiAnalysisEvidenceData>[];
    final sections = <AiAnalysisSectionData>[];
    for (final sectionKey in _sectionOrder) {
      final rawSection = sectionsRaw
          .cast<Object?>()
          .whereType<Map>()
          .firstWhere(
            (item) => (item['section_key'] as String?)?.trim() == sectionKey,
            orElse: () => const <String, Object?>{},
          );
      if (rawSection.isEmpty) {
        throw FormatException('missing section: $sectionKey');
      }
      final evidenceKeys =
          (rawSection['evidence_keys'] as List?)
              ?.whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
      if (evidenceKeys.isEmpty) {
        throw FormatException('section has no evidence: $sectionKey');
      }
      sections.add(
        AiAnalysisSectionData(
          sectionKey: sectionKey,
          title: ((rawSection['title'] as String?) ?? '').trim(),
          body: ((rawSection['body'] as String?) ?? '').trim(),
          evidenceKeys: evidenceKeys,
        ),
      );
      for (final evidenceKey in evidenceKeys) {
        final candidate = candidateMap[evidenceKey];
        if (candidate == null) {
          throw FormatException('unknown evidence_key: $evidenceKey');
        }
        evidences.add(
          AiAnalysisEvidenceData(
            evidenceKey: candidate.evidenceKey,
            sectionKey: sectionKey,
            memoUid: candidate.memoUid,
            chunkId: candidate.chunkId,
            quoteText: candidate.quoteText,
            charStart: candidate.charStart,
            charEnd: candidate.charEnd,
            relevanceScore: candidate.relevanceScore,
          ),
        );
      }
    }

    final suggestions = followUpRaw
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(6)
        .toList(growable: false);
    if (suggestions.isEmpty) {
      throw const FormatException('follow_up_suggestions missing');
    }

    return AiStructuredAnalysisResult(
      schemaVersion: _schemaVersion,
      analysisType: AiAnalysisType.emotionMap,
      summary: ((decoded['summary'] as String?) ?? '').trim(),
      sections: sections,
      evidences: _dedupeEvidences(evidences),
      followUpSuggestions: suggestions,
      rawResponseText: rawResponseText,
    );
  }

  List<AiAnalysisEvidenceData> _dedupeEvidences(
    List<AiAnalysisEvidenceData> items,
  ) {
    final seen = <String>{};
    final result = <AiAnalysisEvidenceData>[];
    for (final item in items) {
      final key = '${item.sectionKey}|${item.evidenceKey}';
      if (seen.add(key)) {
        result.add(item);
      }
    }
    return result;
  }

  String _buildSystemPrompt({required AppLanguage language}) {
    return trByLanguage(
      language: language,
      zh: '你是一个严格输出 JSON 的情绪分析助手。不要输出 Markdown，不要解释，只返回一个合法 JSON 对象。analysis_type 固定为 emotion_map，schema_version 固定为 1。只能引用提供的 evidence_key。',
      en: 'You are an emotion analysis assistant that must output valid JSON only. No markdown, no explanation. Return one JSON object with analysis_type=emotion_map and schema_version=1, and only cite provided evidence_key values.',
    );
  }

  String _buildEmotionMapUserPrompt({
    required AppLanguage language,
    required AiSettings settings,
    required List<AiEvidenceCandidate> candidates,
    required String promptTemplate,
    required DateTimeRange range,
    required int attempt,
    String? previousOutput,
    String? previousError,
  }) {
    final localeText = prefersEnglishFor(language)
        ? 'English'
        : 'Simplified Chinese';
    final sections = _emotionMapIntents(language)
        .map(
          (intent) => {'section_key': intent.sectionKey, 'goal': intent.query},
        )
        .toList(growable: false);
    final payload = <String, Object?>{
      'task': 'emotion_map',
      'write_language': localeText,
      'date_range': {
        'start': range.start.toIso8601String(),
        'end': range.end.toIso8601String(),
      },
      'user_profile': settings.userProfile.trim(),
      'custom_prompt_template': promptTemplate.trim(),
      'sections': sections,
      'evidence_pack': candidates
          .map((item) => item.toJson())
          .toList(growable: false),
      'required_output_schema': {
        'schema_version': 1,
        'analysis_type': 'emotion_map',
        'summary': 'string',
        'sections': [
          {
            'section_key': 'emotion_curve',
            'title': 'string',
            'body': 'string',
            'evidence_keys': ['e1', 'e2'],
          },
        ],
        'follow_up_suggestions': ['string'],
      },
    };
    final buffer = StringBuffer(jsonEncode(payload));
    if (attempt > 0) {
      buffer.writeln();
      buffer.writeln(
        trByLanguage(
          language: language,
          zh: '上一次输出不合法，请修正后重新输出合法 JSON。',
          en: 'The last output was invalid. Fix it and return valid JSON only.',
        ),
      );
      if ((previousError ?? '').trim().isNotEmpty) {
        buffer.writeln('error: ${previousError!.trim()}');
      }
      if ((previousOutput ?? '').trim().isNotEmpty) {
        buffer.writeln('previous_output: ${previousOutput!.trim()}');
      }
    }
    return buffer.toString();
  }

  List<_IntentQuery> _emotionMapIntents(AppLanguage language) {
    return <_IntentQuery>[
      _IntentQuery(
        sectionKey: 'emotion_curve',
        query: trByLanguage(
          language: language,
          zh: '找出情绪高点、低点、波动与反复变化的片段。',
          en: 'Find passages showing emotional highs, lows, volatility, and repeated swings.',
        ),
      ),
      _IntentQuery(
        sectionKey: 'stress_trigger',
        query: trByLanguage(
          language: language,
          zh: '找出压力源、焦虑来源、持续消耗你的触发因素。',
          en: 'Find passages about stressors, anxiety sources, and draining triggers.',
        ),
      ),
      _IntentQuery(
        sectionKey: 'recovery_signal',
        query: trByLanguage(
          language: language,
          zh: '找出让你缓和、恢复、安定、重建秩序的因素。',
          en: 'Find passages about calming, recovery, stability, and restoring balance.',
        ),
      ),
      _IntentQuery(
        sectionKey: 'relationship_theme',
        query: trByLanguage(
          language: language,
          zh: '找出与情绪有关的人际关系、反复出现的人和互动主题。',
          en: 'Find passages about emotional relationship themes, recurring people, and interaction patterns.',
        ),
      ),
    ];
  }

  List<AiChunkDraft> _chunkMemo(Map<String, dynamic> memoRow) {
    final content = ((memoRow['content'] as String?) ?? '').trimRight();
    if (content.trim().isEmpty) return const <AiChunkDraft>[];
    final memoUid = (memoRow['uid'] as String?) ?? '';
    if (memoUid.trim().isEmpty) return const <AiChunkDraft>[];
    final memoContentHash = _computeMemoContentHash(memoRow);
    final createTime = (memoRow['create_time'] as int?) ?? 0;
    final updateTime = (memoRow['update_time'] as int?) ?? 0;
    final visibility = (memoRow['visibility'] as String?)?.trim() ?? 'PRIVATE';

    final chunks = <AiChunkDraft>[];
    final paragraphPattern = RegExp(r'\n\s*\n');
    final matches = paragraphPattern
        .allMatches(content)
        .toList(growable: false);
    var cursor = 0;
    final spans = <_ContentSpan>[];
    for (final match in matches) {
      final end = match.start;
      if (end > cursor) {
        final text = content.substring(cursor, end).trim();
        if (_isChunkableText(text)) {
          spans.add(
            _ContentSpan(
              start: cursor,
              end: end,
              text: content.substring(cursor, end),
            ),
          );
        }
      }
      cursor = match.end;
    }
    if (cursor < content.length) {
      final text = content.substring(cursor).trim();
      if (_isChunkableText(text)) {
        spans.add(
          _ContentSpan(
            start: cursor,
            end: content.length,
            text: content.substring(cursor),
          ),
        );
      }
    }
    if (spans.isEmpty && _isChunkableText(content)) {
      spans.add(_ContentSpan(start: 0, end: content.length, text: content));
    }

    var chunkIndex = 0;
    var currentStart = -1;
    var currentEnd = -1;
    var buffer = StringBuffer();

    void pushChunk() {
      final text = buffer.toString().trim();
      if (text.isEmpty || currentStart < 0 || currentEnd <= currentStart) {
        return;
      }
      chunks.add(
        AiChunkDraft(
          chunkIndex: chunkIndex,
          content: text,
          contentHash: sha1.convert(utf8.encode(text)).toString(),
          memoContentHash: memoContentHash,
          charStart: currentStart,
          charEnd: currentEnd,
          tokenEstimate: (utf8.encode(text).length / 4).ceil(),
          memoCreateTime: createTime,
          memoUpdateTime: updateTime,
          memoVisibility: visibility,
        ),
      );
      chunkIndex += 1;
    }

    for (final span in spans) {
      final trimmed = span.text.trim();
      if (trimmed.length > 600) {
        pushChunk();
        buffer = StringBuffer();
        currentStart = -1;
        currentEnd = -1;
        var splitStart = 0;
        while (splitStart < trimmed.length) {
          final splitEnd = math.min(trimmed.length, splitStart + 500);
          final piece = trimmed.substring(splitStart, splitEnd).trim();
          if (piece.isNotEmpty) {
            chunks.add(
              AiChunkDraft(
                chunkIndex: chunkIndex,
                content: piece,
                contentHash: sha1.convert(utf8.encode(piece)).toString(),
                memoContentHash: memoContentHash,
                charStart: span.start + splitStart,
                charEnd: span.start + splitEnd,
                tokenEstimate: (utf8.encode(piece).length / 4).ceil(),
                memoCreateTime: createTime,
                memoUpdateTime: updateTime,
                memoVisibility: visibility,
              ),
            );
            chunkIndex += 1;
          }
          if (splitEnd >= trimmed.length) break;
          splitStart = math.max(0, splitEnd - 60);
        }
        continue;
      }

      final nextLength = buffer.isEmpty
          ? trimmed.length
          : buffer.length + 2 + trimmed.length;
      if (buffer.isNotEmpty && nextLength > 500) {
        pushChunk();
        final overlapStart = math.max(currentEnd - 60, 0);
        final overlapText = content.substring(overlapStart, currentEnd).trim();
        buffer = StringBuffer();
        if (overlapText.isNotEmpty) {
          buffer.write(overlapText);
          currentStart = overlapStart;
        } else {
          currentStart = -1;
          currentEnd = -1;
        }
      }
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(trimmed);
      currentStart = currentStart < 0 ? span.start : currentStart;
      currentEnd = span.end;
    }
    pushChunk();
    return chunks;
  }

  bool _isChunkableText(String text) {
    final normalized = text
        .replaceAll(RegExp(r'#[^\s#]+'), '')
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^\)]*\)'), '')
        .replaceAll(
          RegExp(r'\[[^\]]*attachment[^\]]*\]', caseSensitive: false),
          '',
        )
        .trim();
    return normalized.isNotEmpty;
  }

  bool _memoRowAllowed(
    Map<String, dynamic> row, {
    required bool includePublic,
    required bool includePrivate,
    required bool includeProtected,
  }) {
    final allowAi = ((row['allow_ai'] as int?) ?? 1) == 1;
    final state = (row['state'] as String?)?.trim().toUpperCase() ?? 'NORMAL';
    final visibility =
        (row['visibility'] as String?)?.trim().toUpperCase() ?? 'PRIVATE';
    final content = ((row['content'] as String?) ?? '').trim();
    if (!allowAi || state != 'NORMAL' || content.isEmpty) return false;
    if (!includePublic && visibility == 'PUBLIC') return false;
    if (!includePrivate && visibility == 'PRIVATE') return false;
    if (!includeProtected && visibility == 'PROTECTED') return false;
    return true;
  }

  String _computeMemoContentHash(Map<String, dynamic> row) {
    final content = (row['content'] as String?) ?? '';
    final visibility = (row['visibility'] as String?) ?? '';
    return computeContentFingerprint('$visibility\n$content');
  }

  AiRetrievalPreviewItem _previewItemFromRow(Map<String, dynamic> row) {
    final createTime = (row['memo_create_time'] as int?) ?? 0;
    return AiRetrievalPreviewItem(
      memoUid: (row['memo_uid'] as String?) ?? '',
      chunkId: (row['id'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createTime * 1000,
        isUtc: true,
      ).toLocal(),
      visibility: (row['memo_visibility'] as String?) ?? 'PRIVATE',
      content: ((row['content'] as String?) ?? '').trim(),
      embeddingStatus: aiEmbeddingStatusFromStorage(
        (row['embedding_status'] as String?) ?? 'pending',
      ),
    );
  }

  _CandidateChunk _candidateChunkFromRow(Map<String, dynamic> row) {
    final blob = row['vector_blob'];
    Float32List? vector;
    if (blob is Uint8List && blob.isNotEmpty) {
      vector = blob.buffer.asFloat32List(
        blob.offsetInBytes,
        blob.lengthInBytes ~/ 4,
      );
    }
    return _CandidateChunk(
      chunkId: (row['id'] as int?) ?? 0,
      memoUid: (row['memo_uid'] as String?) ?? '',
      content: ((row['content'] as String?) ?? '').trim(),
      charStart: (row['char_start'] as int?) ?? 0,
      charEnd: (row['char_end'] as int?) ?? 0,
      memoCreateTime: (row['memo_create_time'] as int?) ?? 0,
      memoVisibility: (row['memo_visibility'] as String?) ?? 'PRIVATE',
      embeddingStatus: aiEmbeddingStatusFromStorage(
        (row['embedding_status'] as String?) ?? 'pending',
      ),
      vector: vector,
    );
  }

  int _rangeStart(DateTimeRange range) {
    return DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        ).toUtc().millisecondsSinceEpoch ~/
        1000;
  }

  int _rangeEndExclusive(DateTimeRange range) {
    return DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
        ).add(const Duration(days: 1)).toUtc().millisecondsSinceEpoch ~/
        1000;
  }

  AiGenerationProfile? _resolveGenerationProfile(AiSettings settings) {
    if (settings.selectedGenerationProfile.enabled) {
      return settings.selectedGenerationProfile;
    }
    return settings.generationProfiles
        .where((profile) => profile.enabled)
        .firstOrNull;
  }

  AiEmbeddingProfile? _resolveEmbeddingProfile(AiSettings settings) {
    final selected = settings.selectedEmbeddingProfile;
    if (selected != null && selected.enabled) return selected;
    return settings.embeddingProfiles
        .where((profile) => profile.enabled)
        .firstOrNull;
  }

  double _cosineSimilarity(Float32List left, Float32List right) {
    if (left.length != right.length || left.isEmpty) return 0;
    var dot = 0.0;
    var leftNorm = 0.0;
    var rightNorm = 0.0;
    for (var index = 0; index < left.length; index++) {
      final l = left[index];
      final r = right[index];
      dot += l * r;
      leftNorm += l * l;
      rightNorm += r * r;
    }
    if (leftNorm <= 0 || rightNorm <= 0) return 0;
    return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
  }

  Map<String, dynamic> _decodeJsonObject(String rawText) {
    final cleaned = rawText
        .trim()
        .replaceAll(RegExp(r'^```[a-zA-Z]*'), '')
        .replaceAll('```', '')
        .trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('No JSON object found');
    }
    final decoded = jsonDecode(cleaned.substring(start, end + 1));
    if (decoded is! Map) {
      throw const FormatException('JSON root must be an object');
    }
    return decoded.cast<String, dynamic>();
  }

  String _normalizeBase(String baseUrl, {required bool ensureV1}) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    final uri = Uri.parse(trimmed);
    final segments = uri.pathSegments
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
    if (ensureV1 && !segments.contains('v1')) {
      segments.add('v1');
    }
    return uri
        .replace(pathSegments: segments)
        .toString()
        .replaceAll(RegExp(r'/$'), '');
  }

  String _resolveEndpoint(String base, String path) {
    final normalizedBase = base.replaceAll(RegExp(r'/$'), '');
    final normalizedPath = path.replaceFirst(RegExp(r'^/+'), '');
    return '$normalizedBase/$normalizedPath';
  }
}

class _ContentSpan {
  const _ContentSpan({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;
}

class _EmbeddingBuildResult {
  const _EmbeddingBuildResult({
    required this.status,
    this.vector,
    this.errorText,
  });

  final AiEmbeddingStatus status;
  final Float32List? vector;
  final String? errorText;
}

class _CandidateChunk {
  const _CandidateChunk({
    required this.chunkId,
    required this.memoUid,
    required this.content,
    required this.charStart,
    required this.charEnd,
    required this.memoCreateTime,
    required this.memoVisibility,
    required this.embeddingStatus,
    required this.vector,
  });

  final int chunkId;
  final String memoUid;
  final String content;
  final int charStart;
  final int charEnd;
  final int memoCreateTime;
  final String memoVisibility;
  final AiEmbeddingStatus embeddingStatus;
  final Float32List? vector;
}

class _RetrievalBundle {
  const _RetrievalBundle({required this.candidates});

  final List<AiEvidenceCandidate> candidates;
}

class _IntentQuery {
  const _IntentQuery({required this.sectionKey, required this.query});

  final String sectionKey;
  final String query;
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
