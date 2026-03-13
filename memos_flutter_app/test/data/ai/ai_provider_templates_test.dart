import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/data/ai/ai_provider_templates.dart';

void main() {
  test('OpenAI template exposes built-in chat and embedding presets', () {
    final template = findAiProviderTemplate(aiTemplateOpenAi);
    expect(template, isNotNull);

    final presets = builtinModelPresetsForTemplate(template!);
    expect(presets.any((preset) => preset.modelKey == 'gpt-5.1'), isTrue);
    expect(
      presets.any((preset) => preset.modelKey == 'text-embedding-3-small'),
      isTrue,
    );
  });

  test('Custom Anthropic template inherits Anthropic built-in presets', () {
    final template = findAiProviderTemplate(aiTemplateCustomAnthropic);
    expect(template, isNotNull);

    final presets = builtinModelPresetsForTemplate(template!);
    expect(
      presets.any((preset) => preset.modelKey == 'claude-sonnet-4-5'),
      isTrue,
    );
  });

  test('Local templates keep presets empty by default', () {
    final ollama = findAiProviderTemplate(aiTemplateOllama);
    final lmStudio = findAiProviderTemplate(aiTemplateLmStudio);

    expect(ollama, isNotNull);
    expect(lmStudio, isNotNull);
    expect(builtinModelPresetsForTemplate(ollama!), isEmpty);
    expect(builtinModelPresetsForTemplate(lmStudio!), isEmpty);
  });
}
