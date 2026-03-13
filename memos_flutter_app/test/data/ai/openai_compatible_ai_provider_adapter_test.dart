import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/data/ai/adapters/openai_compatible_ai_provider_adapter.dart';
import 'package:memos_flutter_app/data/repositories/ai_settings_repository.dart';

void main() {
  late HttpServer server;
  late String baseUrl;
  late List<Map<String, Object?>> requests;

  setUp(() async {
    requests = <Map<String, Object?>>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://${server.address.host}:${server.port}/compatible-mode';
    server.listen((request) async {
      final bodyText = await utf8.decoder.bind(request).join();
      Object? body;
      if (bodyText.trim().isNotEmpty) {
        body = jsonDecode(bodyText);
      }
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name] = values.join(',');
      });
      requests.add(<String, Object?>{
        'method': request.method,
        'path': request.uri.path,
        'headers': headers,
        'body': body,
      });

      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/chat/completions')) {
        request.response.write(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{
                  'content': <Object?>[
                    <String, Object?>{'type': 'text', 'text': '我看见你一直在努力。'},
                    <String, Object?>{'type': 'text', 'text': ' 这封信想先抱抱你。'},
                  ],
                },
              },
            ],
          }),
        );
      } else if (request.uri.path.endsWith('/embeddings')) {
        request.response.write(
          jsonEncode(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'embedding': <Object?>[0.12, 0.34, 0.56],
              },
            ],
          }),
        );
      } else if (request.uri.path.endsWith('/models')) {
        request.response.write(
          jsonEncode(<String, Object?>{'data': <Object?>[]}),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(
          jsonEncode(<String, Object?>{'error': 'unexpected path'}),
        );
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'chat completion uses OpenAI compatible endpoint and parses content parts',
    () async {
      const adapter = OpenAiCompatibleAiProviderAdapter();
      final service = _service(baseUrl: baseUrl);

      final result = await adapter.chatCompletion(
        AiChatCompletionRequest(
          service: service,
          model: service.models.first,
          messages: const <AiChatMessage>[
            AiChatMessage(role: 'user', content: '请给我写一封看见自己的信'),
          ],
          systemPrompt: '像温和的咨询师一样说话',
          temperature: 0.3,
        ),
      );

      expect(result.text, '我看见你一直在努力。 这封信想先抱抱你。');
      expect(requests, hasLength(1));
      expect(requests.single['method'], 'POST');
      expect(requests.single['path'], '/compatible-mode/v1/chat/completions');

      final headers = requests.single['headers']! as Map<String, String>;
      expect(headers['authorization'], 'Bearer sk-test');

      final body = requests.single['body']! as Map<String, Object?>;
      expect(body['model'], 'qwen-plus');
      expect(body['stream'], false);
      final messages = body['messages']! as List<Object?>;
      expect(messages, hasLength(2));
      expect((messages.first as Map<String, Object?>)['role'], 'system');
      expect((messages.last as Map<String, Object?>)['role'], 'user');
    },
  );

  test(
    'embedding uses OpenAI compatible endpoint and returns vector',
    () async {
      const adapter = OpenAiCompatibleAiProviderAdapter();
      final service = _service(baseUrl: baseUrl);

      final vector = await adapter.embed(
        AiEmbeddingRequest(
          service: service,
          model: service.models.last,
          input: '今天其实很累，但还是撑下来了。',
        ),
      );

      expect(vector, <double>[0.12, 0.34, 0.56]);
      expect(requests, hasLength(1));
      expect(requests.single['path'], '/compatible-mode/v1/embeddings');

      final body = requests.single['body']! as Map<String, Object?>;
      expect(body['model'], 'text-embedding-v4');
      expect(body['input'], '今天其实很累，但还是撑下来了。');
    },
  );
}

AiServiceInstance _service({required String baseUrl}) {
  return AiServiceInstance(
    serviceId: 'svc_dashscope',
    templateId: aiTemplateOpenAi,
    adapterKind: AiProviderAdapterKind.openAiCompatible,
    displayName: 'DashScope',
    enabled: true,
    baseUrl: baseUrl,
    apiKey: 'sk-test',
    customHeaders: const <String, String>{},
    models: const <AiModelEntry>[
      AiModelEntry(
        modelId: 'mdl_chat',
        displayName: 'Qwen Plus',
        modelKey: 'qwen-plus',
        capabilities: <AiCapability>[AiCapability.chat],
        source: AiModelSource.manual,
        enabled: true,
      ),
      AiModelEntry(
        modelId: 'mdl_embed',
        displayName: 'Embedding V4',
        modelKey: 'text-embedding-v4',
        capabilities: <AiCapability>[AiCapability.embedding],
        source: AiModelSource.manual,
        enabled: true,
      ),
    ],
    lastValidatedAt: null,
    lastValidationStatus: AiValidationStatus.unknown,
    lastValidationMessage: null,
  );
}
