import '../../core/theme_colors.dart';
import 'app_preferences.dart';
import 'device_preferences.dart';
import 'workspace_preferences.dart';

class ResolvedAppSettings {
  const ResolvedAppSettings({
    required this.device,
    required this.workspace,
    required this.workspaceKey,
    required this.hasWorkspace,
  });

  final DevicePreferences device;
  final WorkspacePreferences workspace;
  final String? workspaceKey;
  final bool hasWorkspace;

  AppThemeColor get resolvedThemeColor =>
      workspace.themeColorOverride ?? device.themeColor;

  CustomThemeSettings get resolvedCustomTheme =>
      workspace.customThemeOverride ?? device.customTheme;

  AppPreferences toLegacyAppPreferences() {
    final normalizedKey = workspaceKey?.trim();
    final hasKey = normalizedKey != null && normalizedKey.isNotEmpty;
    return AppPreferences.defaults.copyWith(
      language: device.language,
      hasSelectedLanguage: device.hasSelectedLanguage,
      onboardingMode: device.onboardingMode,
      homeInitialLoadingOverlayShown: device.homeInitialLoadingOverlayShown,
      fontSize: device.fontSize,
      lineHeight: device.lineHeight,
      fontFamily: device.fontFamily,
      fontFile: device.fontFile,
      collapseLongContent: workspace.collapseLongContent,
      collapseReferences: workspace.collapseReferences,
      showEngagementInAllMemoDetails: workspace.showEngagementInAllMemoDetails,
      launchAction: device.launchAction,
      autoSyncOnStartAndResume: workspace.autoSyncOnStartAndResume,
      quickInputAutoFocus: device.quickInputAutoFocus,
      confirmExitOnBack: device.confirmExitOnBack,
      hapticsEnabled: device.hapticsEnabled,
      useLegacyApi: workspace.defaultUseLegacyApi,
      networkLoggingEnabled: device.networkLoggingEnabled,
      themeMode: device.themeMode,
      themeColor: device.themeColor,
      customTheme: device.customTheme,
      accountThemeColors: hasKey && workspace.themeColorOverride != null
          ? {normalizedKey: workspace.themeColorOverride!}
          : const {},
      accountCustomThemes: hasKey && workspace.customThemeOverride != null
          ? {normalizedKey: workspace.customThemeOverride!}
          : const {},
      showDrawerExplore: workspace.showDrawerExplore,
      showDrawerDailyReview: workspace.showDrawerDailyReview,
      showDrawerAiSummary: workspace.showDrawerAiSummary,
      showDrawerResources: workspace.showDrawerResources,
      showDrawerArchive: workspace.showDrawerArchive,
      homeQuickActionPrimary: workspace.homeQuickActionPrimary,
      homeQuickActionSecondary: workspace.homeQuickActionSecondary,
      homeQuickActionTertiary: workspace.homeQuickActionTertiary,
      aiSummaryAllowPrivateMemos: workspace.aiSummaryAllowPrivateMemos,
      thirdPartyShareEnabled: device.thirdPartyShareEnabled,
      windowsCloseToTray: device.windowsCloseToTray,
      memoToolbarPreferences: workspace.memoToolbarPreferences,
      desktopShortcutBindings: device.desktopShortcutBindings,
      lastSeenAppVersion: device.lastSeenAppVersion,
      acceptedLegalDocumentsHash: device.acceptedLegalDocumentsHash,
      acceptedLegalDocumentsAt: device.acceptedLegalDocumentsAt,
      skippedUpdateVersion: device.skippedUpdateVersion,
      lastSeenAnnouncementVersion: device.lastSeenAnnouncementVersion,
      lastSeenAnnouncementId: device.lastSeenAnnouncementId,
      lastSeenNoticeHash: device.lastSeenNoticeHash,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ResolvedAppSettings &&
        workspaceKey == other.workspaceKey &&
        hasWorkspace == other.hasWorkspace &&
        device == other.device &&
        workspace == other.workspace;
  }

  @override
  int get hashCode =>
      Object.hash(device, workspace, workspaceKey, hasWorkspace);
}
