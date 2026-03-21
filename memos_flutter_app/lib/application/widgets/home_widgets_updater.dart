import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_localization.dart';
import '../../core/url.dart';
import '../../core/theme_colors.dart';
import '../../data/db/app_database.dart';
import '../../data/models/app_preferences.dart';
import '../../state/memos/app_bootstrap_adapter_provider.dart';
import '../../state/system/session_provider.dart';
import 'home_widget_service.dart';
import 'home_widget_snapshot_builder.dart';

class HomeWidgetsUpdater {
  HomeWidgetsUpdater({
    required AppBootstrapAdapter bootstrapAdapter,
    required bool Function() isMounted,
  }) : _bootstrapAdapter = bootstrapAdapter,
       _isMounted = isMounted;

  final AppBootstrapAdapter _bootstrapAdapter;
  final bool Function() _isMounted;

  Timer? _debounceTimer;
  StreamSubscription<void>? _dbChangesSubscription;
  bool _updating = false;
  bool _queued = false;
  bool _queuedForce = false;
  String? _cachedAvatarKey;
  Uint8List? _cachedAvatarBytes;

  bool get _supportsWidgets =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void bindDatabaseChanges(WidgetRef ref) {
    if (!_supportsWidgets || !_isMounted()) return;
    _dbChangesSubscription?.cancel();
    final database = _tryReadDatabase(ref, source: 'bindDatabaseChanges');
    if (database == null) return;
    _dbChangesSubscription = database.changes.listen((_) {
      if (!_isMounted()) return;
      scheduleUpdate(ref, force: true);
    });
    debugPrint('[HomeWidgetsUpdater] database change binding ready');
  }

  void scheduleUpdate(WidgetRef ref, {bool force = false}) {
    if (!_supportsWidgets || !_isMounted()) return;
    _queuedForce = _queuedForce || force;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!_isMounted()) return;
      final nextForce = _queuedForce;
      _queuedForce = false;
      unawaited(updateIfNeeded(ref, force: nextForce));
    });
  }

  Future<void> updateIfNeeded(WidgetRef ref, {bool force = false}) async {
    if (!_supportsWidgets || !_isMounted()) return;
    if (_updating) {
      _queued = true;
      _queuedForce = _queuedForce || force;
      debugPrint(
        '[HomeWidgetsUpdater] skip because updating; queued force=$_queuedForce',
      );
      return;
    }

    _updating = true;
    debugPrint('[HomeWidgetsUpdater] updateIfNeeded start force=$force');
    try {
      if (!_hasActiveWorkspace(ref)) {
        await _clearWidgets();
        return;
      }
      await _updateDailyReviewWidget(ref);
      await _updateQuickInputWidget(ref);
      await _updateCalendarWidget(ref);
    } catch (error, stackTrace) {
      debugPrint('[HomeWidgetsUpdater] update failed: $error');
      debugPrint('$stackTrace');
      // Ignore widget refresh failures to keep app startup resilient.
    } finally {
      debugPrint('[HomeWidgetsUpdater] updateIfNeeded done queued=$_queued');
      _updating = false;
      if (_isMounted() && _queued) {
        final nextForce = _queuedForce;
        _queued = false;
        _queuedForce = false;
        scheduleUpdate(ref, force: nextForce);
      }
    }
  }

  Future<void> _updateDailyReviewWidget(WidgetRef ref) async {
    if (!_isMounted()) return;
    final prefs = _tryReadPreferences(ref, source: '_updateDailyReviewWidget');
    final database = _tryReadDatabase(ref, source: '_updateDailyReviewWidget');
    final session = _tryReadSession(ref, source: '_updateDailyReviewWidget');
    if (prefs == null || database == null) return;
    final rows = await database.listMemos(state: 'NORMAL', limit: null);
    if (!_isMounted()) return;
    final items = buildDailyReviewWidgetItems(
      rows,
      language: prefs.language,
      now: DateTime.now(),
    );
    final avatarBytes = await _resolveCurrentAvatarBytes(session);
    final localeTag = _localeTagForLanguage(prefs.language);
    final clearAvatar = _shouldClearAvatar(session);
    if (!_isMounted()) return;
    await HomeWidgetService.updateDailyReviewWidget(
      items: items,
      title: trByLanguageKey(
        language: prefs.language,
        key: 'legacy.msg_random_review',
      ),
      fallbackBody: trByLanguageKey(
        language: prefs.language,
        key: 'legacy.msg_remember_moment_feel_warmth_life_take',
      ),
      avatarBytes: avatarBytes,
      clearAvatar: clearAvatar,
      localeTag: localeTag,
    );
  }

  Future<void> _updateQuickInputWidget(WidgetRef ref) async {
    if (!_isMounted()) return;
    final prefs = _tryReadPreferences(ref, source: '_updateQuickInputWidget');
    if (prefs == null) return;
    await HomeWidgetService.updateQuickInputWidget(
      hint: trByLanguageKey(language: prefs.language, key: 'legacy.msg_what_s'),
    );
  }

  Future<void> _updateCalendarWidget(WidgetRef ref) async {
    if (!_isMounted()) return;
    final prefs = _tryReadPreferences(ref, source: '_updateCalendarWidget');
    final database = _tryReadDatabase(ref, source: '_updateCalendarWidget');
    if (prefs == null || database == null) return;
    final session = _tryReadSession(ref, source: '_updateCalendarWidget');
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final rows = await database.listMemos(state: 'NORMAL', limit: null);
    if (!_isMounted()) return;
    final themeColor = prefs.resolveThemeColor(session?.currentKey);
    final snapshot = buildCalendarWidgetSnapshot(
      month: month,
      rows: rows,
      language: prefs.language,
      themeColorArgb: themeColorSpec(themeColor).primary.toARGB32(),
    );
    final filledDays = snapshot.days
        .where((day) => day.isCurrentMonth && day.intensity > 0)
        .length;
    final maxIntensity = snapshot.days.fold<int>(
      0,
      (maxValue, day) => day.intensity > maxValue ? day.intensity : maxValue,
    );
    final maxHeatScore = snapshot.heatScores.fold<int>(
      0,
      (maxValue, entry) =>
          entry.heatScore > maxValue ? entry.heatScore : maxValue,
    );
    debugPrint(
      '[HomeWidgetsUpdater] calendar snapshot month=${snapshot.monthLabel} rows=${rows.length} heatScores=${snapshot.heatScores.length} filledDays=$filledDays maxIntensity=$maxIntensity maxHeatScore=$maxHeatScore theme=${snapshot.themeColorArgb}',
    );
    final result = await HomeWidgetService.updateCalendarWidget(
      snapshot: snapshot,
    );
    debugPrint('[HomeWidgetsUpdater] updateCalendarWidget result=$result');
  }

  void dispose() {
    _debounceTimer?.cancel();
    unawaited(_dbChangesSubscription?.cancel());
  }

  bool _hasActiveWorkspace(WidgetRef ref) {
    final currentKey = _tryReadSession(
      ref,
      source: '_hasActiveWorkspace',
    )?.currentKey?.trim();
    if (currentKey != null && currentKey.isNotEmpty) {
      return true;
    }
    return _bootstrapAdapter.readCurrentLocalLibrary(ref) != null;
  }

  Future<void> _clearWidgets() async {
    _cachedAvatarKey = null;
    _cachedAvatarBytes = null;
    debugPrint('[HomeWidgetsUpdater] clearing persisted home widgets');
    await HomeWidgetService.clearHomeWidgets();
  }

  AppPreferences? _tryReadPreferences(WidgetRef ref, {required String source}) {
    try {
      return _bootstrapAdapter.readPreferences(ref);
    } catch (error) {
      debugPrint('[HomeWidgetsUpdater] skip $source preferences: $error');
      return null;
    }
  }

  AppSessionState? _tryReadSession(WidgetRef ref, {required String source}) {
    try {
      return _bootstrapAdapter.readSession(ref);
    } catch (error) {
      debugPrint('[HomeWidgetsUpdater] skip $source session: $error');
      return null;
    }
  }

  AppDatabase? _tryReadDatabase(WidgetRef ref, {required String source}) {
    try {
      return _bootstrapAdapter.readDatabase(ref);
    } catch (error) {
      debugPrint('[HomeWidgetsUpdater] skip $source database: $error');
      return null;
    }
  }

  Future<Uint8List?> _resolveCurrentAvatarBytes(
    AppSessionState? session,
  ) async {
    final account = session?.currentAccount;
    if (account == null) {
      _cachedAvatarKey = null;
      _cachedAvatarBytes = null;
      return null;
    }

    final rawAvatarUrl = account.user.avatarUrl.trim();
    if (rawAvatarUrl.isEmpty) {
      _cachedAvatarKey = null;
      _cachedAvatarBytes = null;
      return null;
    }

    final resolvedUrl = resolveMaybeRelativeUrl(account.baseUrl, rawAvatarUrl);
    if (resolvedUrl.trim().isEmpty) return null;

    final cacheKey = '${account.key}|$resolvedUrl';
    if (_cachedAvatarKey == cacheKey && _cachedAvatarBytes != null) {
      return _cachedAvatarBytes;
    }

    final inlineBytes = tryDecodeDataUri(resolvedUrl);
    if (inlineBytes != null && inlineBytes.isNotEmpty) {
      _cachedAvatarKey = cacheKey;
      _cachedAvatarBytes = inlineBytes;
      return inlineBytes;
    }

    try {
      final headers = <String, dynamic>{};
      final token = account.personalAccessToken.trim();
      if (token.isNotEmpty &&
          _shouldAttachAvatarAuth(
            baseUrl: account.baseUrl,
            resolvedUrl: resolvedUrl,
          )) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await Dio(
        BaseOptions(
          responseType: ResponseType.bytes,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          headers: headers.isEmpty ? null : headers,
        ),
      ).get<List<int>>(resolvedUrl);
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      _cachedAvatarKey = cacheKey;
      _cachedAvatarBytes = bytes;
      return bytes;
    } catch (error) {
      debugPrint('[HomeWidgetsUpdater] avatar fetch failed: $error');
      return null;
    }
  }

  bool _shouldClearAvatar(AppSessionState? session) {
    final account = session?.currentAccount;
    if (account == null) return true;
    return account.user.avatarUrl.trim().isEmpty;
  }

  bool _shouldAttachAvatarAuth({
    required Uri baseUrl,
    required String resolvedUrl,
  }) {
    final resolved = Uri.tryParse(resolvedUrl);
    if (resolved == null) return false;
    if (!resolved.hasScheme) return true;
    final basePort = baseUrl.hasPort
        ? baseUrl.port
        : _defaultPortForScheme(baseUrl.scheme);
    final resolvedPort = resolved.hasPort
        ? resolved.port
        : _defaultPortForScheme(resolved.scheme);
    return resolved.scheme == baseUrl.scheme &&
        resolved.host == baseUrl.host &&
        resolvedPort == basePort;
  }

  int? _defaultPortForScheme(String scheme) {
    return switch (scheme) {
      'http' => 80,
      'https' => 443,
      _ => null,
    };
  }

  String _localeTagForLanguage(AppLanguage language) {
    return switch (language) {
      AppLanguage.zhHans => 'zh-Hans',
      AppLanguage.zhHantTw => 'zh-Hant-TW',
      AppLanguage.ja => 'ja',
      AppLanguage.de => 'de',
      AppLanguage.system => appLocaleForLanguage(language).languageCode,
      _ => 'en',
    };
  }
}
