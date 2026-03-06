import 'package:flutter_test/flutter_test.dart';
import 'package:memos_flutter_app/core/video_thumbnail_cache.dart';

void main() {
  test('disables plugin fallback on Windows', () {
    final allowed =
        VideoThumbnailCache.allowVideoThumbnailPluginFallbackForPlatform(
          isWeb: false,
          isWindows: true,
          isAndroid: false,
          isIOS: false,
          isMacOS: false,
          isLinux: false,
        );

    expect(allowed, isFalse);
  });

  test('keeps plugin fallback enabled on Android and iOS', () {
    expect(
      VideoThumbnailCache.allowVideoThumbnailPluginFallbackForPlatform(
        isWeb: false,
        isWindows: false,
        isAndroid: true,
        isIOS: false,
        isMacOS: false,
        isLinux: false,
      ),
      isTrue,
    );
    expect(
      VideoThumbnailCache.allowVideoThumbnailPluginFallbackForPlatform(
        isWeb: false,
        isWindows: false,
        isAndroid: false,
        isIOS: true,
        isMacOS: false,
        isLinux: false,
      ),
      isTrue,
    );
  });
}
