import 'package:flutter/services.dart';

/// Saves an export where the operator chooses (Android document creator).
/// Returns false when the operator cancels.
abstract interface class ExportService {
  Future<bool> saveCsv(String name, String content);
}

class AndroidExportService implements ExportService {
  const AndroidExportService();
  static const channel = MethodChannel('ci.universdumono/export');

  @override
  Future<bool> saveCsv(String name, String content) async =>
      await channel.invokeMethod<bool>('saveCsv', {
        'name': name,
        'content': content,
      }) ??
      false;
}
