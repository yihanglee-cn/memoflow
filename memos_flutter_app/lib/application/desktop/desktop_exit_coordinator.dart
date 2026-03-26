import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/desktop_quick_input_channel.dart';
import '../../data/db/database_registry.dart';
import '../../state/settings/preferences_provider.dart';
import '../../state/system/logging_provider.dart';
import 'desktop_quick_input_controller.dart';
import 'desktop_tray_controller.dart';

class DesktopExitCoordinator with WindowListener {
  static const Duration _closeSubWindowsStepTimeout = Duration(seconds: 2);
  static const Duration _listSubWindowsTimeout = Duration(milliseconds: 400);
  static const Duration _subWindowExitSignalTimeout = Duration(
    milliseconds: 350,
  );
  static const Duration _subWindowCloseTimeout = Duration(milliseconds: 800);
  static const Duration _mainWindowTeardownDelay = Duration(milliseconds: 200);
  static const List<String> _exitStepOrder = <String>[
    'close_sub_windows',
    'unregister_hotkey',
    'dispose_tray',
    'disable_prevent_close',
    'close_main_window',
    'await_main_window_teardown',
    'close_databases',
  ];

  DesktopExitCoordinator._({
    required WidgetRef ref,
    required DesktopQuickInputController quickInputController,
    required Future<void> Function() closeDatabases,
    required Duration mainWindowTeardownDelay,
  }) : _ref = ref,
       _quickInputController = quickInputController,
       _closeDatabases = closeDatabases,
       _mainWindowTeardownDelayOverride = mainWindowTeardownDelay;

  static DesktopExitCoordinator? _instance;

  final WidgetRef _ref;
  final DesktopQuickInputController _quickInputController;
  final Future<void> Function() _closeDatabases;
  final Duration _mainWindowTeardownDelayOverride;
  bool _listenerAttached = false;
  bool _exiting = false;
  Completer<void>? _exitCompleter;
  Timer? _forceExitTimer;

  static DesktopExitCoordinator? get instance => _instance;
  static bool get isReady => _instance != null;

  static DesktopExitCoordinator init({
    required WidgetRef ref,
    required DesktopQuickInputController quickInputController,
    Future<void> Function()? closeDatabases,
    Duration mainWindowTeardownDelay = _mainWindowTeardownDelay,
  }) {
    _instance = DesktopExitCoordinator._(
      ref: ref,
      quickInputController: quickInputController,
      closeDatabases: closeDatabases ?? DatabaseRegistry.closeAll,
      mainWindowTeardownDelay: mainWindowTeardownDelay,
    );
    return _instance!;
  }

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }

  @visibleForTesting
  static List<String> debugExitStepOrder() =>
      List<String>.unmodifiable(_exitStepOrder);

  @visibleForTesting
  static String debugMainWindowTerminationAction() =>
      !kIsWeb && Platform.isWindows ? 'destroy' : 'close';

  @visibleForTesting
  Future<void> debugPerformExit({String? reason, bool force = false}) {
    return _performExit(reason: reason, force: force);
  }

  static Future<void> requestClose({String? source}) async {
    final instance = _instance;
    if (instance == null) return;
    await instance._requestClose(source: source);
  }

  static Future<void> requestExit({String? reason, bool force = false}) async {
    final instance = _instance;
    if (instance == null) return;
    await instance._requestExit(reason: reason, force: force);
  }

  static Future<void> activateMainWindow() async {
    final instance = _instance;
    if (instance == null) return;
    await instance._activateMainWindow();
  }

  Future<void> attachWindowListener() async {
    if (_listenerAttached || kIsWeb || !Platform.isWindows) return;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    _listenerAttached = true;
  }

  Future<void> dispose() async {
    _forceExitTimer?.cancel();
    _forceExitTimer = null;
    if (_listenerAttached) {
      windowManager.removeListener(this);
      _listenerAttached = false;
    }
  }

  @override
  void onWindowClose() {
    if (_exiting) return;
    unawaited(_requestClose(source: 'window_close'));
  }

  Future<void> _requestClose({String? source}) async {
    if (kIsWeb || !Platform.isWindows) {
      await windowManager.close();
      return;
    }
    if (_exiting) return;
    final closeToTray = _ref.read(
      appPreferencesProvider.select((p) => p.windowsCloseToTray),
    );
    if (closeToTray && DesktopTrayController.instance.supported) {
      try {
        await DesktopTrayController.instance.hideToTray();
        return;
      } catch (error, stackTrace) {
        _ref
            .read(logManagerProvider)
            .warn(
              'Hide to tray failed. Falling back to exit.',
              error: error,
              stackTrace: stackTrace,
            );
      }
    }
    await _requestExit(reason: source ?? 'close', force: false);
  }

  Future<void> _requestExit({String? reason, bool force = false}) async {
    if (_exiting) {
      await _exitCompleter?.future;
      return;
    }
    _exiting = true;
    final completer = Completer<void>();
    _exitCompleter = completer;
    _armForceExitFallback();
    unawaited(
      _performExit(reason: reason, force: force).whenComplete(() {
        if (!completer.isCompleted) completer.complete();
      }),
    );
    await completer.future;
  }

  Future<void> _performExit({String? reason, bool force = false}) async {
    if (!kIsWeb && Platform.isWindows) {
      _ref
          .read(logManagerProvider)
          .info(
            'Desktop exit requested',
            context: {'reason': reason ?? 'unknown', 'force': force},
          );
    }
    await _runExitStep(
      _exitStepOrder[0],
      _closeSubWindows,
      timeout: _closeSubWindowsStepTimeout,
    );
    await _runExitStep(
      _exitStepOrder[1],
      () => _quickInputController.unregisterHotKey(),
    );
    await _runExitStep(
      _exitStepOrder[2],
      () => DesktopTrayController.instance.dispose(),
    );
    await _runExitStep(
      _exitStepOrder[3],
      () => windowManager.setPreventClose(false),
    );
    final closeMainWindowSucceeded = await _runExitStep(
      _exitStepOrder[4],
      _terminateMainWindowForExit,
    );
    final teardownDelaySucceeded = await _runExitStep(
      _exitStepOrder[5],
      () => Future<void>.delayed(_mainWindowTeardownDelayOverride),
    );
    if (closeMainWindowSucceeded && teardownDelaySucceeded) {
      _cancelForceExitFallback();
    }
    await _runExitStep(_exitStepOrder[6], _closeDatabases);
  }

  Future<void> _closeSubWindows() async {
    List<int> ids = const <int>[];
    try {
      ids = await DesktopMultiWindow.getAllSubWindowIds().timeout(
        _listSubWindowsTimeout,
        onTimeout: () => const <int>[],
      );
    } catch (_) {}
    final closeTasks = <Future<void>>[];
    for (final id in ids) {
      if (id <= 0) continue;
      closeTasks.add(_closeSubWindow(id));
    }
    if (closeTasks.isEmpty) return;
    await Future.wait(closeTasks);
  }

  Future<void> _closeSubWindow(int id) async {
    try {
      await DesktopMultiWindow.invokeMethod(
        id,
        desktopSubWindowExitMethod,
        null,
      ).timeout(_subWindowExitSignalTimeout);
    } catch (_) {}

    try {
      await WindowController.fromWindowId(
        id,
      ).close().timeout(_subWindowCloseTimeout);
    } catch (_) {}
  }

  Future<void> _activateMainWindow() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      await windowManager.ensureInitialized();
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      if (!await windowManager.isVisible()) {
        await windowManager.show();
      } else {
        await windowManager.show();
      }
      await windowManager.focus();
    } catch (_) {}
    try {
      await DesktopTrayController.instance.showFromTray();
    } catch (_) {}
  }

  Future<void> _terminateMainWindowForExit() async {
    if (!kIsWeb && Platform.isWindows) {
      await windowManager.destroy();
      return;
    }
    await windowManager.close();
  }

  void _armForceExitFallback() {
    _forceExitTimer?.cancel();
    _forceExitTimer = Timer(const Duration(seconds: 3), () {
      if (!_exiting) return;
      try {
        _ref
            .read(logManagerProvider)
            .warn('Desktop force-exit fallback triggered');
      } catch (_) {}
      exit(0);
    });
  }

  void _cancelForceExitFallback() {
    _forceExitTimer?.cancel();
    _forceExitTimer = null;
  }

  Future<bool> _runExitStep(
    String name,
    Future<void> Function() action, {
    Duration timeout = const Duration(seconds: 1),
  }) async {
    try {
      await action().timeout(timeout);
      return true;
    } catch (error, stackTrace) {
      try {
        _ref
            .read(logManagerProvider)
            .warn(
              'Exit step failed: $name',
              error: error,
              stackTrace: stackTrace,
            );
      } catch (_) {}
      return false;
    }
  }
}
