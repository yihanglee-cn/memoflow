import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/logs/log_manager.dart';
import '../../data/models/app_preferences.dart';
import '../../data/models/local_memo.dart';
import '../../core/top_toast.dart';
import '../../features/memos/memo_detail_screen.dart';
import '../../features/memos/note_input_sheet.dart';
import '../widgets/home_widget_service.dart';
import '../../features/share/share_handler.dart';
import '../../i18n/strings.g.dart';
import '../../presentation/navigation/app_navigator.dart';
import '../../state/memos/app_bootstrap_adapter_provider.dart';
import '../app/app_sync_orchestrator.dart';

enum _StartupAction { share, widget, launchAction, none }

class StartupCoordinator {
  StartupCoordinator({
    required AppBootstrapAdapter bootstrapAdapter,
    required AppSyncOrchestrator syncOrchestrator,
    required AppNavigator appNavigator,
    required GlobalKey<NavigatorState> navigatorKey,
    required WidgetRef ref,
    required bool Function() isMounted,
  }) : _bootstrapAdapter = bootstrapAdapter,
       _syncOrchestrator = syncOrchestrator,
       _appNavigator = appNavigator,
       _navigatorKey = navigatorKey,
       _ref = ref,
       _isMounted = isMounted;

  final AppBootstrapAdapter _bootstrapAdapter;
  final AppSyncOrchestrator _syncOrchestrator;
  final AppNavigator _appNavigator;
  final GlobalKey<NavigatorState> _navigatorKey;
  final WidgetRef _ref;
  final bool Function() _isMounted;

  HomeWidgetLaunchPayload? _pendingWidgetLaunch;
  SharePayload? _pendingSharePayload;
  bool _shareHandlingScheduled = false;
  bool _widgetHandlingScheduled = false;
  bool _startupHandled = false;
  bool _startupScheduled = false;
  String? _startupScheduleKey;
  String? _startupLogKey;
  String? _startupDebugKey;
  String? _startupRetryKey;
  int _startupRetryCount = 0;
  bool _startupRetryScheduled = false;
  _StartupAction? _lastStartupAction;
  Future<void>? _pendingWidgetLaunchLoad;
  Future<void>? _pendingShareLoad;

  Future<void> loadPendingLaunchSources() {
    _pendingWidgetLaunchLoad = _loadPendingWidgetLaunch();
    _pendingShareLoad = _loadPendingShare();
    return Future.wait(<Future<void>>[
      _pendingWidgetLaunchLoad!,
      _pendingShareLoad!,
    ], eagerError: false);
  }

  Future<void> handleWidgetLaunch(HomeWidgetLaunchPayload payload) async {
    _pendingWidgetLaunch = payload;
    if (_startupHandled) {
      _logStartupInfo(
        'Startup: runtime_widget',
        context: _buildStartupContext(phase: 'runtime', source: 'launch'),
      );
      _scheduleWidgetHandling();
      return;
    }
    _requestStartupHandlingFromState(source: 'launch');
  }

  Future<void> handleShareLaunch(SharePayload payload) async {
    _pendingSharePayload = payload;
    if (_startupHandled) {
      _logStartupInfo(
        'Startup: runtime_share',
        context: _buildStartupContext(
          phase: 'runtime',
          source: 'launch',
          extra: _sharePayloadContext(payload),
        ),
      );
      _scheduleShareHandling();
      return;
    }
    _requestStartupHandlingFromState(source: 'launch');
  }

  void onPrefsLoaded({String? source}) {
    _requestStartupHandlingFromState(source: source ?? 'prefs_loaded');
  }

  void onSessionChanged({String? source}) {
    _requestStartupHandlingFromState(source: source ?? 'session');
  }

  void onLocalLibraryChanged({String? source}) {
    _requestStartupHandlingFromState(source: source ?? 'local_library');
  }

  void onBuild({
    required bool prefsLoaded,
    required bool hasWorkspace,
    required bool hasAccount,
    required AppPreferences prefs,
    String? source,
    bool force = false,
  }) {
    _requestStartupHandling(
      prefsLoaded: prefsLoaded,
      hasWorkspace: hasWorkspace,
      hasAccount: hasAccount,
      prefs: prefs,
      source: source ?? 'build',
      force: force,
    );
  }

  void scheduleShareHandling() {
    _scheduleShareHandling();
  }

  void scheduleWidgetHandling() {
    _scheduleWidgetHandling();
  }

  void dispose() {
    _startupHandled = true;
  }

  Future<void> openQuickInput({required bool autoFocus}) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    _appNavigator.openAllMemos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sheetContext = _navigatorKey.currentContext;
      if (sheetContext != null) {
        NoteInputSheet.show(sheetContext, autoFocus: autoFocus);
      }
    });
  }

  Future<void> _loadPendingWidgetLaunch() async {
    final payload = await HomeWidgetService.consumePendingLaunch();
    if (!_isMounted() || payload == null) return;
    _pendingWidgetLaunch = payload;
    if (_startupHandled) {
      _logStartupInfo(
        'Startup: runtime_widget',
        context: _buildStartupContext(phase: 'runtime', source: 'pending'),
      );
      _scheduleWidgetHandling();
      return;
    }
    _requestStartupHandlingFromState(source: 'pending');
  }

  Future<void> _loadPendingShare() async {
    final payload = await ShareHandlerService.consumePendingShare();
    if (!_isMounted() || payload == null) return;
    _pendingSharePayload = payload;
    if (_startupHandled) {
      _logStartupInfo(
        'Startup: runtime_share',
        context: _buildStartupContext(
          phase: 'runtime',
          source: 'pending',
          extra: _sharePayloadContext(payload),
        ),
      );
      _scheduleShareHandling();
      return;
    }
    _requestStartupHandlingFromState(source: 'pending');
  }

  void _scheduleWidgetHandling() {
    if (_widgetHandlingScheduled) return;
    _widgetHandlingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _widgetHandlingScheduled = false;
      if (!_isMounted()) return;
      _handlePendingWidgetAction();
    });
  }

  void _scheduleShareHandling() {
    if (_shareHandlingScheduled) return;
    _shareHandlingScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareHandlingScheduled = false;
      if (!_isMounted()) return;
      _handlePendingShare();
    });
  }

  Future<void> _awaitPendingLaunchSources() async {
    final futures = <Future<void>>[];
    final widgetLoad = _pendingWidgetLaunchLoad;
    if (widgetLoad != null) futures.add(widgetLoad);
    final shareLoad = _pendingShareLoad;
    if (shareLoad != null) futures.add(shareLoad);
    if (futures.isEmpty) return;
    try {
      await Future.wait(futures);
    } catch (_) {}
  }

  Map<String, Object?> _sharePayloadContext(SharePayload payload) {
    return <String, Object?>{
      'shareType': payload.type.name,
      'sharePathsCount': payload.paths.length,
      'shareHasText': (payload.text ?? '').trim().isNotEmpty,
    };
  }

  Map<String, Object?> _buildStartupContext({
    String? phase,
    String? source,
    bool? prefsLoaded,
    bool? hasWorkspace,
    bool? hasAccount,
    AppPreferences? prefs,
    _StartupAction? action,
    String? reason,
    int? retryCount,
    Map<String, Object?>? extra,
  }) {
    final context = <String, Object?>{
      if (phase != null) 'phase': phase,
      if (source != null) 'source': source,
      if (prefsLoaded != null) 'prefsLoaded': prefsLoaded,
      if (hasWorkspace != null) 'hasWorkspace': hasWorkspace,
      if (hasAccount != null) 'hasAccount': hasAccount,
      'pendingShare': _pendingSharePayload != null,
      'pendingWidget': _pendingWidgetLaunch != null,
      if (prefs != null) 'launchAction': prefs.launchAction.name,
      if (action != null) 'action': action.name,
      if (reason != null) 'reason': reason,
      if (retryCount != null) 'retryCount': retryCount,
    };
    if (extra != null) {
      context.addAll(extra);
    }
    return context;
  }

  void _logStartupInfo(
    String event, {
    Map<String, Object?>? context,
    String? key,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final snapshot = key ?? '$event|${context ?? const <String, Object?>{}}';
    if (_startupLogKey == snapshot) return;
    _startupLogKey = snapshot;
    LogManager.instance.info(
      event,
      context: context,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _logStartupDebug(
    String event, {
    Map<String, Object?>? context,
    String? key,
  }) {
    final snapshot = key ?? '$event|${context ?? const <String, Object?>{}}';
    if (_startupDebugKey == snapshot) return;
    _startupDebugKey = snapshot;
    LogManager.instance.debug(event, context: context);
  }

  void _requestStartupHandlingFromState({String? source}) {
    try {
      final prefsLoaded = _bootstrapAdapter.readPreferencesLoaded(_ref);
      final prefs = _bootstrapAdapter.readPreferences(_ref);
      final session = _bootstrapAdapter.readSession(_ref);
      final hasAccount = session?.currentAccount != null;
      final hasWorkspace =
          hasAccount || _bootstrapAdapter.readCurrentLocalLibrary(_ref) != null;
      _requestStartupHandling(
        prefsLoaded: prefsLoaded,
        hasWorkspace: hasWorkspace,
        hasAccount: hasAccount,
        prefs: prefs,
        source: source,
      );
    } catch (e, st) {
      _logStartupInfo(
        'Startup: state_read_failed',
        context: _buildStartupContext(
          source: source,
          reason: 'state_read_failed',
        ),
        error: e,
        stackTrace: st,
      );
      final action = _pendingSharePayload != null
          ? _StartupAction.share
          : (_pendingWidgetLaunch != null
                ? _StartupAction.widget
                : _StartupAction.none);
      if (action != _StartupAction.none) {
        _scheduleStartupRetry(action: action, reason: 'state_read_failed');
      }
    }
  }

  _StartupAction _selectStartupAction(AppPreferences prefs) {
    if (_pendingSharePayload != null) return _StartupAction.share;
    if (_pendingWidgetLaunch != null) return _StartupAction.widget;
    if (prefs.launchAction != LaunchAction.none) {
      return _StartupAction.launchAction;
    }
    return _StartupAction.none;
  }

  String _selectStartupReason(AppPreferences prefs) {
    if (_pendingSharePayload != null) return 'pending_share';
    if (_pendingWidgetLaunch != null) return 'pending_widget';
    if (prefs.launchAction != LaunchAction.none) return 'prefs_launch_action';
    return 'none';
  }

  String? _evaluateShareBlockReason({
    required bool prefsLoaded,
    required AppPreferences prefs,
    required bool hasAccount,
    required bool hasNavigator,
    required bool hasContext,
  }) {
    if (!prefsLoaded) return 'prefs_not_loaded';
    if (!hasAccount) return 'no_account';
    if (!hasNavigator) return 'no_navigator';
    if (!hasContext) return 'no_context';
    return null;
  }

  String? _evaluateWidgetBlockReason({
    required bool hasWorkspace,
    required bool hasNavigator,
    required bool hasContext,
  }) {
    if (!hasWorkspace) return 'no_workspace';
    if (!hasNavigator) return 'no_navigator';
    if (!hasContext) return 'no_context';
    return null;
  }

  bool _shouldRetryForReason(String reason) {
    return reason == 'no_navigator' || reason == 'no_context';
  }

  void _scheduleStartupRetry({
    required _StartupAction action,
    required String reason,
  }) {
    if (_startupHandled) return;
    final key =
        '${action.name}|$reason|${_pendingSharePayload != null}|${_pendingWidgetLaunch != null}';
    if (_startupRetryKey != key) {
      _startupRetryKey = key;
      _startupRetryCount = 0;
      _startupRetryScheduled = false;
    }
    if (_startupRetryCount >= 2 || _startupRetryScheduled) return;
    final delay = _startupRetryCount == 0
        ? Duration.zero
        : const Duration(milliseconds: 250);
    _startupRetryCount += 1;
    _startupRetryScheduled = true;
    _logStartupDebug(
      'Startup: retry_scheduled',
      context: _buildStartupContext(
        action: action,
        reason: reason,
        retryCount: _startupRetryCount,
        extra: {'delayMs': delay.inMilliseconds},
      ),
    );
    _logStartupInfo(
      'Startup: scheduled',
      context: _buildStartupContext(
        phase: 'startup',
        source: 'retry',
        action: action,
        reason: reason,
        retryCount: _startupRetryCount,
        extra: {'delayMs': delay.inMilliseconds},
      ),
    );
    void trigger() {
      _startupRetryScheduled = false;
      if (!_isMounted() || _startupHandled) return;
      _scheduleStartupHandling();
    }

    if (delay == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) => trigger());
    } else {
      Future<void>.delayed(delay, trigger);
    }
  }

  void _requestStartupHandling({
    required bool prefsLoaded,
    required bool hasWorkspace,
    required bool hasAccount,
    required AppPreferences prefs,
    String? source,
    bool force = false,
  }) {
    if (_startupHandled) return;
    final action = _selectStartupAction(prefs);
    final key =
        '$prefsLoaded|$hasWorkspace|$hasAccount|${_pendingSharePayload != null}|${_pendingWidgetLaunch != null}|${prefs.launchAction}|$action';
    if (!force) {
      if (_startupScheduleKey == key) return;
      _startupScheduleKey = key;
    }
    final reason = _selectStartupReason(prefs);
    final baseContext = _buildStartupContext(
      phase: 'startup',
      source: source,
      prefsLoaded: prefsLoaded,
      hasWorkspace: hasWorkspace,
      hasAccount: hasAccount,
      prefs: prefs,
      action: action,
      reason: reason,
      retryCount: _startupRetryCount,
    );
    _logStartupInfo('Startup: request', context: baseContext);
    _logStartupDebug('Startup: request', context: baseContext);
    if (!prefsLoaded) {
      _logStartupInfo(
        'Startup: deferred',
        context: _buildStartupContext(
          phase: 'startup',
          source: source,
          prefsLoaded: prefsLoaded,
          hasWorkspace: hasWorkspace,
          hasAccount: hasAccount,
          prefs: prefs,
          action: action,
          reason: 'prefs_not_loaded',
        ),
      );
      return;
    }
    if (!hasWorkspace) {
      _logStartupInfo(
        'Startup: deferred',
        context: _buildStartupContext(
          phase: 'startup',
          source: source,
          prefsLoaded: prefsLoaded,
          hasWorkspace: hasWorkspace,
          hasAccount: hasAccount,
          prefs: prefs,
          action: action,
          reason: 'no_workspace',
        ),
      );
      return;
    }
    if (_scheduleStartupHandling()) {
      _logStartupInfo('Startup: scheduled', context: baseContext);
    }
  }

  bool _scheduleStartupHandling() {
    if (_startupHandled || _startupScheduled) return false;
    _startupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupScheduled = false;
      if (!_isMounted()) return;
      unawaited(_handleStartupActions());
    });
    return true;
  }

  void _handlePrefsLaunchAction(AppPreferences prefs) {
    switch (prefs.launchAction) {
      case LaunchAction.dailyReview:
        _appNavigator.openDailyReview();
        break;
      case LaunchAction.quickInput:
        unawaited(openQuickInput(autoFocus: prefs.quickInputAutoFocus));
        break;
      case LaunchAction.none:
        break;
      case LaunchAction.sync:
        // Deprecated. Kept for backward compatibility with stale in-memory
        // enum values before preferences migration writes back.
        break;
    }
  }

  Future<void> _handleStartupActions() async {
    if (_startupHandled) return;
    await _awaitPendingLaunchSources();
    if (!_isMounted()) return;
    bool prefsLoaded;
    AppPreferences prefs;
    bool hasAccount;
    bool hasWorkspace;
    try {
      prefsLoaded = _bootstrapAdapter.readPreferencesLoaded(_ref);
      prefs = _bootstrapAdapter.readPreferences(_ref);
      final session = _bootstrapAdapter.readSession(_ref);
      hasAccount = session?.currentAccount != null;
      hasWorkspace =
          hasAccount || _bootstrapAdapter.readCurrentLocalLibrary(_ref) != null;
    } catch (e, st) {
      _logStartupInfo(
        'Startup: state_read_failed',
        context: _buildStartupContext(
          phase: 'startup',
          reason: 'state_read_failed',
        ),
        error: e,
        stackTrace: st,
      );
      final action = _pendingSharePayload != null
          ? _StartupAction.share
          : (_pendingWidgetLaunch != null
                ? _StartupAction.widget
                : _StartupAction.none);
      if (action != _StartupAction.none) {
        _scheduleStartupRetry(action: action, reason: 'state_read_failed');
      }
      return;
    }

    if (!prefsLoaded) {
      _logStartupInfo(
        'Startup: deferred',
        context: _buildStartupContext(
          phase: 'startup',
          prefsLoaded: prefsLoaded,
          hasWorkspace: hasWorkspace,
          hasAccount: hasAccount,
          prefs: prefs,
          reason: 'prefs_not_loaded',
        ),
      );
      return;
    }
    if (!hasWorkspace) {
      _logStartupInfo(
        'Startup: deferred',
        context: _buildStartupContext(
          phase: 'startup',
          prefsLoaded: prefsLoaded,
          hasWorkspace: hasWorkspace,
          hasAccount: hasAccount,
          prefs: prefs,
          reason: 'no_workspace',
        ),
      );
      return;
    }

    final action = _selectStartupAction(prefs);
    final selectionReason = _selectStartupReason(prefs);
    if (_lastStartupAction != null && _lastStartupAction != action) {
      _logStartupDebug(
        'Startup: action_changed',
        context: _buildStartupContext(
          phase: 'startup',
          prefsLoaded: prefsLoaded,
          hasWorkspace: hasWorkspace,
          hasAccount: hasAccount,
          prefs: prefs,
          action: action,
          reason: selectionReason,
          extra: {'previousAction': _lastStartupAction!.name},
        ),
      );
    }
    _lastStartupAction = action;
    _logStartupInfo(
      'Startup: select_action',
      context: _buildStartupContext(
        phase: 'startup',
        prefsLoaded: prefsLoaded,
        hasWorkspace: hasWorkspace,
        hasAccount: hasAccount,
        prefs: prefs,
        action: action,
        reason: selectionReason,
      ),
    );
    _logStartupDebug(
      'Startup: select_action',
      context: _buildStartupContext(
        phase: 'startup',
        prefsLoaded: prefsLoaded,
        hasWorkspace: hasWorkspace,
        hasAccount: hasAccount,
        prefs: prefs,
        action: action,
        reason: selectionReason,
        retryCount: _startupRetryCount,
      ),
    );

    final navigatorReady = _navigatorKey.currentState != null;
    final contextReady = _navigatorKey.currentContext != null;
    var handled = false;
    switch (action) {
      case _StartupAction.share:
        handled = _handlePendingShare();
        if (handled) {
          _pendingWidgetLaunch = null;
        }
        break;
      case _StartupAction.widget:
        handled = _handlePendingWidgetAction();
        break;
      case _StartupAction.launchAction:
        _handlePrefsLaunchAction(prefs);
        handled = true;
        break;
      case _StartupAction.none:
        handled = true;
        break;
    }
    if (!handled) {
      String reason = 'unknown';
      if (action == _StartupAction.share) {
        reason =
            _evaluateShareBlockReason(
              prefsLoaded: prefsLoaded,
              prefs: prefs,
              hasAccount: hasAccount,
              hasNavigator: navigatorReady,
              hasContext: contextReady,
            ) ??
            reason;
      } else if (action == _StartupAction.widget) {
        reason =
            _evaluateWidgetBlockReason(
              hasWorkspace: hasWorkspace,
              hasNavigator: navigatorReady,
              hasContext: contextReady,
            ) ??
            reason;
      }
      _logStartupInfo(
        'Startup: deferred',
        context: _buildStartupContext(
          phase: 'startup',
          prefsLoaded: prefsLoaded,
          hasWorkspace: hasWorkspace,
          hasAccount: hasAccount,
          prefs: prefs,
          action: action,
          reason: reason,
        ),
      );
      _logStartupDebug(
        'Startup: deferred',
        context: _buildStartupContext(
          phase: 'startup',
          prefsLoaded: prefsLoaded,
          hasWorkspace: hasWorkspace,
          hasAccount: hasAccount,
          prefs: prefs,
          action: action,
          reason: reason,
          retryCount: _startupRetryCount,
        ),
      );
      if (_shouldRetryForReason(reason)) {
        _scheduleStartupRetry(action: action, reason: reason);
      }
      return;
    }

    _startupHandled = true;
    _logStartupInfo(
      'Startup: handled',
      context: _buildStartupContext(
        phase: 'startup',
        prefsLoaded: prefsLoaded,
        hasWorkspace: hasWorkspace,
        hasAccount: hasAccount,
        prefs: prefs,
        action: action,
      ),
    );
    _logStartupInfo(
      'Startup: autosync',
      context: _buildStartupContext(
        phase: 'startup',
        prefsLoaded: prefsLoaded,
        hasWorkspace: hasWorkspace,
        hasAccount: hasAccount,
        prefs: prefs,
        action: action,
      ),
    );
    await _syncOrchestrator.maybeSyncOnLaunch(prefs);
  }

  bool _handlePendingWidgetAction() {
    final payload = _pendingWidgetLaunch;
    if (payload == null) return false;
    final session = _bootstrapAdapter.readSession(_ref);
    final localLibrary = _bootstrapAdapter.readCurrentLocalLibrary(_ref);
    if (session?.currentAccount == null && localLibrary == null) return false;
    final navigator = _navigatorKey.currentState;
    final context = _navigatorKey.currentContext;
    if (navigator == null || context == null) return false;

    _pendingWidgetLaunch = null;
    switch (payload.widgetType) {
      case HomeWidgetType.dailyReview:
        final memoUid = payload.memoUid?.trim();
        if (memoUid == null || memoUid.isEmpty) {
          _appNavigator.openDailyReview();
          break;
        }
        unawaited(_openWidgetMemoDetail(memoUid));
        break;
      case HomeWidgetType.quickInput:
        final prefs = _bootstrapAdapter.readPreferences(_ref);
        unawaited(openQuickInput(autoFocus: prefs.quickInputAutoFocus));
        break;
      case HomeWidgetType.calendar:
        final epochSec = payload.dayEpochSec;
        if (epochSec == null || epochSec <= 0) {
          _appNavigator.openAllMemos();
          break;
        }
        final selectedDay = DateTime.fromMillisecondsSinceEpoch(
          epochSec * 1000,
          isUtc: true,
        ).toLocal();
        final normalizedSelectedDay = DateTime(
          selectedDay.year,
          selectedDay.month,
          selectedDay.day,
        );
        final now = DateTime.now();
        final normalizedToday = DateTime(now.year, now.month, now.day);
        if (normalizedSelectedDay.isAfter(normalizedToday)) {
          _appNavigator.openAllMemos();
          break;
        }
        _appNavigator.openDayMemos(selectedDay);
        break;
    }
    return true;
  }

  Future<void> _openWidgetMemoDetail(String memoUid) async {
    final row = await _bootstrapAdapter
        .readDatabase(_ref)
        .getMemoByUid(memoUid);
    if (!_isMounted()) return;
    if (row == null) {
      _appNavigator.openDailyReview();
      return;
    }
    final memo = LocalMemo.fromDb(row);
    _appNavigator.openAllMemos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _navigatorKey.currentContext;
      if (context == null) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MemoDetailScreen(initialMemo: memo),
        ),
      );
    });
  }

  bool _handlePendingShare() {
    final payload = _pendingSharePayload;
    if (payload == null) return false;
    if (!_bootstrapAdapter.readPreferencesLoaded(_ref)) return false;
    final prefs = _bootstrapAdapter.readPreferences(_ref);
    if (!prefs.thirdPartyShareEnabled) {
      _logStartupInfo(
        'Startup: share_disabled',
        context: _buildStartupContext(
          phase: _startupHandled ? 'runtime' : 'startup',
          extra: _sharePayloadContext(payload),
        ),
      );
      _pendingSharePayload = null;
      _notifyShareDisabled();
      return true;
    }
    final session = _bootstrapAdapter.readSession(_ref);
    if (session?.currentAccount == null) return false;
    final navigator = _navigatorKey.currentState;
    final context = _navigatorKey.currentContext;
    if (navigator == null || context == null) return false;

    _pendingSharePayload = null;
    _appNavigator.openAllMemos();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted()) return;
      final sheetContext = _navigatorKey.currentContext;
      if (sheetContext == null) return;
      _openShareComposer(sheetContext, payload);
    });
    return true;
  }

  void _openShareComposer(BuildContext context, SharePayload payload) {
    if (payload.type == SharePayloadType.images) {
      if (payload.paths.isEmpty) return;
      NoteInputSheet.show(
        context,
        initialAttachmentPaths: payload.paths,
        initialSelection: const TextSelection.collapsed(offset: 0),
        ignoreDraft: true,
      );
      return;
    }

    final rawText = (payload.text ?? '').trim();
    final url = _extractShareUrl(rawText);
    final text = url == null ? rawText : '[]($url)';
    final selectionOffset = url == null ? text.length : 1;
    NoteInputSheet.show(
      context,
      initialText: text,
      initialSelection: TextSelection.collapsed(offset: selectionOffset),
      ignoreDraft: true,
    );
  }

  String? _extractShareUrl(String raw) {
    final match = RegExp(r'https?://[^\s]+').firstMatch(raw);
    final url = match?.group(0);
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return url;
  }

  void _notifyShareDisabled() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    showTopToast(
      context,
      context.t.strings.legacy.msg_third_party_share_disabled,
    );
  }
}
