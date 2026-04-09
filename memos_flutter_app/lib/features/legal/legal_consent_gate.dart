import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/desktop/desktop_exit_coordinator.dart';
import '../../application/legal/legal_consent_policy.dart';
import '../../core/memoflow_palette.dart';
import '../../data/models/device_preferences.dart';
import '../../i18n/strings.g.dart';
import '../../state/settings/device_preferences_provider.dart';

class LegalConsentGate extends ConsumerStatefulWidget {
  const LegalConsentGate({
    super.key,
    required this.child,
    required this.placeholder,
  });

  final Widget child;
  final Widget placeholder;

  @override
  ConsumerState<LegalConsentGate> createState() => _LegalConsentGateState();
}

class _LegalConsentGateState extends ConsumerState<LegalConsentGate> {
  String? _currentAppVersion;
  String? _lastStampedVersion;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCurrentAppVersion());
  }

  Future<void> _loadCurrentAppVersion() async {
    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version.trim();
    } catch (_) {}
    if (version.isEmpty) {
      version = MemoFlowLegalConsentPolicy.requiredSinceAppVersion;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _currentAppVersion = version;
    });
  }

  void _scheduleLastSeenVersionStamp(
    DevicePreferences prefs,
    String currentAppVersion,
  ) {
    if (prefs.lastSeenAppVersion.trim() == currentAppVersion) {
      _lastStampedVersion = currentAppVersion;
      return;
    }
    if (_lastStampedVersion == currentAppVersion) {
      return;
    }
    _lastStampedVersion = currentAppVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(devicePreferencesProvider.notifier)
          .setLastSeenAppVersion(currentAppVersion);
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(devicePreferencesProvider);
    final currentAppVersion = _currentAppVersion;
    if (currentAppVersion == null) {
      return widget.placeholder;
    }
    final needsConsent = MemoFlowLegalConsentPolicy.requiresConsent(
      prefs: prefs,
      currentAppVersion: currentAppVersion,
    );
    if (!needsConsent) {
      _scheduleLastSeenVersionStamp(prefs, currentAppVersion);
      return widget.child;
    }
    return LegalConsentScreen(currentAppVersion: currentAppVersion);
  }
}

class LegalConsentScreen extends ConsumerStatefulWidget {
  const LegalConsentScreen({super.key, required this.currentAppVersion});

  final String currentAppVersion;

  @override
  ConsumerState<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends ConsumerState<LegalConsentScreen> {
  bool _agreed = false;
  bool _submitting = false;

  Future<void> _openExternalLink(BuildContext context, String rawUrl) async {
    final uri = Uri.parse(rawUrl);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.t.strings.legacy.msg_unable_open_browser_try),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t.strings.legacy.msg_failed_open_try)),
      );
    }
  }

  Future<void> _exitApp() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      await DesktopExitCoordinator.requestExit(
        reason: 'legal_consent_declined',
      );
      return;
    }
    await SystemNavigator.pop();
  }

  void _agreeAndContinue() {
    if (_submitting || !_agreed) {
      return;
    }
    setState(() {
      _submitting = true;
    });
    ref
        .read(devicePreferencesProvider.notifier)
        .acceptLegalDocuments(
          hash: MemoFlowLegalConsentPolicy.currentDocumentsHash,
          appVersion: widget.currentAppVersion,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? MemoFlowPalette.backgroundDark
        : MemoFlowPalette.backgroundLight;
    final card = isDark ? MemoFlowPalette.cardDark : MemoFlowPalette.cardLight;
    final textMain = isDark
        ? MemoFlowPalette.textDark
        : MemoFlowPalette.textLight;
    final textMuted = textMain.withValues(alpha: isDark ? 0.58 : 0.66);
    final border = isDark
        ? MemoFlowPalette.borderDark
        : MemoFlowPalette.borderLight;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bg,
        body: Stack(
          children: [
            if (isDark)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [const Color(0xFF0B0B0B), bg, bg],
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        margin: const EdgeInsets.only(bottom: 18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                              color: MemoFlowPalette.primary.withValues(
                                alpha: isDark ? 0.18 : 0.16,
                              ),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'assets/splash/splash_logo_native.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      Text(
                        context.t.strings.legalConsent.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: textMain,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.t.strings.legalConsent.description,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'v${widget.currentAppVersion}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: border),
                          boxShadow: isDark
                              ? null
                              : [
                                  BoxShadow(
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                    color: Colors.black.withValues(alpha: 0.06),
                                  ),
                                ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              context.t.strings.legalConsent.linksHint,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: textMuted,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                _InlineLink(
                                  text: context
                                      .t
                                      .strings
                                      .legacy
                                      .msg_about_user_agreement,
                                  onTap: () => _openExternalLink(
                                    context,
                                    MemoFlowLegalConsentPolicy
                                        .termsOfServiceUrl,
                                  ),
                                ),
                                Text(
                                  '/',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: textMuted,
                                  ),
                                ),
                                _InlineLink(
                                  text: context
                                      .t
                                      .strings
                                      .legacy
                                      .msg_about_privacy_policy,
                                  onTap: () => _openExternalLink(
                                    context,
                                    MemoFlowLegalConsentPolicy.privacyPolicyUrl,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            CheckboxListTile(
                              value: _agreed,
                              onChanged: (value) {
                                setState(() {
                                  _agreed = value ?? false;
                                });
                              },
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                context.t.strings.legalConsent.acknowledge,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.45,
                                  color: textMain,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: (_submitting || !_agreed)
                              ? null
                              : _agreeAndContinue,
                          style: FilledButton.styleFrom(
                            backgroundColor: MemoFlowPalette.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  context.t.strings.legalConsent.continueAction,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _submitting ? null : _exitApp,
                        child: Text(context.t.strings.legalConsent.exitAction),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineLink extends StatelessWidget {
  const _InlineLink({required this.text, required this.onTap});

  final String text;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => unawaited(onTap()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          text,
          style: TextStyle(
            color: MemoFlowPalette.primary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: MemoFlowPalette.primary,
          ),
        ),
      ),
    );
  }
}
