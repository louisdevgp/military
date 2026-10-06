import 'package:flutter/services.dart';

/// Photos selected by the operator, copied into the private Android app folder.
/// These local paths must never be included in a public API response.
abstract interface class PhotoService {
  Future<String?> choosePhoto();
  Future<void> discardDraft(String path);
}

class AndroidPhotoService implements PhotoService {
  const AndroidPhotoService();
  static const channel = MethodChannel('ci.universdumono/photos');

  @override
  Future<String?> choosePhoto() => channel.invokeMethod<String>('choose');

  @override
  Future<void> discardDraft(String path) =>
      channel.invokeMethod<void>('discardDraft', {'path': path});
}
