import 'dart:async';
import 'dart:ui' show ImageFilter, PointerDeviceKind;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/app/app_sync_orchestrator.dart';
import 'application/desktop/desktop_quick_input_controller.dart';
import 'application/desktop/desktop_window_resize_frame.dart';
import 'application/desktop/desktop_window_manager.dart';
import 'application/desktop/desktop_exit_coordinator.dart';
import 'application/desktop/single_instance_coordinator.dart';
import 'application/quick_input/quick_input_service.dart';
import 'application/startup/startup_coordinator.dart';
import 'application/sync/sync_feedback_presenter.dart';
import 'application/updates/update_announcement_runner.dart';
import 'application/widgets/home_widgets_updater.dart';
import 'core/app_localization.dart';
import 'core/app_theme.dart';
import 'core/startup_timing.dart';
import 'application/desktop/desktop_settings_window.dart';
import 'core/font_loader.dart' as app_font;
import 'core/memoflow_palette.dart';
import 'data/models/device_preferences.dart';
import 'data/models/local_library.dart';
import 'features/home/main_home_page.dart';
import 'features/image_editor/i18n.dart';
import 'features/lock/app_lock_gate.dart';
import 'features/memos/memos_list_screen.dart';
import 'features/share/share_handler.dart';
import 'application/widgets/home_widget_service.dart';
import 'i18n/strings.g.dart';
import 'private_hooks/private_extension_bundle_provider.dart';
import 'presentation/navigation/app_navigator.dart';
import 'presentation/reminders/reminder_tap_handler.dart';
import 'state/system/local_library_provider.dart';
import 'state/memos/app_bootstrap_adapter_provider.dart';
import 'state/memos/app_bootstrap_controller.dart';
import 'state/settings/device_preferences_provider.dart';
import 'state/settings/resolved_preferences_provider.dart';
import 'state/system/session_provider.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppNavigator _appNavigator = AppNavigator(_navigatorKey);
  final _mainHomePageKey = GlobalKey<State<StatefulWidget>>();
  late final AppBootstrapAdapter _bootstrapAdapter;
  late final AppBootstrapController _bootstrapController;
  late final AppSyncOrchestrator _syncOrchestrator;
  late final StartupCoordinator _startupCoordinator;
  late final DesktopQuickInputController _desktopQuickInputController;
  late final DesktopWindowManager _desktopWindowManager;
  DesktopExitCoordinator? _exitCoordinator;
  late final HomeWidgetsUpdater _homeWidgetsUpdater;
  late final UpdateAnnouncementRunner _updateAnnouncementRunner;
  late final SyncFeedbackPresenter _syncFeedbackPresenter;
  final app_font.FontLoader _fontLoader = app_font.FontLoader();
  ProviderSubscription<bool>? _prefsLoadedSub;
  ProviderSubscription<AsyncValue<AppSessionState>>? _sessionSub;
  ProviderSubscription<LocalLibrary?>? _localLibrarySub;
  AppLocale? _activeLocale;
  bool _loggedAppInitState = false;
  bool _loggedAppBuildStart = false;
  bool _loggedAppBuildEnd = false;
  bool _deferredWidgetRefresh = false;
  bool _deferredResumeSync = false;

  Future<void> _ensureFontLoaded(DevicePreferences prefs) async {
    await _fontLoader.ensureLoaded(
      prefs,
      onLoaded: () {
        if (!mounted) return;
        setState(() {});
      },
    );
  }

  Future<void> _applyDebugScreenshotMode(bool enabled) async {
    if (!kDebugMode) return;
    try {
      if (enabled) {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: const <SystemUiOverlay>[],
        );
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }

  void _scheduleHomeWidgetRefresh({bool force = false}) {
    if (_startupCoordinator.shouldDeferHeavyStartupWork) {
      _deferredWidgetRefresh = _deferredWidgetRefresh || force;
      return;
    }
    _homeWidgetsUpdater.scheduleUpdate(ref, force: force);
  }

  void _triggerLifecycleSync({required bool isResume}) {
    if (isResume && _startupCoordinator.shouldDeferHeavyStartupWork) {
      _deferredResumeSync = true;
      return;
    }
    _syncOrchestrator.triggerLifecycleSync(isResume: isResume);
  }

  void _handleStartupCoordinatorChanged() {
    if (!mounted) return;
    if (!_startupCoordinator.shouldDeferHeavyStartupWork) {
      final shouldFlushWidgets = _deferredWidgetRefresh;
      final shouldFlushSync = _deferredResumeSync;
      _deferredWidgetRefresh = false;
      _deferredResumeSync = false;
      if (shouldFlushWidgets) {
        _scheduleHomeWidgetRefresh(force: true);
      }
      if (shouldFlushSync) {
        _syncOrchestrator.triggerLifecycleSync(isResume: true);
      }
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (!_loggedAppInitState) {
      _loggedAppInitState = true;
      StartupTiming.markStep('app_init_state');
    }
    _bootstrapAdapter = ref.read(appBootstrapAdapterProvider);
    _bootstrapController = AppBootstrapController(_bootstrapAdapter);
    _homeWidgetsUpdater = HomeWidgetsUpdater(
      bootstrapAdapter: _bootstrapAdapter,
      isMounted: () => mounted,
    );
    _syncFeedbackPresenter = SyncFeedbackPresenter(
      bootstrapAdapter: _bootstrapAdapter,
      ref: ref,
      navigatorKey: _navigatorKey,
      mainHomePageKey: _mainHomePageKey,
      isMounted: () => mounted,
    );
    _syncOrchestrator = AppSyncOrchestrator(
      ref: ref,
      updateStatsWidgetIfNeeded: ({required bool force}) =>
          _homeWidgetsUpdater.updateIfNeeded(ref, force: force),
      showFeedbackToast: ({required bool succeeded}) => _syncFeedbackPresenter
          .showAutoSyncFeedbackToast(succeeded: succeeded),
      showProgressToast: _syncFeedbackPresenter.showAutoSyncProgressToast,
    );
    _startupCoordinator = StartupCoordinator(
      bootstrapAdapter: _bootstrapAdapter,
      syncOrchestrator: _syncOrchestrator,
      appNavigator: _appNavigator,
      navigatorKey: _navigatorKey,
      ref: ref,
      isMounted: () => mounted,
    );
    _startupCoordinator.addListener(_handleStartupCoordinatorChanged);
    final quickInputService = QuickInputService(
      bootstrapAdapter: _bootstrapAdapter,
    );
    _desktopQuickInputController = DesktopQuickInputController(
      bootstrapAdapter: _bootstrapAdapter,
      quickInputService: quickInputService,
      ref: ref,
      navigatorKey: _navigatorKey,
      ensureMethodHandlerBound: () => _desktopWindowManager.bindMethodHandler(),
      onSubWindowVisibilityChanged:
          ({required int windowId, required bool visible}) {
            _desktopWindowManager.setSubWindowVisibility(
              windowId: windowId,
              visible: visible,
            );
          },
      onWindowIdChanged: (windowId) =>
          _desktopWindowManager.updateQuickInputWindowId(windowId),
      isMounted: () => mounted,
    );
    _desktopWindowManager = DesktopWindowManager(
      bootstrapAdapter: _bootstrapAdapter,
      ref: ref,
      navigatorKey: _navigatorKey,
      quickInputController: _desktopQuickInputController,
      openQuickInput: ({required bool autoFocus}) =>
          _startupCoordinator.openQuickInput(autoFocus: autoFocus),
      isMounted: () => mounted,
      onVisibilityChanged: () {
        if (!mounted) return;
        setState(() {});
      },
    );
    _exitCoordinator = DesktopExitCoordinator.init(
      ref: ref,
      quickInputController: _desktopQuickInputController,
    );
    unawaited(_exitCoordinator?.attachWindowListener());
    _updateAnnouncementRunner = UpdateAnnouncementRunner(
      bootstrapAdapter: _bootstrapAdapter,
      navigatorKey: _navigatorKey,
      isMounted: () => mounted,
    );

    WidgetsBinding.instance.addObserver(this);
    _desktopWindowManager.bindMethodHandler();
    setDesktopSettingsWindowVisibilityListener(({
      required int windowId,
      required bool visible,
    }) {
      _desktopWindowManager.setSubWindowVisibility(
        windowId: windowId,
        visible: visible,
      );
    });
    _desktopWindowManager.configureTrayActions();
    SingleInstanceCoordinator.setActivationHandler(
      DesktopExitCoordinator.activateMainWindow,
    );
    _bootstrapAdapter.readLogManager(ref);
    final privateExtensionBundle = ref.read(privateExtensionBundleProvider);
    HomeWidgetService.setLaunchHandler(_startupCoordinator.handleWidgetLaunch);
    ShareHandlerService.setShareHandler(_startupCoordinator.handleShareLaunch);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startupCoordinator.loadPendingLaunchSources());
      unawaited(privateExtensionBundle.onAppReady(ref));
    });
    _bootstrapController.bind(
      ref: ref,
      syncOrchestrator: _syncOrchestrator,
      scheduleStatsWidgetUpdate: () => _scheduleHomeWidgetRefresh(force: true),
      scheduleShareHandling: _startupCoordinator.scheduleShareHandling,
      ensureFontLoaded: _ensureFontLoaded,
      registerDesktopQuickInputHotKey:
          _desktopQuickInputController.registerHotKey,
      applyDebugScreenshotMode: _applyDebugScreenshotMode,
      reminderTapHandler: ReminderTapHandlerImpl(_navigatorKey).handle,
      scheduleDesktopSubWindowPrewarm: _desktopWindowManager.schedulePrewarm,
    );
    _prefsLoadedSub = ref.listenManual<bool>(devicePreferencesLoadedProvider, (
      previous,
      nextValue,
    ) {
      if (!mounted || !nextValue) return;
      _startupCoordinator.onPrefsLoaded(source: 'prefs_loaded');
    });
    _sessionSub = _bootstrapAdapter.listenSession(ref, (previous, nextValue) {
      if (!mounted) return;
      _homeWidgetsUpdater.bindDatabaseChanges(ref);
      _scheduleHomeWidgetRefresh(force: true);
      _startupCoordinator.onSessionChanged(source: 'session');
    });
    _localLibrarySub = ref.listenManual<LocalLibrary?>(
      currentLocalLibraryProvider,
      (previous, nextValue) {
        if (!mounted) return;
        _homeWidgetsUpdater.bindDatabaseChanges(ref);
        _scheduleHomeWidgetRefresh(force: true);
        _startupCoordinator.onLocalLibraryChanged(source: 'local_library');
      },
    );
    _scheduleHomeWidgetRefresh(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _bootstrapAdapter.resumeWebDavBackupProgress(ref);
        _desktopWindowManager.bindMethodHandler();
        _triggerLifecycleSync(isResume: true);
        _bootstrapController.rescheduleRemindersIfNeeded(ref: ref);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _bootstrapAdapter.pauseWebDavBackupProgress(ref);
        break;
      case AppLifecycleState.inactive:
        _bootstrapAdapter.pauseWebDavBackupProgress(ref);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedAppBuildStart) {
      _loggedAppBuildStart = true;
      StartupTiming.markStep('app_build_start');
    }
    ref.watch(preferencesMigrationBootstrapProvider);
    final devicePrefs = _bootstrapAdapter.watchDevicePreferences(ref);
    final resolvedSettings = _bootstrapAdapter.watchResolvedAppSettings(ref);
    final prefsLoaded = _bootstrapAdapter.watchDevicePreferencesLoaded(ref);
    final session = _bootstrapAdapter.watchSession(ref).valueOrNull;
    final themeColor = resolvedSettings.resolvedThemeColor;
    final customTheme = resolvedSettings.resolvedCustomTheme;
    MemoFlowPalette.applyThemeColor(themeColor, customTheme: customTheme);
    final themeMode = themeModeFor(devicePrefs.themeMode);
    final loggerService = _bootstrapAdapter.watchLoggerService(ref);
    final appLocale = appLocaleForLanguage(devicePrefs.language);
    if (_activeLocale != appLocale) {
      LocaleSettings.setLocale(appLocale);
      _activeLocale = appLocale;
    }
    final screenshotModeEnabled = kDebugMode
        ? _bootstrapAdapter.watchDebugScreenshotMode(ref)
        : false;
    final scale = textScaleFor(devicePrefs.fontSize);
    final blurDesktopMainWindow = _desktopWindowManager.shouldBlurMainWindow;
    if (blurDesktopMainWindow) {
      _desktopWindowManager.scheduleVisibilitySync();
    }
    ImageEditorI18n.apply(devicePrefs.language);
    final deviceLegacyPrefs = devicePrefs.toLegacyAppPreferences();

    if (prefsLoaded) {
      _updateAnnouncementRunner.scheduleIfNeeded(ref);
    }
    final localLibrary = _bootstrapAdapter.watchCurrentLocalLibrary(ref);
    final hasAccount = session?.currentAccount != null;
    final hasWorkspace = hasAccount || localLibrary != null;
    _startupCoordinator.onBuild(
      prefsLoaded: prefsLoaded,
      hasWorkspace: hasWorkspace,
      hasAccount: hasAccount,
      settings: resolvedSettings,
      source: 'build',
    );

    final app = TranslationProvider(
      child: MaterialApp(
        title: 'MemoFlow',
        debugShowCheckedModeBanner: !screenshotModeEnabled,
        theme: applyPreferencesToTheme(
          buildAppTheme(Brightness.light),
          deviceLegacyPrefs,
        ),
        darkTheme: applyPreferencesToTheme(
          buildAppTheme(Brightness.dark),
          deviceLegacyPrefs,
        ),
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.stylus,
            PointerDeviceKind.invertedStylus,
            PointerDeviceKind.trackpad,
          },
        ),
        themeMode: themeMode,
        locale: appLocale.flutterLocale,
        navigatorKey: _navigatorKey,
        supportedLocales: AppLocaleUtils.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        navigatorObservers: [loggerService.navigatorObserver],
        onGenerateRoute: (settings) {
          if (settings.name == '/memos/day') {
            final arg = settings.arguments;
            return MaterialPageRoute<void>(
              builder: (_) => MemosListScreen(
                title: 'MemoFlow',
                state: 'NORMAL',
                showDrawer: true,
                enableCompose: true,
                dayFilter: arg is DateTime ? arg : null,
              ),
            );
          }
          return null;
        },
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final appContent = MediaQuery(
            data: media.copyWith(textScaler: TextScaler.linear(scale)),
            child: AppLockGate(
              navigatorKey: _navigatorKey,
              child: child ?? const SizedBox.shrink(),
            ),
          );
          final windowContent = !blurDesktopMainWindow
              ? appContent
              : (() {
                  final isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  final overlayColor = Colors.black.withValues(
                    alpha: isDark ? 0.26 : 0.12,
                  );

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      appContent,
                      ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: ColoredBox(color: overlayColor),
                        ),
                      ),
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) {
                          unawaited(
                            _desktopWindowManager.focusVisibleSubWindow(),
                          );
                        },
                        child: ClipRect(
                          child: ColoredBox(color: Colors.transparent),
                        ),
                      ),
                    ],
                  );
                })();

          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
            return DesktopWindowResizeFrame(child: windowContent);
          }
          return windowContent;
        },
        home: MainHomePage(
          key: _mainHomePageKey,
          startupCoordinator: _startupCoordinator,
        ),
      ),
    );
    if (!_loggedAppBuildEnd) {
      _loggedAppBuildEnd = true;
      StartupTiming.markStep('app_build_end');
    }
    return app;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    setDesktopSettingsWindowVisibilityListener(null);
    _prefsLoadedSub?.close();
    _sessionSub?.close();
    _localLibrarySub?.close();
    if (kDebugMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _bootstrapController.dispose();
    _startupCoordinator.removeListener(_handleStartupCoordinatorChanged);
    _startupCoordinator.dispose();
    _desktopWindowManager.unbindMethodHandler();
    unawaited(_desktopQuickInputController.unregisterHotKey());
    _homeWidgetsUpdater.dispose();
    unawaited(_exitCoordinator?.dispose());
    super.dispose();
  }
}
