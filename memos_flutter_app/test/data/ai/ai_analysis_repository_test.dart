import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/data/ai/ai_analysis_models.dart';
import 'package:memos_flutter_app/data/ai/ai_analysis_repository.dart';
import 'package:memos_flutter_app/data/db/app_database.dart';

import '../../test_support.dart';

void main() {
  late TestSupport support;

  setUpAll(() async {
    support = await initializeTestSupport();
  });

  tearDownAll(() async {
    await support.dispose();
  });

  test('analysis history preserves whether public memos were included', () async {
    final dbName = uniqueDbName('ai_analysis_history_scope');
    final db = AppDatabase(dbName: dbName);
    final repository = AiAnalysisRepository(db);

    addTearDown(() async {
      await db.close();
      await deleteTestDatabase(dbName);
    });

    final taskId = await repository.createAnalysisTask(
      taskUid: 'task-private-only',
      analysisType: AiAnalysisType.emotionMap,
      status: AiTaskStatus.completed,
      rangeStart: DateTime.utc(2026, 3, 1).millisecondsSinceEpoch ~/ 1000,
      rangeEndExclusive:
          DateTime.utc(2026, 3, 8).millisecondsSinceEpoch ~/ 1000,
      includePublic: false,
      includePrivate: true,
      includeProtected: false,
      promptTemplate: 'Reflect on the week with care.',
      generationProfileKey: 'gen-default',
      embeddingProfileKey: 'embed-default',
      retrievalProfile: const <String, dynamic>{'include_public': false},
    );

    await repository.saveAnalysisResult(
      taskId: taskId,
      result: const AiStructuredAnalysisResult(
        schemaVersion: 1,
        analysisType: AiAnalysisType.emotionMap,
        summary: 'A private-only reflection.',
        sections: <AiAnalysisSectionData>[
          AiAnalysisSectionData(
            sectionKey: 'main',
            title: '',
            body: 'This week felt quieter and more internal.',
            evidenceKeys: <String>[],
          ),
        ],
        evidences: <AiAnalysisEvidenceData>[],
        followUpSuggestions: <String>[],
        rawResponseText: '{}',
      ),
    );

    final history = await repository.listAnalysisReportHistory(
      analysisType: AiAnalysisType.emotionMap,
    );

    expect(history, hasLength(1));
    expect(history.single.includePublic, isFalse);
    expect(history.single.includePrivate, isTrue);
    expect(history.single.includeProtected, isFalse);
  });
}
