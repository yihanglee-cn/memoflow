import 'dart:ui';

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_localization.dart';
import '../../core/drawer_navigation.dart';
import '../../core/memoflow_palette.dart';
import '../../core/platform_layout.dart';
import '../../core/top_toast.dart';
import '../../core/tags.dart';
import '../../core/uid.dart';
import '../../data/ai/ai_analysis_models.dart';
import '../../data/ai/ai_summary_service.dart';
import '../../data/models/local_memo.dart';
import '../about/about_screen.dart';
import '../explore/explore_screen.dart';
import '../home/app_drawer.dart';
import '../memos/memo_markdown.dart';
import '../memos/memo_detail_screen.dart';
import '../memos/memos_list_screen.dart';
import '../memos/recycle_bin_screen.dart';
import '../notifications/notifications_screen.dart';
import '../resources/resources_screen.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import '../tags/tags_screen.dart';
import '../sync/sync_queue_screen.dart';
import '../../state/settings/ai_settings_provider.dart';
import '../../state/review/ai_analysis_provider.dart';
import '../../state/system/database_provider.dart';
import '../../state/sync/sync_coordinator_provider.dart';
import '../../application/sync/sync_request.dart';
import 'daily_review_screen.dart';
import 'ai_insight_models.dart';
import 'ai_insight_settings_sheet.dart';
import '../../i18n/strings.g.dart';

class AiSummaryScreen extends ConsumerStatefulWidget {
  const AiSummaryScreen({super.key});

  @override
  ConsumerState<AiSummaryScreen> createState() => _AiSummaryScreenState();
}

enum _AiSummaryView { input, report }

class _AiSummaryScreenState extends ConsumerState<AiSummaryScreen> {
  final _reportBoundaryKey = GlobalKey();
  var _range = AiInsightRange.last7Days;
  DateTimeRange? _customRange;
  var _view = _AiSummaryView.input;
  var _isLoading = false;
  var _requestId = 0;
  AiSummaryResult? _summary;
  AiSavedAnalysisReport? _analysisReport;
  var _insightExpanded = false;

  void _navigate(BuildContext context, AppDrawerDestination dest) {
    final route = switch (dest) {
      AppDrawerDestination.memos => const MemosListScreen(
        title: 'MemoFlow',
        state: 'NORMAL',
        showDrawer: true,
        enableCompose: true,
      ),
      AppDrawerDestination.syncQueue => const SyncQueueScreen(),
      AppDrawerDestination.explore => const ExploreScreen(),
      AppDrawerDestination.dailyReview => const DailyReviewScreen(),
      AppDrawerDestination.aiSummary => const AiSummaryScreen(),
      AppDrawerDestination.archived => MemosListScreen(
        title: context.t.strings.legacy.msg_archive,
        state: 'ARCHIVED',
        showDrawer: true,
      ),
      AppDrawerDestination.tags => const TagsScreen(),
      AppDrawerDestination.resources => const ResourcesScreen(),
      AppDrawerDestination.recycleBin => const RecycleBinScreen(),
      AppDrawerDestination.stats => const StatsScreen(),
      AppDrawerDestination.settings => const SettingsScreen(),
      AppDrawerDestination.about => const AboutScreen(),
    };
    closeDrawerThenPushReplacement(context, route);
  }

  void _backToAllMemos(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const MemosListScreen(
          title: 'MemoFlow',
          state: 'NORMAL',
          showDrawer: true,
          enableCompose: true,
        ),
      ),
      (route) => false,
    );
  }

  void _openTag(BuildContext context, String tag) {
    closeDrawerThenPushReplacement(
      context,
      MemosListScreen(
        title: '#$tag',
        state: 'NORMAL',
        tag: tag,
        showDrawer: true,
        enableCompose: true,
      ),
    );
  }

  void _openNotifications(BuildContext context) {
    closeDrawerThenPushReplacement(context, const NotificationsScreen());
  }

  Future<DateTimeRange?> _pickCustomRange(
    BuildContext pickerContext,
    DateTimeRange? currentRange,
  ) {
    final now = DateTime.now();
    final initial =
        currentRange ??
        DateTimeRange(
          start: DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 6)),
          end: DateTime(now.year, now.month, now.day),
        );
    return showDateRangePicker(
      context: pickerContext,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
    );
  }

  Future<void> _openInsightSettings(AiInsightDefinition definition) async {
    if (_isLoading) return;
    final result = await showDialog<AiInsightSettingsResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: AiInsightSettingsSheet(
          definition: definition,
          analysisLoading: _isLoading,
          customRangePicker: _pickCustomRange,
          previewLoader:
              ({
                required range,
                required customRange,
                required allowPublic,
                required allowPrivate,
                required allowProtected,
              }) {
                return _buildPreviewPayload(
                  range: range,
                  customRange: customRange,
                  allowPublic: allowPublic,
                  allowPrivate: allowPrivate,
                  allowProtected: allowProtected,
                );
              },
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _runAnalysis(result);
  }

  Future<void> _runAnalysis(AiInsightSettingsResult result) async {
    if (_isLoading) return;
    final settings = ref.read(aiSettingsProvider);
    final isZh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    if (!settings.hasEnabledEmbeddingProfile) {
      showTopToast(
        context,
        isZh
            ? '请先配置 embedding 模型。'
            : 'Please configure an embedding model first.',
      );
      return;
    }
    if (settings.apiKey.trim().isEmpty) {
      showTopToast(
        context,
        context.t.strings.legacy.msg_enter_api_key_ai_settings,
      );
      return;
    }
    if (settings.apiUrl.trim().isEmpty) {
      showTopToast(
        context,
        context.t.strings.legacy.msg_enter_api_url_ai_settings,
      );
      return;
    }

    final requestId = ++_requestId;
    setState(() {
      _range = result.range;
      _customRange = result.customRange;
      _isLoading = true;
    });
    try {
      final previewPayload = result.previewPayload;
      if (!mounted || !_isLoading || requestId != _requestId) return;
      if (!previewPayload.hasContent || previewPayload.embeddingReady <= 0) {
        setState(() => _isLoading = false);
        showTopToast(
          context,
          isZh
              ? '当前时间范围内还没有可用的索引证据。'
              : 'No indexed evidence is available for this range yet.',
        );
        return;
      }

      final analysisResult = await ref
          .read(aiAnalysisServiceProvider)
          .generateEmotionMap(
            language: context.appLanguage,
            settings: settings,
            range: resolveAiInsightRange(result.range, result.customRange),
            includePublic: result.allowPublic,
            includePrivate: result.allowPrivate,
            includeProtected: result.allowProtected,
            promptTemplate: result.promptTemplate.trim(),
          );
      if (!mounted || !_isLoading || requestId != _requestId) return;
      setState(() {
        _analysisReport = analysisResult;
        _summary = null;
        _view = _AiSummaryView.report;
        _isLoading = false;
        _insightExpanded = false;
      });
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t.strings.legacy.msg_ai_summary_failed(
              formatSummaryError_e: _formatSummaryError(e),
            ),
          ),
        ),
      );
    }
  }

  String _formatSummaryError(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return context
              .t
              .strings
              .legacy
              .msg_connection_timeout_check_network_api_url;
        case DioExceptionType.sendTimeout:
          return context.t.strings.legacy.msg_request_send_timeout_try;
        case DioExceptionType.receiveTimeout:
          return context.t.strings.legacy.msg_server_response_timeout_try;
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          if (code == 401 || code == 403) {
            return context
                .t
                .strings
                .legacy
                .msg_invalid_api_key_insufficient_permissions;
          }
          if (code == 404) {
            return context.t.strings.legacy.msg_api_url_incorrect;
          }
          if (code == 429) {
            return context.t.strings.legacy.msg_too_many_requests_try_later;
          }
          if (code != null) {
            return context.t.strings.legacy.msg_server_returned_error(
              code: code,
            );
          }
          return context.t.strings.legacy.msg_server_response_error;
        case DioExceptionType.connectionError:
          return context.t.strings.legacy.msg_network_connection_failed;
        case DioExceptionType.cancel:
          return context.t.strings.legacy.msg_request_cancelled;
        case DioExceptionType.badCertificate:
          return context.t.strings.legacy.msg_bad_ssl_certificate;
        case DioExceptionType.unknown:
          break;
      }
      return error.message ?? error.toString();
    }
    return error.toString();
  }

  void _cancelSummary() {
    if (!_isLoading) return;
    setState(() {
      _isLoading = false;
      _requestId++;
    });
  }

  String _buildSummaryText({
    required AiSummaryResult summary,
    required bool forMemo,
  }) {
    final title = context.t.strings.legacy.msg_ai_summary_report;
    final header = forMemo ? '# $title' : title;
    final insights = summary.insights.isNotEmpty
        ? summary.insights
        : [context.t.strings.legacy.msg_no_summary_yet];
    final moodTrend = summary.moodTrend.isNotEmpty
        ? summary.moodTrend
        : context.t.strings.legacy.msg_no_mood_trend;
    final keywordText = summary.keywords.isNotEmpty
        ? summary.keywords.map(_normalizeKeyword).join(' ')
        : context.t.strings.legacy.msg_no_keywords;

    final buffer = StringBuffer();
    buffer.writeln(header);
    buffer.writeln('${context.t.strings.legacy.msg_range}: ${_rangeLabel()}');
    buffer.writeln('');
    buffer.writeln(context.t.strings.legacy.msg_key_insights);
    for (final insight in insights) {
      buffer.writeln('- $insight');
    }
    buffer.writeln('');
    buffer.writeln('${context.t.strings.legacy.msg_mood_trend}: $moodTrend');
    buffer.writeln('');
    buffer.writeln('${context.t.strings.legacy.msg_keywords}: $keywordText');
    return buffer.toString().trim();
  }

  String _buildStructuredReportText({
    required AiSavedAnalysisReport report,
    required bool forMemo,
  }) {
    final isZh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    final title = isZh ? '情绪地图' : 'Emotion Map';
    final header = forMemo ? '# $title' : title;
    final buffer = StringBuffer();
    buffer.writeln(header);
    buffer.writeln('${context.t.strings.legacy.msg_range}: ${_rangeLabel()}');
    buffer.writeln('');
    buffer.writeln(report.summary.trim());
    for (final section in report.sections) {
      buffer.writeln('');
      buffer.writeln('## ${section.title}');
      buffer.writeln(section.body.trim());
      final evidences = report.evidences.where(
        (item) => item.sectionKey == section.sectionKey,
      );
      for (final evidence in evidences) {
        buffer.writeln('- ${evidence.quoteText.trim()}');
      }
    }
    if (report.followUpSuggestions.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('## ${isZh ? '后续建议' : 'Follow-up Suggestions'}');
      for (final item in report.followUpSuggestions) {
        buffer.writeln('- ${item.trim()}');
      }
    }
    return buffer.toString().trim();
  }

  Future<void> _shareReport() async {
    final report = _analysisReport;
    final summary = _summary;
    if (summary == null && report == null) {
      showTopToast(context, context.t.strings.legacy.msg_no_summary_share);
      return;
    }
    final text = report != null
        ? _buildStructuredReportText(report: report, forMemo: false)
        : _buildSummaryText(summary: summary!, forMemo: false);
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: context.t.strings.legacy.msg_ai_summary_report,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.strings.legacy.msg_share_failed(e: e)),
        ),
      );
    }
  }

  Future<void> _sharePoster() async {
    final report = _analysisReport;
    final summary = _summary;
    if (summary == null && report == null) {
      showTopToast(context, context.t.strings.legacy.msg_no_summary_share);
      return;
    }
    final boundary = _reportBoundaryKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      showTopToast(context, context.t.strings.legacy.msg_poster_not_ready_yet);
      return;
    }

    try {
      await Future.delayed(const Duration(milliseconds: 30));
      if (!mounted) return;
      final pixelRatio = MediaQuery.of(
        context,
      ).devicePixelRatio.clamp(2.0, 3.0);
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      if (byteData == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.t.strings.legacy.msg_poster_generation_failed,
            ),
          ),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}ai_summary_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      if (!mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: report != null
              ? _buildStructuredReportText(report: report, forMemo: false)
              : _buildSummaryText(summary: summary!, forMemo: false),
          subject: context.t.strings.legacy.msg_ai_summary_report,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.strings.legacy.msg_share_failed(e: e)),
        ),
      );
    }
  }

  Future<void> _saveAsMemo() async {
    final report = _analysisReport;
    final summary = _summary;
    if (summary == null && report == null) {
      showTopToast(context, context.t.strings.legacy.msg_no_summary_save);
      return;
    }

    final content = report != null
        ? _buildStructuredReportText(report: report, forMemo: true)
        : _buildSummaryText(summary: summary!, forMemo: true);
    final uid = generateUid();
    final now = DateTime.now();
    final tags = extractTags(content);
    final db = ref.read(databaseProvider);

    try {
      await db.upsertMemo(
        uid: uid,
        content: content,
        visibility: 'PRIVATE',
        pinned: false,
        state: 'NORMAL',
        createTimeSec: now.toUtc().millisecondsSinceEpoch ~/ 1000,
        updateTimeSec: now.toUtc().millisecondsSinceEpoch ~/ 1000,
        tags: tags,
        attachments: const [],
        location: null,
        relationCount: 0,
        syncState: 1,
      );
      await db.enqueueOutbox(
        type: 'create_memo',
        payload: {
          'uid': uid,
          'content': content,
          'visibility': 'PRIVATE',
          'pinned': false,
          'has_attachments': false,
        },
      );
      unawaited(
        ref
            .read(syncCoordinatorProvider.notifier)
            .requestSync(
              const SyncRequest(
                kind: SyncRequestKind.memos,
                reason: SyncRequestReason.manual,
              ),
            ),
      );
      if (!mounted) return;
      showTopToast(context, context.t.strings.legacy.msg_saved_memo);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.strings.legacy.msg_save_failed_3(e: e)),
        ),
      );
    }
  }

  DateTimeRange _effectiveRange() {
    return resolveAiInsightRange(_range, _customRange);
  }

  String _rangeLabel() {
    return formatAiInsightRangeLabel(_effectiveRange());
  }

  String _reportTitle() {
    final range = _effectiveRange();
    final days = range.end.difference(range.start).inDays + 1;
    if (_range == AiInsightRange.last30Days || days > 7 && days <= 31) {
      return context.t.strings.legacy.msg_month;
    }
    if (_range == AiInsightRange.last7Days || days == 7) {
      return context.t.strings.legacy.msg_week;
    }
    return context.t.strings.legacy.msg_period_review;
  }

  String _reportRangeLabel() {
    return formatAiInsightReportRangeLabel(context, _effectiveRange());
  }

  String _buildInsightMarkdown(AiSummaryResult summary) {
    final insights = summary.insights.isNotEmpty
        ? summary.insights
        : [context.t.strings.legacy.msg_no_summary_yet];
    final moodTrend = summary.moodTrend.isNotEmpty
        ? summary.moodTrend
        : context.t.strings.legacy.msg_no_mood_trend;
    final buffer = StringBuffer();
    buffer.writeln('### ${context.t.strings.legacy.msg_key_insights}');
    buffer.writeln('');
    buffer.writeln('> ${context.t.strings.legacy.msg_intro}: $moodTrend');
    buffer.writeln('');
    for (var i = 0; i < insights.length; i++) {
      final text = insights[i].trim();
      if (text.isEmpty) continue;
      if (i == 0) {
        buffer.writeln('- **$text**');
      } else {
        buffer.writeln('- $text');
      }
    }
    return buffer.toString().trim();
  }

  Future<AiAnalysisPreviewPayload> _buildPreviewPayload({
    required AiInsightRange range,
    required DateTimeRange? customRange,
    required bool allowPublic,
    required bool allowPrivate,
    required bool allowProtected,
  }) async {
    return ref
        .read(aiAnalysisServiceProvider)
        .buildEmotionMapPreview(
          language: context.appLanguage,
          settings: ref.read(aiSettingsProvider),
          range: resolveAiInsightRange(range, customRange),
          includePublic: allowPublic,
          includePrivate: allowPrivate,
          includeProtected: allowProtected,
        );
  }

  PreferredSizeWidget _buildAppBar({
    required BuildContext context,
    required bool isReport,
    required Color bg,
    required Color border,
    required Color textMain,
    required bool useDesktopSidePane,
  }) {
    final enableWindowsDragToMove = Platform.isWindows;
    final titleText = useDesktopSidePane
        ? context.t.strings.aiInsight.title
        : (isReport
              ? context.t.strings.legacy.msg_ai_summary_report
              : context.t.strings.aiInsight.title);
    return AppBar(
      title: IgnorePointer(
        ignoring: enableWindowsDragToMove,
        child: Text(
          titleText,
          style: TextStyle(fontWeight: FontWeight.w700, color: textMain),
        ),
      ),
      centerTitle: !useDesktopSidePane,
      backgroundColor: useDesktopSidePane ? bg : Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: !useDesktopSidePane,
      toolbarHeight: 46,
      leading: useDesktopSidePane
          ? null
          : IconButton(
              icon: const Icon(Icons.arrow_back_ios_new),
              color: textMain,
              onPressed: () => _backToAllMemos(context),
            ),
      actions: isReport
          ? [
              IconButton(
                icon: const Icon(Icons.share),
                color: MemoFlowPalette.primary,
                onPressed: _shareReport,
              ),
            ]
          : (useDesktopSidePane ? [const SizedBox(width: 48)] : null),
      flexibleSpace: enableWindowsDragToMove
          ? const DragToMoveArea(child: SizedBox.expand())
          : (useDesktopSidePane
                ? null
                : ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(color: bg.withValues(alpha: 0.9)),
                    ),
                  )),
      bottom: isReport
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(height: 1, color: border.withValues(alpha: 0.6)),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? MemoFlowPalette.backgroundDark
        : MemoFlowPalette.backgroundLight;
    final card = isDark ? MemoFlowPalette.cardDark : MemoFlowPalette.cardLight;
    final border = isDark
        ? MemoFlowPalette.borderDark
        : MemoFlowPalette.borderLight;
    final textMain = isDark
        ? MemoFlowPalette.textDark
        : MemoFlowPalette.textLight;
    final textMuted = textMain.withValues(alpha: isDark ? 0.6 : 0.5);
    final isReport = _view == _AiSummaryView.report;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useDesktopSidePane = shouldUseDesktopSidePaneLayout(screenWidth);
    final drawerPanel = AppDrawer(
      selected: AppDrawerDestination.aiSummary,
      onSelect: (d) => _navigate(context, d),
      onSelectTag: (t) => _openTag(context, t),
      onOpenNotifications: () => _openNotifications(context),
      embedded: useDesktopSidePane,
    );
    final pageBody = Stack(
      children: [
        if (isReport)
          _buildReportBody(
            bg: bg,
            card: card,
            border: border,
            textMain: textMain,
            textMuted: textMuted,
            summary: _summary ?? AiSummaryResult.empty,
            report: _analysisReport,
          )
        else
          _buildInputBody(
            card: card,
            border: border,
            textMain: textMain,
            textMuted: textMuted,
          ),
        if (isReport)
          _buildBottomBar(
            bg: bg,
            border: border,
            textMain: textMain,
            card: card,
          ),
        if (_isLoading)
          _buildLoadingOverlay(
            bg: bg,
            textMain: textMain,
            textMuted: textMuted,
          ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _backToAllMemos(context);
      },
      child: Scaffold(
        backgroundColor: bg,
        drawer: useDesktopSidePane ? null : drawerPanel,
        appBar: _buildAppBar(
          context: context,
          isReport: isReport,
          bg: bg,
          border: border,
          textMain: textMain,
          useDesktopSidePane: useDesktopSidePane,
        ),
        body: useDesktopSidePane
            ? Row(
                children: [
                  SizedBox(
                    width: kMemoFlowDesktopDrawerWidth,
                    child: drawerPanel,
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
                  Expanded(child: pageBody),
                ],
              )
            : pageBody,
      ),
    );
  }

  Widget _buildInputBody({
    required Color card,
    required Color border,
    required Color textMain,
    required Color textMuted,
  }) {
    final isNarrow = MediaQuery.sizeOf(context).width < 640;
    final crossAxisCount = isNarrow ? 2 : 3;
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = isNarrow ? 20.0 : 28.0;
    final grid = GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visibleAiInsightDefinitions.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: isNarrow ? 0.92 : 1.08,
      ),
      itemBuilder: (context, index) {
        final definition = visibleAiInsightDefinitions[index];
        return _AiInsightCard(
          definition: definition,
          cardColor: card,
          borderColor: border,
          textMain: textMain,
          textMuted: textMuted,
          onTap: () => _openInsightSettings(definition),
        );
      },
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width < 900 ? width : 840),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t.strings.aiInsight.title,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: textMain,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.t.strings.aiInsight.subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: textMuted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  grid,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportBody({
    required Color bg,
    required Color card,
    required Color border,
    required Color textMain,
    required Color textMuted,
    required AiSummaryResult summary,
    required AiSavedAnalysisReport? report,
  }) {
    if (report != null) {
      return _buildStructuredReportBody(
        bg: bg,
        card: card,
        border: border,
        textMain: textMain,
        textMuted: textMuted,
        report: report,
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reportBg = isDark ? bg : const Color(0xFFF7F2EA);
    final reportCard = isDark ? card : const Color(0xFFFFFFFF);
    final cardBorder = isDark ? border : border.withValues(alpha: 0.7);
    final moodWarm = const Color(0xFFF2A167);
    final moodDeep = const Color(0xFFE98157);
    final moodLight = const Color(0xFFF7C796);
    final moodChipBg = moodWarm.withValues(alpha: isDark ? 0.25 : 0.2);
    final moodChipBorder = moodWarm.withValues(alpha: isDark ? 0.45 : 0.35);
    final moodChipText = isDark
        ? textMain.withValues(alpha: 0.9)
        : const Color(0xFF6B5344);
    final title = _reportTitle();
    final dateLabel = _reportRangeLabel();
    final rawKeywords = summary.keywords.isNotEmpty
        ? summary.keywords
        : [context.t.strings.legacy.msg_no_keywords_2];
    final keywords = rawKeywords.map(_normalizeKeyword).toList(growable: false);
    final insightMarkdown = _buildInsightMarkdown(summary);
    final shouldCollapse = insightMarkdown.length > 260;
    final showCollapsed = shouldCollapse && !_insightExpanded;
    final insightStyle = TextStyle(
      fontSize: 14,
      height: 1.7,
      color: textMain.withValues(alpha: isDark ? 0.85 : 0.82),
    );
    Widget insightContent = MemoMarkdown(
      data: insightMarkdown,
      textStyle: insightStyle,
      blockSpacing: 10,
      shrinkWrap: true,
    );
    if (showCollapsed) {
      insightContent = SizedBox(
        height: 260,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: insightContent,
        ),
      );
    }
    final headerTextColor = isDark ? MemoFlowPalette.textLight : textMain;
    final headerTextMuted = headerTextColor.withValues(alpha: 0.6);

    return RepaintBoundary(
      key: _reportBoundaryKey,
      child: Container(
        color: reportBg,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 200),
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: reportCard,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: cardBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 190,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFFFF4E8), Color(0xFFFFE7D6)],
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 170,
                            height: 170,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const RadialGradient(
                                center: Alignment(-0.2, -0.2),
                                radius: 0.9,
                                colors: [
                                  Color(0xFFFBD7B1),
                                  Color(0xFFF4A96F),
                                  Color(0xFFE97B57),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: moodWarm.withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 30,
                          top: 24,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  moodLight.withValues(alpha: 0.9),
                                  moodWarm.withValues(alpha: 0.4),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 28,
                          bottom: 26,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  moodWarm.withValues(alpha: 0.8),
                                  moodDeep.withValues(alpha: 0.5),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: headerTextColor,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                dateLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: headerTextMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final keyword in keywords)
                          _KeywordChip(
                            label: keyword,
                            background: moodChipBg,
                            textColor: moodChipText,
                            borderColor: moodChipBorder,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                    child: Stack(
                      children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOut,
                          child: ClipRect(child: insightContent),
                        ),
                        if (showCollapsed)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              height: 70,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    reportCard.withValues(alpha: 0.0),
                                    reportCard,
                                  ],
                                ),
                              ),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: TextButton.icon(
                                  onPressed: () {
                                    setState(() => _insightExpanded = true);
                                  },
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 18,
                                  ),
                                  label: Text(
                                    context.t.strings.legacy.msg_expand_2,
                                  ),
                                  style: TextButton.styleFrom(
                                    foregroundColor: textMain.withValues(
                                      alpha: 0.65,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Center(
                      child: Text(
                        context.t.strings.legacy.msg_generated_ai_memoflow,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: textMuted.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar({
    required Color bg,
    required Color border,
    required Color textMain,
    required Color card,
  }) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [bg, bg.withValues(alpha: 0.9), Colors.transparent],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _sharePoster,
                  icon: const Icon(Icons.palette, size: 20),
                  label: Text(
                    context.t.strings.legacy.msg_generate_share_poster,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: MemoFlowPalette.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _saveAsMemo,
                  icon: const Icon(Icons.save_as, size: 20),
                  label: Text(context.t.strings.legacy.msg_save_memo),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textMain,
                    side: BorderSide(color: border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    backgroundColor: card,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _normalizeKeyword(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('#')) return trimmed;
    return '#$trimmed';
  }

  Widget _buildLoadingOverlay({
    required Color bg,
    required Color textMain,
    required Color textMuted,
  }) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: bg.withValues(alpha: 0.4),
            child: Stack(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              MemoFlowPalette.primary,
                            ),
                            backgroundColor: MemoFlowPalette.primary.withValues(
                              alpha: 0.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          context.t.strings.legacy.msg_analyzing_memos,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: textMain,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.t.strings.legacy.msg_about_15_seconds_left,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: SafeArea(
                    top: false,
                    child: TextButton(
                      onPressed: _cancelSummary,
                      style: TextButton.styleFrom(
                        foregroundColor: textMain.withValues(alpha: 0.4),
                      ),
                      child: Text(context.t.strings.legacy.msg_cancel),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on _AiSummaryScreenState {
  Widget _buildStructuredReportBody({
    required Color bg,
    required Color card,
    required Color border,
    required Color textMain,
    required Color textMuted,
    required AiSavedAnalysisReport report,
  }) {
    final isZh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    return RepaintBoundary(
      key: _reportBoundaryKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 200),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZh ? '情绪地图' : 'Emotion Map',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: textMain,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _reportRangeLabel(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                if (report.isStale) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      isZh
                          ? '当前分析结果已过期，建议重新生成。'
                          : 'This result is stale and should be regenerated.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textMain,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  report.summary,
                  style: TextStyle(fontSize: 15, height: 1.6, color: textMain),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final section in report.sections) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textMain,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    section.body,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: textMain,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final evidence in report.evidences.where(
                    (item) => item.sectionKey == section.sectionKey,
                  )) ...[
                    InkWell(
                      onTap: () => _openEvidenceMemo(evidence),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              evidence.quoteText,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: textMain,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isZh
                                  ? '笔记：${evidence.memoUid} · 相关度 ${(evidence.relevanceScore * 100).toStringAsFixed(0)}%'
                                  : 'Memo: ${evidence.memoUid} · Score ${(evidence.relevanceScore * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (report.followUpSuggestions.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isZh ? '后续建议' : 'Follow-up Suggestions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: textMain,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final item in report.followUpSuggestions) ...[
                    Text(
                      '• $item',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: textMain,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openEvidenceMemo(AiAnalysisEvidenceData evidence) async {
    final row = await ref.read(databaseProvider).getMemoByUid(evidence.memoUid);
    if (!mounted || row == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemoDetailScreen(initialMemo: LocalMemo.fromDb(row)),
      ),
    );
  }
}

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({
    required this.definition,
    required this.cardColor,
    required this.borderColor,
    required this.textMain,
    required this.textMuted,
    required this.onTap,
  });

  final AiInsightDefinition definition;
  final Color cardColor;
  final Color borderColor;
  final Color textMain;
  final Color textMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: definition.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  definition.icon,
                  color: definition.accent,
                  size: 22,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                definition.title(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textMain,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  definition.description(context),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: textMuted,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeywordChip extends StatelessWidget {
  const _KeywordChip({
    required this.label,
    required this.background,
    required this.textColor,
    this.borderColor,
  });

  final String label;
  final Color background;
  final Color textColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
