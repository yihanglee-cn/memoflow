import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/memoflow_palette.dart';
import '../../i18n/strings.g.dart';
import '../../state/settings/ai_settings_provider.dart';
import 'ai_insight_models.dart';

class AiInsightPromptEditorScreen extends ConsumerStatefulWidget {
  const AiInsightPromptEditorScreen({super.key, required this.insightId});

  final AiInsightId insightId;

  @override
  ConsumerState<AiInsightPromptEditorScreen> createState() =>
      _AiInsightPromptEditorScreenState();
}

class _AiInsightPromptEditorScreenState
    extends ConsumerState<AiInsightPromptEditorScreen> {
  late final TextEditingController _controller;
  late String _initialValue;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _initialValue = _templateFromSettings();
    _controller = TextEditingController(text: _initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _templateFromSettings() {
    final settings = ref.read(aiSettingsProvider);
    return settings.insightPromptTemplates[widget.insightId.storageKey]
            ?.trim() ??
        '';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await ref
        .read(aiSettingsProvider.notifier)
        .setInsightPromptTemplate(
          widget.insightId.storageKey,
          _controller.text,
        );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _clear() async {
    if (_saving) return;
    setState(() => _saving = true);
    await ref
        .read(aiSettingsProvider.notifier)
        .clearInsightPromptTemplate(widget.insightId.storageKey);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  void _restoreDefaultPlaceholder() {
    final isZh =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isZh ? '恢复默认模板即将支持。' : 'Restore default template is coming soon.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final definition = definitionForInsight(widget.insightId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? MemoFlowPalette.backgroundDark
        : MemoFlowPalette.backgroundLight;
    final card = isDark ? MemoFlowPalette.cardDark : MemoFlowPalette.cardLight;
    final border = isDark
        ? MemoFlowPalette.borderDark
        : MemoFlowPalette.borderLight;
    final textMain = isDark
        ? MemoFlowPalette.textDark
        : MemoFlowPalette.textLight;
    final textMuted = textMain.withValues(alpha: isDark ? 0.66 : 0.58);
    final hasExistingTemplate = _initialValue.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          context.t.strings.aiInsight.promptSettings.editPromptTemplate,
        ),
        actions: [
          TextButton(
            onPressed: _restoreDefaultPlaceholder,
            child: Text(
              Localizations.localeOf(context).languageCode.toLowerCase() == 'zh'
                  ? '恢复默认'
                  : 'Restore Default',
            ),
          ),
          if (hasExistingTemplate)
            TextButton(
              onPressed: _clear,
              child: Text(
                context.t.strings.aiInsight.promptSettings.clearTemplate,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      definition.title(context),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textMain,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t.strings.aiInsight.promptSettings
                          .editorDescription(
                            insight: definition.title(context),
                          ),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: border),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _controller,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: textMain,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: context
                          .t
                          .strings
                          .aiInsight
                          .promptSettings
                          .editorPlaceholder,
                      hintStyle: TextStyle(color: textMuted),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: MemoFlowPalette.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          context.t.strings.common.save,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
