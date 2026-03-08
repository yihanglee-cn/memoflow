import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_coordinator_provider.dart';
import '../../application/sync/sync_request.dart';
import '../../data/repositories/ai_settings_repository.dart';
import 'preferences_provider.dart';
import '../system/session_provider.dart';

final aiSettingsRepositoryProvider = Provider<AiSettingsRepository>((ref) {
  final accountKey = ref.watch(
    appSessionProvider.select((state) => state.valueOrNull?.currentKey),
  );
  return AiSettingsRepository(
    ref.watch(secureStorageProvider),
    accountKey: accountKey,
  );
});

final aiSettingsProvider =
    StateNotifierProvider<AiSettingsController, AiSettings>((ref) {
      return AiSettingsController(ref, ref.watch(aiSettingsRepositoryProvider));
    });

class AiSettingsController extends StateNotifier<AiSettings> {
  AiSettingsController(Ref ref, AiSettingsRepository repo)
    : _ref = ref,
      _repo = repo,
      super(AiSettings.defaultsFor(ref.read(appPreferencesProvider).language)) {
    unawaited(_load());
  }

  final Ref _ref;
  final AiSettingsRepository _repo;

  Future<void> _load() async {
    state = await _repo.read(
      language: _ref.read(appPreferencesProvider).language,
    );
  }

  Future<void> setAll(AiSettings next, {bool triggerSync = true}) async {
    state = next;
    await _repo.write(next);
    if (triggerSync) {
      unawaited(
        _ref
            .read(syncCoordinatorProvider.notifier)
            .requestSync(
              const SyncRequest(
                kind: SyncRequestKind.webDavSync,
                reason: SyncRequestReason.settings,
              ),
            ),
      );
    }
  }

  Future<void> setApiUrl(String v) async =>
      setAll(state.copyWith(apiUrl: v.trim()));
  Future<void> setApiKey(String v) async =>
      setAll(state.copyWith(apiKey: v.trim()));
  Future<void> setModel(String v) async =>
      setAll(state.copyWith(model: v.trim()));
  Future<void> setEmbeddingBaseUrl(String v) async =>
      setAll(state.copyWith(embeddingBaseUrl: v.trim()));
  Future<void> setEmbeddingApiKey(String v) async =>
      setAll(state.copyWith(embeddingApiKey: v.trim()));
  Future<void> setEmbeddingModel(String v) async =>
      setAll(state.copyWith(embeddingModel: v.trim()));
  Future<void> setPrompt(String v) async =>
      setAll(state.copyWith(prompt: v.trim()));
  Future<void> setUserProfile(String v) async =>
      setAll(state.copyWith(userProfile: v.trim()));

  Future<void> setGenerationProfiles(
    List<AiGenerationProfile> profiles, {
    String? selectedKey,
  }) async {
    await setAll(
      state.copyWith(
        generationProfiles: List<AiGenerationProfile>.unmodifiable(profiles),
        selectedGenerationProfileKey: selectedKey,
      ),
    );
  }

  Future<void> setEmbeddingProfiles(
    List<AiEmbeddingProfile> profiles, {
    String? selectedKey,
  }) async {
    await setAll(
      state.copyWith(
        embeddingProfiles: List<AiEmbeddingProfile>.unmodifiable(profiles),
        selectedEmbeddingProfileKey: selectedKey,
      ),
    );
  }

  Future<void> setInsightPromptTemplate(
    String insightId,
    String template,
  ) async {
    final normalizedInsightId = insightId.trim();
    if (normalizedInsightId.isEmpty) return;
    final nextTemplates = Map<String, String>.from(
      state.analysisPromptTemplates,
    );
    final normalizedTemplate = template.trim();
    if (normalizedTemplate.isEmpty) {
      nextTemplates.remove(normalizedInsightId);
    } else {
      nextTemplates[normalizedInsightId] = normalizedTemplate;
    }
    await setAll(
      state.copyWith(
        analysisPromptTemplates: Map<String, String>.unmodifiable(
          nextTemplates,
        ),
      ),
    );
  }

  Future<void> clearInsightPromptTemplate(String insightId) async {
    await setInsightPromptTemplate(insightId, '');
  }
}
