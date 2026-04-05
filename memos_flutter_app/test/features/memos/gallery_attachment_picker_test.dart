import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
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
  test('buildPickedLocalAttachment defaults to gallery source', () {
    final attachment = buildPickedLocalAttachment(
      filePath: '/tmp/sample.png',
      filename: 'sample.png',
      size: 42,
    );

    expect(attachment.mimeType, 'image/png');
    expect(attachment.source, PickedLocalAttachmentSource.gallery);
    expect(attachment.skipCompression, isFalse);
  });

  test('buildPickedLocalAttachment can mark camera source', () {
    final attachment = buildPickedLocalAttachment(
      filePath: '/tmp/sample.mp4',
      filename: 'sample.mp4',
      size: 42,
      source: PickedLocalAttachmentSource.camera,
    );

    expect(attachment.mimeType, 'video/mp4');
    expect(attachment.source, PickedLocalAttachmentSource.camera);
    expect(attachment.skipCompression, isFalse);
  });

  test(
    'captureCameraAttachment returns a camera attachment from override',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'memo_gallery_camera_test',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final photo = File('${tempDir.path}${Platform.pathSeparator}captured.jpg')
        ..writeAsBytesSync(const [1, 2, 3, 4]);

      final attachment = await captureCameraAttachment(
        imagePicker: ImagePicker(),
        capturePhotoOverride: () async => XFile(photo.path),
      );

      expect(attachment, isNotNull);
      expect(attachment!.filePath, photo.path);
      expect(attachment.filename, 'captured.jpg');
      expect(attachment.mimeType, 'image/jpeg');
      expect(attachment.size, 4);
      expect(attachment.source, PickedLocalAttachmentSource.camera);
      expect(attachment.skipCompression, isFalse);
    },
  );

  test('captureCameraAttachment throws for missing file paths', () async {
    await expectLater(
      () => captureCameraAttachment(
        imagePicker: ImagePicker(),
        capturePhotoOverride: () async => XFile(''),
      ),
      throwsA(isA<CameraAttachmentFileMissingException>()),
    );
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
