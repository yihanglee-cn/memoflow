import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/features/share/parsers/bilibili_share_page_parser.dart';
import 'package:memos_flutter_app/features/share/parsers/generic_share_page_parser.dart';
import 'package:memos_flutter_app/features/share/parsers/share_page_parser.dart';
import 'package:memos_flutter_app/features/share/parsers/xiaohongshu_share_page_parser.dart';
import 'package:memos_flutter_app/features/share/share_clip_models.dart';

void main() {
  group('share page parsers', () {
    test('generic parser detects article page', () {
      final parser = GenericSharePageParser();
      final snapshot = SharePageSnapshot(
        requestUrl: Uri.parse('https://example.com/post/1'),
        finalUrl: Uri.parse('https://example.com/post/1'),
        host: 'example.com',
        bridgeData: const {
          'articleTitle': 'Example Article',
          'excerpt': 'Summary',
          'contentHtml': '<p>Hello world</p>',
          'textContent': 'Hello world Hello world Hello world Hello world Hello world',
        },
      );

      final result = parser.parse(snapshot);

      expect(result.pageKind, SharePageKind.article);
      expect(result.videoCandidates, isEmpty);
      expect(result.title, 'Example Article');
    });

    test('generic parser detects direct video candidate', () {
      final parser = GenericSharePageParser();
      final snapshot = SharePageSnapshot(
        requestUrl: Uri.parse('https://example.com/video'),
        finalUrl: Uri.parse('https://example.com/video'),
        host: 'example.com',
        bridgeData: const {
          'pageTitle': 'Video Page',
          'rawVideoHints': [
            {
              'url': 'https://cdn.example.com/video.mp4',
              'source': 'meta',
              'mimeType': 'video/mp4',
            },
          ],
        },
      );

      final result = parser.parse(snapshot);

      expect(result.pageKind, SharePageKind.video);
      expect(result.videoCandidates, hasLength(1));
      expect(result.videoCandidates.first.isDirectDownloadable, isTrue);
    });

    test('bilibili parser detects video from playinfo', () {
      final parser = BilibiliSharePageParser();
      final snapshot = SharePageSnapshot(
        requestUrl: Uri.parse('https://www.bilibili.com/video/BV1xx'),
        finalUrl: Uri.parse('https://www.bilibili.com/video/BV1xx'),
        host: 'www.bilibili.com',
        bridgeData: const {
          'windowStates': {
            '__playinfo__': {
              'data': {
                'durl': [
                  {'url': 'https://upos-sz-mirror.bilivideo.com/example.mp4'},
                ],
              },
            },
            '__INITIAL_STATE__': {
              'videoData': {
                'title': 'Bilibili Video',
                'desc': 'Bilibili description',
              },
            },
          },
        },
      );

      final result = parser.parse(snapshot);

      expect(result.pageKind, SharePageKind.video);
      expect(result.videoCandidates, isNotEmpty);
      expect(result.title, 'Bilibili Video');
    });

    test('xiaohongshu parser detects video note', () {
      final parser = XiaohongshuSharePageParser();
      final snapshot = SharePageSnapshot(
        requestUrl: Uri.parse('https://www.xiaohongshu.com/explore/123'),
        finalUrl: Uri.parse('https://www.xiaohongshu.com/explore/123'),
        host: 'www.xiaohongshu.com',
        bridgeData: const {
          'windowStates': {
            '__INITIAL_STATE__': {
              'note': {
                'title': 'XHS Video',
                'desc': 'XHS description',
                'noteType': 'video',
                'masterUrl': 'https://sns-video-bd.xhscdn.com/example.mp4',
              },
            },
          },
        },
      );

      final result = parser.parse(snapshot);

      expect(result.pageKind, SharePageKind.video);
      expect(result.videoCandidates, isNotEmpty);
      expect(result.title, 'XHS Video');
    });
  });
}
