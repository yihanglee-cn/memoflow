import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/features/share/parsers/bilibili_share_page_parser.dart';
import 'package:memos_flutter_app/features/share/parsers/generic_share_page_parser.dart';
import 'package:memos_flutter_app/features/share/parsers/share_page_parser.dart';
import 'package:memos_flutter_app/features/share/parsers/wechat_share_page_parser.dart';
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
          'textContent':
              'Hello world Hello world Hello world Hello world Hello world',
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

    test('wechat parser cleans promo blocks and lazy images', () {
      final parser = WechatSharePageParser();
      final snapshot = SharePageSnapshot(
        requestUrl: Uri.parse('https://mp.weixin.qq.com/s/example'),
        finalUrl: Uri.parse('https://mp.weixin.qq.com/s/example'),
        host: 'mp.weixin.qq.com',
        bridgeData: const {
          'articleTitle': '一个家庭，比穷更可怕的，是这种饭桌陋习',
          'excerpt': '好的家庭，父母从不在饭桌上为难孩子',
          'contentHtml':
              '<div><p><strong><span>👇预约直播，活出自己👇</span></strong></p><p>真正的正文第一段。</p><p><img data-src="https://mmbiz.qpic.cn/body.jpg"></p><p>真正的正文第二段。</p><p>点击小程序，立即订阅</p><p>P.S.如果今天的漫画有打动到你，记得帮我点亮「在看」+「分享」哦。</p></div>',
          'textContent': '👇预约直播，活出自己👇 真正的正文第一段。 真正的正文第二段。 点击小程序，立即订阅',
        },
      );

      final result = parser.parse(snapshot);

      expect(result.pageKind, SharePageKind.article);
      expect(result.parserTag, 'wechat');
      expect(result.title, '一个家庭，比穷更可怕的，是这种饭桌陋习');
      expect(result.siteName, '微信公众平台');
      expect(result.contentHtml, contains('真正的正文第一段'));
      expect(result.contentHtml, contains('真正的正文第二段'));
      expect(
        result.contentHtml,
        contains('src="https://mmbiz.qpic.cn/body.jpg"'),
      );
      expect(result.contentHtml, isNot(contains('imgIndex=')));
      expect(result.contentHtml, isNot(contains('预约直播')));
      expect(result.contentHtml, isNot(contains('点击小程序')));
      expect(result.textContent, contains('真正的正文第一段'));
      expect(result.textContent, isNot(contains('立即订阅')));
    });

    test('wechat parser removes malformed image tail fragments', () {
      final parser = WechatSharePageParser();
      final snapshot = SharePageSnapshot(
        requestUrl: Uri.parse('https://mp.weixin.qq.com/s/example'),
        finalUrl: Uri.parse('https://mp.weixin.qq.com/s/example'),
        host: 'mp.weixin.qq.com',
        bridgeData: const {
          'articleTitle': 'Article',
          'contentHtml':
              '<div><p>Paragraph A.</p><p><img data-src="http://mmbiz.qpic.cn/body.jpg?wx_fmt=png&amp;from=appmsg#imgIndex=3&lt;span class=&quot;bad&quot;&gt;"></p>#imgIndex=3" alt="\u56FE\u7247"><p>Paragraph B.</p></div>',
          'textContent': 'Paragraph A. Paragraph B.',
        },
      );

      final result = parser.parse(snapshot);

      expect(result.pageKind, SharePageKind.article);
      expect(result.contentHtml, contains('Paragraph A.'));
      expect(result.contentHtml, contains('Paragraph B.'));
      expect(
        result.contentHtml,
        contains('src="https://mmbiz.qpic.cn/body.jpg?wx_fmt=png&amp;from=appmsg"'),
      );
      expect(result.contentHtml, isNot(contains('imgIndex=')));
      expect(result.contentHtml, isNot(contains('span class=')));
      expect(result.textContent, isNot(contains('imgIndex')));
    });
  });
}
