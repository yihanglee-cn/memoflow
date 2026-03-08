import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/memoflow_palette.dart';
import '../../i18n/strings.g.dart';
import '../../state/settings/ai_settings_provider.dart';
import '../../state/settings/preferences_provider.dart';
import 'ai_analysis_preview_screen.dart';
import 'ai_insight_models.dart';
import 'ai_insight_prompt_editor_screen.dart';

typedef AiInsightPreviewLoader =
    Future<AiAnalysisPreviewPayload> Function({
      required AiInsightRange range,
      required DateTimeRange? customRange,
      required bool allowPublic,
      required bool allowPrivate,
      required bool allowProtected,
    });

typedef AiInsightCustomRangePicker =
    Future<DateTimeRange?> Function(
      BuildContext context,
      DateTimeRange? currentRange,
    );

class AiInsightSettingsSheet extends ConsumerStatefulWidget {
  const AiInsightSettingsSheet({
    super.key,
    required this.definition,
    required this.previewLoader,
    this.customRangePicker,
    this.analysisLoading = false,
  });

  final AiInsightDefinition definition;
  final AiInsightPreviewLoader previewLoader;
  final AiInsightCustomRangePicker? customRangePicker;
  final bool analysisLoading;

  @override
  ConsumerState<AiInsightSettingsSheet> createState() =>
      _AiInsightSettingsSheetState();
}

class _AiInsightSettingsSheetState
    extends ConsumerState<AiInsightSettingsSheet> {
  late AiInsightRange _range;
  AiInsightRange _lastNonCustomRange = AiInsightRange.last7Days;
  DateTimeRange? _customRange;
  var _allowPublic = true;
  late bool _allowPrivate;
  var _allowProtected = false;
  var _isPreviewLoading = true;
  Object? _previewError;
  AiAnalysisPreviewPayload _previewPayload = AiAnalysisPreviewPayload.empty;
  var _previewRequestId = 0;

  @override
  void initState() {
    super.initState();
    _range = AiInsightRange.last7Days;
    _allowPrivate = ref.read(appPreferencesProvider).aiSummaryAllowPrivateMemos;
    _loadPreview();
  }

  String get _promptTemplate {
    final settings = ref.read(aiSettingsProvider);
    return settings.insightPromptTemplates[widget.definition.id.storageKey]
            ?.trim() ??
        '';
  }

  DateTimeRange get _effectiveRange =>
      resolveAiInsightRange(_range, _customRange);

  String _rangeLabel() {
    return formatAiInsightRangeLabel(_effectiveRange);
  }

  Future<void> _loadPreview() async {
    final requestId = ++_previewRequestId;
    setState(() {
      _isPreviewLoading = true;
      _previewError = null;
    });
    try {
      final payload = await widget.previewLoader(
        range: _range,
        customRange: _customRange,
        allowPublic: _allowPublic,
        allowPrivate: _allowPrivate,
        allowProtected: _allowProtected,
      );
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _previewPayload = payload;
        _isPreviewLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _previewError = error;
        _previewPayload = AiAnalysisPreviewPayload.empty;
        _isPreviewLoading = false;
      });
    }
  }

  Future<DateTimeRange?> _pickCustomRange() {
    final picker = widget.customRangePicker;
    if (picker != null) {
      return picker(context, _customRange);
    }
    final now = DateTime.now();
    final initial =
        _customRange ??
        DateTimeRange(
          start: DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 6)),
          end: DateTime(now.year, now.month, now.day),
        );
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
    );
  }

  Future<void> _selectRange(AiInsightRange nextRange) async {
    if (nextRange == AiInsightRange.custom) {
      final picked = await _pickCustomRange();
      if (!mounted) return;
      if (picked == null) {
        if (_customRange == null) {
          setState(() => _range = _lastNonCustomRange);
        }
        return;
      }
      setState(() {
        _customRange = picked;
        _range = AiInsightRange.custom;
      });
      await _loadPreview();
      return;
    }
    setState(() {
      _range = nextRange;
      _lastNonCustomRange = nextRange;
    });
    await _loadPreview();
  }

  Future<void> _toggleAllowPublic(bool value) async {
    setState(() => _allowPublic = value);
    if (!mounted) return;
    await _loadPreview();
  }

  Future<void> _toggleAllowPrivate(bool value) async {
    setState(() => _allowPrivate = value);
    ref
        .read(appPreferencesProvider.notifier)
        .setAiSummaryAllowPrivateMemos(value);
    if (!mounted) return;
    await _loadPreview();
  }

  Future<void> _toggleAllowProtected(bool value) async {
    setState(() => _allowProtected = value);
    if (!mounted) return;
    await _loadPreview();
  }

  Future<void> _openPromptEditor() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            AiInsightPromptEditorScreen(insightId: widget.definition.id),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openPreviewScreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AiAnalysisPreviewScreen(
          definition: widget.definition,
          payload: _previewPayload,
          allowPublic: _allowPublic,
          allowPrivate: _allowPrivate,
          allowProtected: _allowProtected,
          rangeLabel: _rangeLabel(),
        ),
      ),
    );
  }

  void _startAnalysis() {
    if (!_canStartAnalysis) return;
    Navigator.of(context).pop(
      AiInsightSettingsResult(
        insightId: widget.definition.id,
        range: _range,
        customRange: _customRange,
        allowPublic: _allowPublic,
        allowPrivate: _allowPrivate,
        allowProtected: _allowProtected,
        previewPayload: _previewPayload,
        promptTemplate: _promptTemplate,
      ),
    );
  }

  bool get _canStartAnalysis {
    final hasEmbeddingProfile = ref
        .read(aiSettingsProvider)
        .hasEnabledEmbeddingProfile;
    return !widget.analysisLoading &&
        !_isPreviewLoading &&
        _previewError == null &&
        hasEmbeddingProfile &&
        (_allowPublic || _allowPrivate || _allowProtected) &&
        _previewPayload.hasContent &&
        _previewPayload.embeddingReady > 0 &&
        _promptTemplate.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? MemoFlowPalette.cardDark : MemoFlowPalette.cardLight;
    final border = isDark
        ? MemoFlowPalette.borderDark
        : MemoFlowPalette.borderLight;
    final textMain = isDark
        ? MemoFlowPalette.textDark
        : MemoFlowPalette.textLight;
    final textMuted = textMain.withValues(alpha: isDark ? 0.66 : 0.58);
    final accentSoft = widget.definition.accent.withValues(alpha: 0.12);
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.8;
    final minHeight = mediaQuery.size.height * 0.5;
    final promptTemplate = ref.watch(
      aiSettingsProvider.select(
        (settings) =>
            settings.insightPromptTemplates[widget.definition.id.storageKey]
                ?.trim() ??
            '',
      ),
    );
    final hasEmbeddingProfile = ref.watch(
      aiSettingsProvider.select(
        (settings) => settings.hasEnabledEmbeddingProfile,
      ),
    );
    final isZh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    final previewTitle = isZh ? '检索预览' : 'Retrieval Preview';
    final matchingMemosLabel = isZh ? '匹配笔记数' : 'Matching memos';
    final candidateChunksLabel = isZh ? '候选分片数' : 'Candidate chunks';
    final readyLabel = isZh ? '向量已就绪' : 'Embeddings ready';
    final pendingLabel = isZh ? '向量处理中' : 'Embeddings pending';
    final failedLabel = isZh ? '向量失败数' : 'Embeddings failed';
    final embeddingHint = isZh
        ? '请先在 AI 设置中配置 embedding 服务和模型。'
        : 'Configure an embedding provider and model in AI settings first.';

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: minHeight,
            maxHeight: maxHeight,
            maxWidth: 560,
          ),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: border.withValues(alpha: isDark ? 0.72 : 0.9),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t.strings.aiInsight.settingsTitle,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: textMain,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.definition.title(context),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: widget.definition.accent,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _SectionTitle(
                          title: context.t.strings.aiInsight.timeRange.title,
                          textColor: textMain,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _RangeOptionTile(
                              selected: _range == AiInsightRange.last3Days,
                              title: context
                                  .t
                                  .strings
                                  .aiInsight
                                  .timeRange
                                  .last3Days,
                              activeColor: MemoFlowPalette.primary,
                              textColor: textMain,
                              onTap: () =>
                                  _selectRange(AiInsightRange.last3Days),
                            ),
                            _RangeOptionTile(
                              selected: _range == AiInsightRange.last7Days,
                              title: context
                                  .t
                                  .strings
                                  .aiInsight
                                  .timeRange
                                  .last7Days,
                              activeColor: MemoFlowPalette.primary,
                              textColor: textMain,
                              onTap: () =>
                                  _selectRange(AiInsightRange.last7Days),
                            ),
                            _RangeOptionTile(
                              selected: _range == AiInsightRange.last30Days,
                              title: context
                                  .t
                                  .strings
                                  .aiInsight
                                  .timeRange
                                  .last30Days,
                              activeColor: MemoFlowPalette.primary,
                              textColor: textMain,
                              onTap: () =>
                                  _selectRange(AiInsightRange.last30Days),
                            ),
                            _RangeOptionTile(
                              selected: _range == AiInsightRange.custom,
                              title: context
                                  .t
                                  .strings
                                  .aiInsight
                                  .timeRange
                                  .customRange,
                              activeColor: MemoFlowPalette.primary,
                              textColor: textMain,
                              onTap: () => _selectRange(AiInsightRange.custom),
                            ),
                          ],
                        ),
                        if (_range == AiInsightRange.custom &&
                            _customRange != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _rangeLabel(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textMuted,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Divider(color: border),
                        const SizedBox(height: 16),
                        _SectionTitle(
                          title: context.t.strings.aiInsight.privacyScope.title,
                          textColor: textMain,
                        ),
                        const SizedBox(height: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _VisibilityCheckTile(
                                  value: _allowPublic,
                                  onChanged: _toggleAllowPublic,
                                  label: isZh ? '\u516c\u5f00' : 'Public',
                                  textColor: textMain,
                                  activeColor: MemoFlowPalette.primary,
                                ),
                                _VisibilityCheckTile(
                                  value: _allowPrivate,
                                  onChanged: _toggleAllowPrivate,
                                  label: isZh ? '\u79c1\u5bc6' : 'Private',
                                  textColor: textMain,
                                  activeColor: MemoFlowPalette.primary,
                                ),
                                _VisibilityCheckTile(
                                  value: _allowProtected,
                                  onChanged: _toggleAllowProtected,
                                  label: isZh
                                      ? '\u53d7\u4fdd\u62a4'
                                      : 'Protected',
                                  textColor: textMain,
                                  activeColor: MemoFlowPalette.primary,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              isZh
                                  ? '\u52fe\u9009\u540e\uff0c\u6240\u9009\u53ef\u89c1\u6027\u7684\u7b14\u8bb0\u4f1a\u8fdb\u5165\u68c0\u7d22\u4e0e\u5206\u6790\u3002'
                                  : 'Checked visibilities will be included in retrieval and analysis.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                        Divider(color: border),
                        const SizedBox(height: 16),
                        _SectionTitle(
                          title:
                              context.t.strings.aiInsight.promptSettings.title,
                          textColor: textMain,
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: _openPromptEditor,
                          child: Ink(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: accentSoft,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        context
                                            .t
                                            .strings
                                            .aiInsight
                                            .promptSettings
                                            .editPromptTemplate,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: textMain,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        context
                                            .t
                                            .strings
                                            .aiInsight
                                            .promptSettings
                                            .description,
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.5,
                                          color: textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (promptTemplate.trim().isEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            context
                                .t
                                .strings
                                .aiInsight
                                .promptSettings
                                .emptyTemplateHint,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: textMuted,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Divider(color: border),
                        const SizedBox(height: 16),
                        _SectionTitle(title: previewTitle, textColor: textMain),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_isPreviewLoading)
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  MemoFlowPalette.primary,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          context
                                              .t
                                              .strings
                                              .aiInsight
                                              .contentPreview
                                              .loading,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: textMain,
                                          ),
                                        ),
                                      ],
                                    )
                                  else if (_previewError != null)
                                    Text(
                                      context
                                          .t
                                          .strings
                                          .aiInsight
                                          .contentPreview
                                          .previewLoadFailed,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.5,
                                        color: textMuted,
                                      ),
                                    )
                                  else if (!hasEmbeddingProfile)
                                    Text(
                                      embeddingHint,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.5,
                                        color: textMuted,
                                      ),
                                    )
                                  else ...[
                                    _PreviewStatLine(
                                      label: matchingMemosLabel,
                                      value:
                                          '${_previewPayload.totalMatchingMemos}',
                                      textColor: textMain,
                                      mutedColor: textMuted,
                                    ),
                                    const SizedBox(height: 8),
                                    _PreviewStatLine(
                                      label: candidateChunksLabel,
                                      value:
                                          '${_previewPayload.candidateChunks}',
                                      textColor: textMain,
                                      mutedColor: textMuted,
                                    ),
                                    const SizedBox(height: 8),
                                    _PreviewStatLine(
                                      label: readyLabel,
                                      value:
                                          '${_previewPayload.embeddingReady}',
                                      textColor: textMain,
                                      mutedColor: textMuted,
                                    ),
                                    const SizedBox(height: 8),
                                    _PreviewStatLine(
                                      label: pendingLabel,
                                      value:
                                          '${_previewPayload.embeddingPending}',
                                      textColor: textMain,
                                      mutedColor: textMuted,
                                    ),
                                    const SizedBox(height: 8),
                                    _PreviewStatLine(
                                      label: failedLabel,
                                      value:
                                          '${_previewPayload.embeddingFailed}',
                                      textColor: textMain,
                                      mutedColor: textMuted,
                                    ),
                                    if (_previewPayload.isSampled) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        isZh
                                            ? 'The candidate set exceeded the limit, so this preview is sampled.'
                                            : 'The candidate set exceeded the limit, so this preview is sampled.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          height: 1.45,
                                          color: textMuted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            OutlinedButton(
                              onPressed: _openPreviewScreen,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: textMain,
                                side: BorderSide(color: border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                context
                                    .t
                                    .strings
                                    .aiInsight
                                    .contentPreview
                                    .previewContent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: card,
                    border: Border(top: BorderSide(color: border)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: textMain,
                                side: BorderSide(color: border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                minimumSize: const Size.fromHeight(52),
                              ),
                              child: Text(context.t.strings.common.cancel),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _canStartAnalysis
                                  ? _startAnalysis
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: MemoFlowPalette.primary,
                                disabledBackgroundColor: MemoFlowPalette.primary
                                    .withValues(alpha: 0.35),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                minimumSize: const Size.fromHeight(52),
                              ),
                              child: Text(
                                context.t.strings.aiInsight.startAnalysis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.textColor});

  final String title;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    );
  }
}

class _RangeOptionTile extends StatelessWidget {
  const _RangeOptionTile({
    required this.selected,
    required this.title,
    required this.activeColor,
    required this.textColor,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final Color activeColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : textColor,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: activeColor,
      backgroundColor: activeColor.withValues(alpha: 0.08),
      side: BorderSide(
        color: activeColor.withValues(alpha: selected ? 0 : 0.2),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }
}

class _VisibilityCheckTile extends StatelessWidget {
  const _VisibilityCheckTile({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.textColor,
    required this.activeColor,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  final Color textColor;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value
          ? activeColor.withValues(alpha: 0.12)
          : activeColor.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
                child: Checkbox(
                  value: value,
                  onChanged: (_) {},
                  activeColor: activeColor,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewStatLine extends StatelessWidget {
  const _PreviewStatLine({
    required this.label,
    required this.value,
    required this.textColor,
    required this.mutedColor,
  });

  final String label;
  final String value;
  final Color textColor;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: mutedColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}
