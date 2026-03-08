import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai/ai_analysis_repository.dart';
import '../../data/ai/ai_analysis_service.dart';
import '../system/database_provider.dart';

final aiAnalysisRepositoryProvider = Provider<AiAnalysisRepository>((ref) {
  return AiAnalysisRepository(ref.watch(databaseProvider));
});

final aiAnalysisServiceProvider = Provider<AiAnalysisService>((ref) {
  return AiAnalysisService(
    repository: ref.watch(aiAnalysisRepositoryProvider),
    dio: Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 180),
      ),
    ),
  );
});
