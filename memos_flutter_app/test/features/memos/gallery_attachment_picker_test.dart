import 'package:flutter_test/flutter_test.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import 'package:memos_flutter_app/features/memos/gallery_attachment_original_picker.dart';
import 'package:memos_flutter_app/features/memos/gallery_attachment_picker.dart';

AssetEntity _asset({
  required String id,
  required AssetType type,
  String? title,
}) {
  return AssetEntity(
    id: id,
    typeInt: type.index,
    width: 16,
    height: 16,
    title: title,
  );
}

void main() {
  test('normalizeGalleryOriginalAssetIds keeps only selected images', () {
    final image = _asset(id: 'img-1', type: AssetType.image);
    final video = _asset(id: 'video-1', type: AssetType.video);

    final normalized = normalizeGalleryOriginalAssetIds(
      selectedAssets: [image, video],
      originalAssetIds: const {'img-1', 'video-1', 'missing'},
    );

    expect(normalized, {'img-1'});
  });

  test(
    'buildPickedLocalAttachment marks selected image as skipCompression',
    () {
      final attachment = buildPickedLocalAttachment(
        filePath: '/tmp/sample.png',
        filename: 'sample.png',
        size: 42,
        assetType: AssetType.image,
        assetId: 'img-1',
        originalAssetIds: {'img-1'},
      );

      expect(attachment.mimeType, 'image/png');
      expect(attachment.skipCompression, isTrue);
    },
  );

  test('buildPickedLocalAttachment never marks videos as skipCompression', () {
    final attachment = buildPickedLocalAttachment(
      filePath: '/tmp/sample.mp4',
      filename: 'sample.mp4',
      size: 42,
      assetType: AssetType.video,
      assetId: 'video-1',
      originalAssetIds: {'video-1'},
    );

    expect(attachment.mimeType, 'video/mp4');
    expect(attachment.skipCompression, isFalse);
  });

  test(
    'OriginalToggleAssetPickerProvider clears original marks when unselected',
    () {
      final image = _asset(id: 'img-1', type: AssetType.image);
      final provider = OriginalToggleAssetPickerProvider(maxAssets: 10);

      provider.selectedAssets = [image];
      provider.toggleOriginalForAsset(image);
      expect(provider.originalAssetIds, {'img-1'});

      provider.selectedAssets = const [];
      expect(provider.originalAssetIds, isEmpty);
    },
  );

  test(
    'OriginalToggleAssetPickerProvider ignores non-image original toggles',
    () {
      final video = _asset(id: 'video-1', type: AssetType.video);
      final provider = OriginalToggleAssetPickerProvider(maxAssets: 10);

      provider.selectedAssets = [video];
      provider.toggleOriginalForAsset(video);

      expect(provider.originalAssetIds, isEmpty);
    },
  );

  test(
    'OriginalToggleAssetPickerProvider bottom toggle marks only last selected image',
    () {
      final image1 = _asset(id: 'img-1', type: AssetType.image);
      final image2 = _asset(id: 'img-2', type: AssetType.image);
      final video = _asset(id: 'video-1', type: AssetType.video);
      final provider = OriginalToggleAssetPickerProvider(maxAssets: 10);

      provider.selectedAssets = [image1, video, image2];
      provider.toggleOriginalForCurrentSelectedImage();

      expect(provider.originalAssetIds, {'img-2'});
      expect(provider.isCurrentOriginalTargetMarked, isTrue);
    },
  );

  test(
    'OriginalToggleAssetPickerProvider does not inherit original to new images',
    () {
      final image1 = _asset(id: 'img-1', type: AssetType.image);
      final image2 = _asset(id: 'img-2', type: AssetType.image);
      final provider = OriginalToggleAssetPickerProvider(maxAssets: 10);

      provider.selectedAssets = [image1];
      provider.toggleOriginalForCurrentSelectedImage();
      provider.selectAsset(image2);

      expect(provider.originalAssetIds, {'img-1'});
      expect(provider.isMarkedOriginal(image2), isFalse);
    },
  );
}
