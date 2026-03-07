import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/models/app_preferences.dart';
import '../../data/updates/update_config.dart';
import '../../features/updates/notice_dialog.dart';
import '../../features/updates/update_announcement_dialog.dart';
import '../../state/memos/app_bootstrap_adapter_provider.dart';

class UpdateAnnouncementRunner {
  UpdateAnnouncementRunner({
    required AppBootstrapAdapter bootstrapAdapter,
    required GlobalKey<NavigatorState> navigatorKey,
    required bool Function() isMounted,
  }) : _bootstrapAdapter = bootstrapAdapter,
       _navigatorKey = navigatorKey,
       _isMounted = isMounted;

  final AppBootstrapAdapter _bootstrapAdapter;
  final GlobalKey<NavigatorState> _navigatorKey;
  final bool Function() _isMounted;

  bool _updateAnnouncementChecked = false;
  Future<String?>? _appVersionFuture;

  static const UpdateAnnouncementConfig _fallbackUpdateConfig =
      UpdateAnnouncementConfig(
        schemaVersion: 1,
        versionInfo: UpdateVersionInfo(
          latestVersion: '',
          isForce: false,
          downloadUrl: '',
          updateSource: '',
          publishAt: null,
          debugVersion: '',
          skipUpdateVersion: '',
        ),
        announcement: UpdateAnnouncement(
          id: 0,
          title: '',
          showWhenUpToDate: false,
          contentsByLocale: {},
          fallbackContents: [],
          newDonorIds: [],
        ),
        donors: [],
        releaseNotes: [],
        noticeEnabled: false,
        notice: null,
      );

  void scheduleIfNeeded(WidgetRef ref) {
    if (_updateAnnouncementChecked) return;
    _updateAnnouncementChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted()) return;
      unawaited(_maybeShowAnnouncements(ref));
    });
  }

  Future<String?> _fetchAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      return version.isEmpty ? null : version;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveAppVersion() {
    return _appVersionFuture ??= _fetchAppVersion();
  }

  int _compareVersionTriplets(String remote, String local) {
    final remoteParts = _parseVersionTriplet(remote);
    final localParts = _parseVersionTriplet(local);
    for (var i = 0; i < 3; i++) {
      final diff = remoteParts[i].compareTo(localParts[i]);
      if (diff != 0) return diff;
    }
    return 0;
  }

  List<int> _parseVersionTriplet(String version) {
    if (version.trim().isEmpty) return const [0, 0, 0];
    final trimmed = version.split(RegExp(r'[-+]')).first;
    final parts = trimmed.split('.');
    final values = <int>[0, 0, 0];
    for (var i = 0; i < 3; i++) {
      if (i >= parts.length) break;
      final match = RegExp(r'\d+').firstMatch(parts[i]);
      if (match == null) continue;
      values[i] = int.tryParse(match.group(0) ?? '') ?? 0;
    }
    return values;
  }

  Future<void> _maybeShowAnnouncements(WidgetRef ref) async {
    var version = await _resolveAppVersion();
    if (!_isMounted() || version == null || version.isEmpty) return;

    final prefs = _bootstrapAdapter.readPreferences(ref);
    if (!prefs.hasSelectedLanguage) return;

    final config = await _bootstrapAdapter.fetchLatestUpdateConfig(ref);
    if (!_isMounted()) return;
    final effectiveConfig = config ?? _fallbackUpdateConfig;

    var displayVersion = version;
    if (kDebugMode) {
      final debugVersion = effectiveConfig.versionInfo.debugVersion.trim();
      displayVersion = debugVersion.isNotEmpty ? debugVersion : '999.0';
    }

    await _maybeShowUpdateAnnouncementWithConfig(
      ref: ref,
      config: effectiveConfig,
      currentVersion: displayVersion,
      prefs: prefs,
    );
    await _maybeShowNoticeWithConfig(
      ref: ref,
      config: effectiveConfig,
      prefs: prefs,
    );
  }

  Future<void> _maybeShowUpdateAnnouncementWithConfig({
    required WidgetRef ref,
    required UpdateAnnouncementConfig config,
    required String currentVersion,
    required AppPreferences prefs,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    final publishReady = config.versionInfo.isPublishedAt(nowUtc);
    final latestVersion = config.versionInfo.latestVersion.trim();
    final skipUpdateVersion = config.versionInfo.skipUpdateVersion.trim();
    final hasUpdate =
        publishReady &&
        latestVersion.isNotEmpty &&
        (skipUpdateVersion.isEmpty || latestVersion != skipUpdateVersion) &&
        _compareVersionTriplets(latestVersion, currentVersion) > 0;
    final isForce = config.versionInfo.isForce && hasUpdate;
    final skippedUpdateVersion = prefs.skippedUpdateVersion.trim();
    final skippedThisVersion =
        latestVersion.isNotEmpty &&
        skippedUpdateVersion.isNotEmpty &&
        _compareVersionTriplets(latestVersion, skippedUpdateVersion) == 0;

    final showWhenUpToDate = config.announcement.showWhenUpToDate;
    final announcementId = config.announcement.id;
    final hasUnseenAnnouncement =
        announcementId > 0 && announcementId != prefs.lastSeenAnnouncementId;
    final shouldShow =
        isForce ||
        (hasUpdate && !skippedThisVersion) ||
        (showWhenUpToDate && hasUnseenAnnouncement);
    if (!shouldShow) return;

    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;

    final action = await UpdateAnnouncementDialog.show(
      dialogContext,
      config: config,
      currentVersion: currentVersion,
    );
    if (!_isMounted() || isForce) return;
    if (action == AnnouncementAction.update ||
        action == AnnouncementAction.later) {
      _bootstrapAdapter.setLastSeenAnnouncement(
        ref: ref,
        version: currentVersion,
        announcementId: config.announcement.id,
      );
    }
    if (action == AnnouncementAction.later && hasUpdate) {
      _bootstrapAdapter.setSkippedUpdateVersion(
        ref: ref,
        version: latestVersion,
      );
    }
  }

  Future<void> _maybeShowNoticeWithConfig({
    required WidgetRef ref,
    required UpdateAnnouncementConfig config,
    required AppPreferences prefs,
  }) async {
    if (!config.noticeEnabled) return;
    final notice = config.notice;
    if (notice == null || !notice.hasContents) return;

    final noticeHash = _hashNotice(notice);
    if (noticeHash.isEmpty) return;
    if (prefs.lastSeenNoticeHash.trim() == noticeHash) return;

    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;

    final acknowledged = await NoticeDialog.show(dialogContext, notice: notice);
    if (!_isMounted() || acknowledged != true) return;
    _bootstrapAdapter.setLastSeenNoticeHash(ref, noticeHash);
  }

  String _hashNotice(UpdateNotice notice) {
    final buffer = StringBuffer();
    buffer.write(notice.title.trim());
    final localeKeys = notice.contentsByLocale.keys.toList()..sort();
    for (final key in localeKeys) {
      buffer.write('|$key=');
      final entries = notice.contentsByLocale[key] ?? const <String>[];
      for (final line in entries) {
        buffer.write(line.trim());
        buffer.write('\n');
      }
    }
    if (notice.fallbackContents.isNotEmpty) {
      buffer.write('|fallback=');
      for (final line in notice.fallbackContents) {
        buffer.write(line.trim());
        buffer.write('\n');
      }
    }
    final raw = buffer.toString().trim();
    if (raw.isEmpty) return '';
    return sha1.convert(utf8.encode(raw)).toString();
  }
}
