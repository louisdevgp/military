import 'dart:io';

import 'package:flutter/services.dart';

import 'receipt.dart';

export 'receipt.dart';

enum PrintOutcome { simulated, submittedUnconfirmed }

abstract interface class PrinterService {
  /// Shown to the operator so a simulation is never mistaken for paper.
  String get label;
  Future<PrintOutcome> printReceipt(Receipt receipt);
}

class SimulatedPrinter implements PrinterService {
  final List<Receipt> jobs = [];
  @override
  String get label => 'Imprimante simulée';
  @override
  Future<PrintOutcome> printReceipt(Receipt receipt) async {
    jobs.add(receipt);
    return PrintOutcome.simulated;
  }
}

/// H10 built-in printer through the SRPrinter service (PrinterBridge.kt).
/// The service reports no paper status: success means "submitted", never
/// "printed".
class PlatformPrinter implements PrinterService {
  PlatformPrinter({this.version = '', AssetBundle? bundle})
    : bundle = bundle ?? rootBundle;
  static const channel = MethodChannel('ci.universdumono/printer');
  final String version;
  final AssetBundle bundle;

  /// Returns the service version, or throws [PlatformException] when the
  /// SRPrinter service is absent or does not answer.
  static Future<String> probe() async =>
      await channel.invokeMethod<String>('status') ?? '';

  @override
  String get label => version.isEmpty
      ? 'Imprimante intégrée'
      : 'Imprimante intégrée (SRPrinter $version)';

  @override
  Future<PrintOutcome> printReceipt(Receipt receipt) async {
    final blocks = <Map<String, Object?>>[];
    for (final block in receipt.blocks) {
      final json = block.toJson();
      if (block is ReceiptLogo) {
        final Uint8List bytes;
        if (block.file) {
          bytes = await File(block.source).readAsBytes();
        } else {
          final data = await bundle.load(block.source);
          bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        }
        json
          ..remove('asset')
          ..remove('file')
          ..['png'] = bytes;
      }
      blocks.add(json);
    }
    await channel.invokeMethod<void>('printReceipt', {'blocks': blocks});
    return PrintOutcome.submittedUnconfirmed;
  }
}
