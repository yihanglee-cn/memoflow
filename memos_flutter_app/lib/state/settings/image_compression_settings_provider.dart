import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync/sync_request.dart';
import '../../data/models/image_compression_settings.dart';
import '../../data/repositories/image_compression_settings_repository.dart';
import '../sync/sync_coordinator_provider.dart';
import '../system/session_provider.dart';

final imageCompressionSettingsRepositoryProvider =
    Provider<ImageCompressionSettingsRepository>((ref) {
      final session = ref.watch(appSessionProvider).valueOrNull;
      final key = session?.currentKey?.trim();
      final storageKey = (key == null || key.isEmpty) ? 'device' : key;
      return ImageCompressionSettingsRepository(
        ref.watch(secureStorageProvider),
        accountKey: storageKey,
      );
    });

final imageCompressionSettingsProvider = StateNotifierProvider<
    ImageCompressionSettingsController,
    ImageCompressionSettings>((ref) {
  return ImageCompressionSettingsController(
    ref,
    ref.watch(imageCompressionSettingsRepositoryProvider),
  );
});

class ImageCompressionSettingsController
    extends StateNotifier<ImageCompressionSettings> {
  ImageCompressionSettingsController(this._ref, this._repo)
    : super(ImageCompressionSettings.defaults) {
    unawaited(_load());
  }

  final Ref _ref;
  final ImageCompressionSettingsRepository _repo;

  Future<void> _load() async {
    final stored = await _repo.read();
    state = stored;
  }

  void _setAndPersist(ImageCompressionSettings next, {bool triggerSync = true}) {
    state = next;
    unawaited(_repo.write(next));
    if (triggerSync) {
      unawaited(
        _ref.read(syncCoordinatorProvider.notifier).requestSync(
              const SyncRequest(
                kind: SyncRequestKind.webDavSync,
                reason: SyncRequestReason.settings,
              ),
            ),
      );
    }
  }

  void setEnabled(bool value) => _setAndPersist(state.copyWith(enabled: value));

  void setMaxSide(int value) => _setAndPersist(state.copyWith(maxSide: value));

  void setQuality(int value) => _setAndPersist(state.copyWith(quality: value));

  void setFormat(ImageCompressionFormat value) {
    _setAndPersist(state.copyWith(format: value));
  }

  Future<void> setAll(
    ImageCompressionSettings next, {
    bool triggerSync = true,
  }) async {
    state = next;
    await _repo.write(next);
    if (triggerSync) {
      unawaited(
        _ref.read(syncCoordinatorProvider.notifier).requestSync(
              const SyncRequest(
                kind: SyncRequestKind.webDavSync,
                reason: SyncRequestReason.settings,
              ),
            ),
      );
    }
  }
}
