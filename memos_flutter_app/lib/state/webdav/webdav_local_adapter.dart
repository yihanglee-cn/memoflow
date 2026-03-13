import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/sync/webdav_sync_service.dart';
import '../../data/models/image_compression_settings.dart';
import '../../data/models/image_bed_settings.dart';
import '../../data/models/location_settings.dart';
import '../../data/models/memo_template_settings.dart';
import '../../data/models/tag_snapshot.dart';
import '../../data/models/webdav_settings.dart';
import '../../data/repositories/ai_settings_repository.dart';
import '../settings/ai_settings_provider.dart';
import '../settings/app_lock_provider.dart';
import '../settings/image_bed_settings_provider.dart';
import '../settings/image_compression_settings_provider.dart';
import '../settings/location_settings_provider.dart';
import '../settings/memo_template_settings_provider.dart';
import '../memos/note_draft_provider.dart';
import '../settings/preferences_provider.dart';
import '../settings/reminder_settings_provider.dart';
import '../tags/tag_repository.dart';
import 'webdav_settings_provider.dart';

class RiverpodWebDavSyncLocalAdapter implements WebDavSyncLocalAdapter {
  RiverpodWebDavSyncLocalAdapter(this._ref);

  final Ref _ref;

  @override
  Future<WebDavSyncLocalSnapshot> readSnapshot() async {
    final prefs = _ref.read(appPreferencesProvider);
    final ai = await _ref
        .read(aiSettingsRepositoryProvider)
        .read(language: prefs.language);
    final reminder = _ref.read(reminderSettingsProvider);
    final imageBed = _ref.read(imageBedSettingsProvider);
    final imageCompression = _ref.read(imageCompressionSettingsProvider);
    final location = _ref.read(locationSettingsProvider);
    final template = _ref.read(memoTemplateSettingsProvider);
    final lockRepo = _ref.read(appLockRepositoryProvider);
    final lockSnapshot = await lockRepo.readSnapshot();
    final draft = _ref.read(noteDraftProvider).valueOrNull ?? '';
    final tagsSnapshot = await _ref.read(tagRepositoryProvider).readSnapshot();
    return WebDavSyncLocalSnapshot(
      preferences: prefs,
      aiSettings: ai,
      reminderSettings: reminder,
      imageBedSettings: imageBed,
      imageCompressionSettings: imageCompression,
      locationSettings: location,
      templateSettings: template,
      appLockSnapshot: lockSnapshot,
      noteDraft: draft,
      tagsSnapshot: tagsSnapshot,
    );
  }

  @override
  Future<void> applyPreferences(AppPreferences preferences) async {
    await _ref
        .read(appPreferencesProvider.notifier)
        .setAll(preferences, triggerSync: false);
  }

  @override
  Future<void> applyAiSettings(AiSettings settings) async {
    await _ref
        .read(aiSettingsProvider.notifier)
        .setAll(settings, triggerSync: false);
  }

  @override
  Future<void> applyReminderSettings(ReminderSettings settings) async {
    await _ref
        .read(reminderSettingsProvider.notifier)
        .setAll(settings, triggerSync: false);
  }

  @override
  Future<void> applyImageBedSettings(ImageBedSettings settings) async {
    await _ref
        .read(imageBedSettingsProvider.notifier)
        .setAll(settings, triggerSync: false);
  }

  @override
  Future<void> applyImageCompressionSettings(
    ImageCompressionSettings settings,
  ) async {
    await _ref
        .read(imageCompressionSettingsProvider.notifier)
        .setAll(settings, triggerSync: false);
  }

  @override
  Future<void> applyLocationSettings(LocationSettings settings) async {
    await _ref
        .read(locationSettingsProvider.notifier)
        .setAll(settings, triggerSync: false);
  }

  @override
  Future<void> applyTemplateSettings(MemoTemplateSettings settings) async {
    await _ref
        .read(memoTemplateSettingsProvider.notifier)
        .setAll(settings, triggerSync: false);
  }

  @override
  Future<void> applyAppLockSnapshot(AppLockSnapshot snapshot) async {
    await _ref
        .read(appLockProvider.notifier)
        .setSnapshot(snapshot, triggerSync: false);
  }

  @override
  Future<void> applyNoteDraft(String text) async {
    await _ref
        .read(noteDraftProvider.notifier)
        .setDraft(text, triggerSync: false);
  }

  @override
  Future<void> applyTags(TagSnapshot snapshot) async {
    await _ref.read(tagRepositoryProvider).applySnapshot(snapshot);
  }

  @override
  Future<void> applyWebDavSettings(WebDavSettings settings) async {
    _ref.read(webDavSettingsProvider.notifier).setAll(settings);
  }
}
