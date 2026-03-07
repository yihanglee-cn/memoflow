import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync/sync_request.dart';
import '../../data/api/memos_api.dart';
import '../../data/db/app_database.dart';
import '../../data/logs/log_manager.dart';
import '../../data/logs/logger_service.dart';
import '../../data/models/local_library.dart';
import '../../data/models/user_setting.dart';
import '../../data/updates/update_config.dart';
import '../system/database_provider.dart';
import '../system/debug_screenshot_mode_provider.dart';
import '../system/home_loading_overlay_provider.dart';
import '../system/local_library_provider.dart';
import '../system/logging_provider.dart';
import 'memos_providers.dart';
import '../settings/preferences_provider.dart';
import '../system/reminder_scheduler.dart';
import '../settings/reminder_settings_provider.dart';
import '../system/session_provider.dart';
import '../sync/sync_coordinator_provider.dart';
import '../system/update_config_provider.dart';
import '../settings/user_settings_provider.dart';
import '../webdav/webdav_backup_provider.dart';
final appBootstrapAdapterProvider = Provider<AppBootstrapAdapter>((ref) {
  return const AppBootstrapAdapter();
});

class AppBootstrapAdapter {
  const AppBootstrapAdapter();

  AppPreferences watchPreferences(WidgetRef ref) =>
      ref.watch(appPreferencesProvider);
  bool watchPreferencesLoaded(WidgetRef ref) =>
      ref.watch(appPreferencesLoadedProvider);
  AsyncValue<AppSessionState> watchSession(WidgetRef ref) =>
      ref.watch(appSessionProvider);
  LoggerService watchLoggerService(WidgetRef ref) =>
      ref.watch(loggerServiceProvider);
  ReminderSettings watchReminderSettings(WidgetRef ref) =>
      ref.watch(reminderSettingsProvider);
  bool watchDebugScreenshotMode(WidgetRef ref) =>
      ref.watch(debugScreenshotModeProvider);
  LocalLibrary? watchCurrentLocalLibrary(WidgetRef ref) =>
      ref.watch(currentLocalLibraryProvider);

  AppPreferences readPreferences(WidgetRef ref) =>
      ref.read(appPreferencesProvider);
  bool readPreferencesLoaded(WidgetRef ref) =>
      ref.read(appPreferencesLoadedProvider);
  AsyncValue<AppSessionState> readSessionAsync(WidgetRef ref) =>
      ref.read(appSessionProvider);
  AppSessionState? readSession(WidgetRef ref) =>
      ref.read(appSessionProvider).valueOrNull;
  LocalLibrary? readCurrentLocalLibrary(WidgetRef ref) =>
      ref.read(currentLocalLibraryProvider);
  bool readDebugScreenshotMode(WidgetRef ref) =>
      ref.read(debugScreenshotModeProvider);
  LogManager readLogManager(WidgetRef ref) => ref.read(logManagerProvider);
  ReminderScheduler readReminderScheduler(WidgetRef ref) =>
      ref.read(reminderSchedulerProvider);
  bool readReminderSettingsLoaded(WidgetRef ref) =>
      ref.read(reminderSettingsLoadedProvider);
  UserGeneralSetting? readUserGeneralSetting(WidgetRef ref) =>
      ref.read(userGeneralSettingProvider).valueOrNull;
  AppDatabase readDatabase(WidgetRef ref) => ref.read(databaseProvider);
  MemosApi readMemosApi(WidgetRef ref) => ref.read(memosApiProvider);

  ProviderSubscription<AsyncValue<AppSessionState>> listenSession(
    WidgetRef ref,
    void Function(
      AsyncValue<AppSessionState>? prev,
      AsyncValue<AppSessionState> next,
    ) listener,
  ) {
    return ref.listenManual<AsyncValue<AppSessionState>>(
      appSessionProvider,
      listener,
    );
  }

  ProviderSubscription<AppPreferences> listenPreferences(
    WidgetRef ref,
    void Function(AppPreferences? prev, AppPreferences next) listener,
  ) {
    return ref.listenManual<AppPreferences>(appPreferencesProvider, listener);
  }

  ProviderSubscription<bool> listenPreferencesLoaded(
    WidgetRef ref,
    void Function(bool? prev, bool next) listener,
  ) {
    return ref.listenManual<bool>(appPreferencesLoadedProvider, listener);
  }

  ProviderSubscription<ReminderSettings> listenReminderSettings(
    WidgetRef ref,
    void Function(ReminderSettings? prev, ReminderSettings next) listener,
  ) {
    return ref.listenManual<ReminderSettings>(
      reminderSettingsProvider,
      listener,
    );
  }

  ProviderSubscription<bool> listenDebugScreenshotMode(
    WidgetRef ref,
    void Function(bool? prev, bool next) listener,
  ) {
    return ref.listenManual<bool>(debugScreenshotModeProvider, listener);
  }

  Future<List<TagStat>> readTagStats(WidgetRef ref) =>
      ref.read(tagStatsProvider.future);

  Future<void> reloadSessionFromStorage(WidgetRef ref) =>
      ref.read(appSessionProvider.notifier).reloadFromStorage();

  Future<void> reloadLocalLibrariesFromStorage(WidgetRef ref) =>
      ref.read(localLibrariesProvider.notifier).reloadFromStorage();

  Future<void> setCurrentSessionKey(WidgetRef ref, String? key) =>
      ref.read(appSessionProvider.notifier).setCurrentKey(key);

  void setHasSelectedLanguage(WidgetRef ref, bool value) {
    ref.read(appPreferencesProvider.notifier).setHasSelectedLanguage(value);
  }

  void ensureAccountThemeDefaults(WidgetRef ref, String accountKey) {
    ref
        .read(appPreferencesProvider.notifier)
        .ensureAccountThemeDefaults(accountKey);
  }

  void setLastSeenAnnouncement({
    required WidgetRef ref,
    required String version,
    required int announcementId,
  }) {
    ref
        .read(appPreferencesProvider.notifier)
        .setLastSeenAnnouncement(
          version: version,
          announcementId: announcementId,
        );
  }

  void setSkippedUpdateVersion({
    required WidgetRef ref,
    required String version,
  }) {
    ref.read(appPreferencesProvider.notifier).setSkippedUpdateVersion(version);
  }

  void setLastSeenNoticeHash(WidgetRef ref, String hash) {
    ref.read(appPreferencesProvider.notifier).setLastSeenNoticeHash(hash);
  }

  void forceHomeLoadingOverlay(WidgetRef ref) {
    ref.read(homeLoadingOverlayForceProvider.notifier).state = true;
  }

  Future<void> requestSync(WidgetRef ref, SyncRequest request) =>
      ref.read(syncCoordinatorProvider.notifier).requestSync(request);

  Future<UpdateAnnouncementConfig?> fetchLatestUpdateConfig(WidgetRef ref) =>
      ref.read(updateConfigServiceProvider).fetchLatest();

  void resumeWebDavBackupProgress(WidgetRef ref) {
    ref.read(webDavBackupProgressTrackerProvider).resume();
  }

  void pauseWebDavBackupProgress(WidgetRef ref) {
    ref.read(webDavBackupProgressTrackerProvider).pauseIfRunning();
  }
}
