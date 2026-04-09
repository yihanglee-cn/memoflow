import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync/sync_request.dart';
import '../../core/desktop/shortcuts.dart';
import '../../core/storage_read.dart';
import '../../core/theme_colors.dart';
import '../../data/logs/log_manager.dart';
import '../../data/models/app_preferences.dart';
import '../../data/models/device_preferences.dart';
import '../sync/sync_coordinator_provider.dart';
import '../system/storage_error_provider.dart';
import 'preferences_migration_service.dart';

final devicePreferencesRepositoryProvider = Provider<DevicePreferencesRepository>(
  (ref) {
    return DevicePreferencesRepository(ref.watch(preferencesMigrationServiceProvider));
  },
);

final devicePreferencesLoadedProvider = StateProvider<bool>((ref) => false);

final devicePreferencesProvider =
    StateNotifierProvider<DevicePreferencesController, DevicePreferences>((ref) {
      final loadedState = ref.read(devicePreferencesLoadedProvider.notifier);
      Future.microtask(() => loadedState.state = false);
      return DevicePreferencesController(
        ref,
        ref.watch(devicePreferencesRepositoryProvider),
        onLoaded: () => loadedState.state = true,
      );
    });

class DevicePreferencesController extends StateNotifier<DevicePreferences> {
  DevicePreferencesController(this._ref, this._repo, {void Function()? onLoaded})
    : _onLoaded = onLoaded,
      super(DevicePreferences.defaults) {
    unawaited(_loadFromStorage());
  }

  final Ref _ref;
  final DevicePreferencesRepository _repo;
  final void Function()? _onLoaded;
  Future<void> _writeChain = Future<void>.value();

  Future<void> reloadFromStorage() async {
    await _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    final stateBeforeLoad = state;
    try {
      final result = await _repo.readWithStatus();
      if (!mounted) return;
      if (!identical(state, stateBeforeLoad)) return;
      if (result.isError) {
        final error = StorageLoadError(
          source: 'device_preferences',
          error: result.error!,
          stackTrace: result.stackTrace ?? StackTrace.current,
        );
        LogManager.instance.error(
          'Failed to load device preferences.',
          error: error.error,
          stackTrace: error.stackTrace,
        );
        _ref.read(devicePreferencesStorageErrorProvider.notifier).state = error;
        return;
      }
      _ref.read(devicePreferencesStorageErrorProvider.notifier).state = null;
      state = result.data ?? DevicePreferences.defaults;
    } catch (error, stackTrace) {
      LogManager.instance.error(
        'Failed to load device preferences.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      if (!identical(state, stateBeforeLoad)) return;
      _ref.read(devicePreferencesStorageErrorProvider.notifier).state =
          StorageLoadError(
            source: 'device_preferences',
            error: error,
            stackTrace: stackTrace,
          );
      return;
    } finally {
      if (mounted) {
        _onLoaded?.call();
      }
    }
  }

  void _setAndPersist(DevicePreferences next, {bool triggerSync = true}) {
    state = next;
    _writeChain = _writeChain.then((_) async {
      try {
        await _repo.write(next);
      } catch (error, stackTrace) {
        LogManager.instance.warn(
          'Failed to persist device preferences.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
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

  Future<void> waitForPendingWrites() => _writeChain;

  Future<void> setAll(
    DevicePreferences next, {
    bool triggerSync = true,
  }) async => _setAndPersist(next, triggerSync: triggerSync);

  void setLanguage(AppLanguage value) =>
      _setAndPersist(state.copyWith(language: value));
  void setHasSelectedLanguage(bool value) =>
      _setAndPersist(state.copyWith(hasSelectedLanguage: value));
  void setOnboardingMode(AppOnboardingMode? value) =>
      _setAndPersist(state.copyWith(onboardingMode: value));
  void setHomeInitialLoadingOverlayShown(bool value) =>
      _setAndPersist(state.copyWith(homeInitialLoadingOverlayShown: value));
  void setFontSize(AppFontSize value) =>
      _setAndPersist(state.copyWith(fontSize: value));
  void setLineHeight(AppLineHeight value) =>
      _setAndPersist(state.copyWith(lineHeight: value));
  void setFontFamily({String? family, String? filePath}) =>
      _setAndPersist(state.copyWith(fontFamily: family, fontFile: filePath));
  void setConfirmExitOnBack(bool value) =>
      _setAndPersist(state.copyWith(confirmExitOnBack: value));
  void setHapticsEnabled(bool value) =>
      _setAndPersist(state.copyWith(hapticsEnabled: value));
  void setNetworkLoggingEnabled(bool value) =>
      _setAndPersist(state.copyWith(networkLoggingEnabled: value));
  void setThemeMode(AppThemeMode value) =>
      _setAndPersist(state.copyWith(themeMode: value));
  void setThemeColor(AppThemeColor value) =>
      _setAndPersist(state.copyWith(themeColor: value));
  void setCustomTheme(CustomThemeSettings value) =>
      _setAndPersist(state.copyWith(customTheme: value));
  void setLaunchAction(LaunchAction value) =>
      _setAndPersist(state.copyWith(launchAction: value));
  void setQuickInputAutoFocus(bool value) =>
      _setAndPersist(state.copyWith(quickInputAutoFocus: value));
  void setThirdPartyShareEnabled(bool value) =>
      _setAndPersist(state.copyWith(thirdPartyShareEnabled: value));
  void setWindowsCloseToTray(bool value) =>
      _setAndPersist(state.copyWith(windowsCloseToTray: value));
  void setDesktopShortcutBinding({
    required DesktopShortcutAction action,
    required DesktopShortcutBinding binding,
  }) {
    final next = Map<DesktopShortcutAction, DesktopShortcutBinding>.from(
      state.desktopShortcutBindings,
    );
    next[action] = binding;
    _setAndPersist(state.copyWith(desktopShortcutBindings: next));
  }

  void resetDesktopShortcutBindings() {
    _setAndPersist(
      state.copyWith(desktopShortcutBindings: desktopShortcutDefaultBindings),
    );
  }

  void setLastSeenAppVersion(String value) =>
      _setAndPersist(state.copyWith(lastSeenAppVersion: value), triggerSync: false);
  void setSkippedUpdateVersion(String value) =>
      _setAndPersist(state.copyWith(skippedUpdateVersion: value), triggerSync: false);
  void setLastSeenAnnouncement({
    required String version,
    required int announcementId,
  }) {
    _setAndPersist(
      state.copyWith(
        lastSeenAnnouncementVersion: version,
        lastSeenAnnouncementId: announcementId,
      ),
      triggerSync: false,
    );
  }

  void setLastSeenNoticeHash(String value) {
    _setAndPersist(
      state.copyWith(lastSeenNoticeHash: value),
      triggerSync: false,
    );
  }
}

class DevicePreferencesRepository {
  DevicePreferencesRepository(this._migrationService);

  final PreferencesMigrationService _migrationService;

  Future<StorageReadResult<DevicePreferences>> readWithStatus() =>
      _migrationService.readDeviceWithStatus();

  Future<DevicePreferences> read() => _migrationService.readDevice();

  Future<void> write(DevicePreferences prefs) =>
      _migrationService.writeDevice(prefs);
}
