import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memos_flutter_app/data/models/app_preferences.dart';
import 'package:memos_flutter_app/data/repositories/ai_settings_repository.dart';

class _MemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
      return;
    }
    _data[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

void main() {
  test('AiSettings.fromJson falls back to an empty insight template map', () {
    final settings = AiSettings.fromJson(<String, dynamic>{
      'apiUrl': 'https://example.com',
      'apiKey': 'test-key',
      'model': 'gpt-4o-mini',
      'prompt': 'Base prompt',
    });

    expect(settings.insightPromptTemplates, isEmpty);
  });

  test('AiSettingsRepository round-trips insight prompt templates', () async {
    final storage = _MemorySecureStorage();
    final repository = AiSettingsRepository(storage, accountKey: 'user-1');
    final initial = AiSettings.defaultsFor(AppLanguage.en).copyWith(
      insightPromptTemplates: const <String, String>{
        'today_clues': 'Focus on recent tensions.',
        'emotion_map': 'Summarize emotional patterns.',
      },
    );

    await repository.write(initial);
    final raw = await storage.read(key: 'ai_settings_v2_user-1');
    final encoded = jsonDecode(raw!) as Map<String, dynamic>;

    expect(
      encoded['insightPromptTemplates'],
      containsPair('today_clues', 'Focus on recent tensions.'),
    );

    final restored = await repository.read(language: AppLanguage.en);
    expect(restored.insightPromptTemplates, const <String, String>{
      'today_clues': 'Focus on recent tensions.',
      'emotion_map': 'Summarize emotional patterns.',
    });
  });
}
