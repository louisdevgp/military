import 'dart:io';

import '../domain/models.dart';
import '../printing/receipt.dart';
import 'database.dart';
import 'pos_repository.dart';

/// Receipt identity edited by the administrator. Defaults (customer annex)
/// apply until a first save.
class SettingsRepository {
  SettingsRepository(this.pos);
  final PosRepository pos;
  PosDatabase get db => pos.db;

  static const maxShopName = 40, maxContacts = 64, maxFooter = 80;

  Future<ReceiptSettings> receiptSettings() async {
    final values = {
      for (final row in await db.select(db.shopSettings).get())
        row.key: row.value,
    };
    const defaults = ReceiptSettings();
    final logo = LogoChoice.values.asNameMap()[values['logo']] ?? defaults.logo;
    final file = values['logo_file'];
    return ReceiptSettings(
      shopName: values['shop_name'] ?? defaults.shopName,
      contacts: values['contacts'] ?? defaults.contacts,
      footer: values['footer'] ?? defaults.footer,
      // A missing custom image falls back to the original logo, never to a
      // broken print.
      logo:
          logo == LogoChoice.custom &&
              (file == null || !File(file).existsSync())
          ? LogoChoice.original
          : logo,
      logoFile: file,
    );
  }

  Future<void> saveReceiptSettings(Actor admin, ReceiptSettings next) async {
    admin.requireAdmin();
    final name = next.shopName.trim();
    final contacts = next.contacts.trim();
    final footer = next.footer.trim();
    String check(String value, int max, String field, {bool required = false}) {
      if ((required && value.isEmpty) ||
          value.length > max ||
          value.contains('\n')) {
        throw BusinessException(
          '$field : ${required ? '1' : '0'} à $max caractères sur une ligne.',
        );
      }
      return value;
    }

    check(name, maxShopName, 'Nom de la boutique', required: true);
    check(contacts, maxContacts, 'Contacts');
    check(footer, maxFooter, 'Pied de ticket');
    final file = next.logo == LogoChoice.custom ? next.logoFile : null;
    if (next.logo == LogoChoice.custom) {
      if (file == null ||
          !RegExp(r'[/\\]catalog_images[/\\][a-f0-9-]{36}\.jpg$')
              .hasMatch(file) ||
          !await File(file).exists() ||
          await File(file).length() > 2 * 1024 * 1024) {
        throw const BusinessException(
          'Le logo choisi est indisponible. Sélectionnez-le à nouveau.',
        );
      }
    }
    await db.transaction(() async {
      final values = {
        'shop_name': name,
        'contacts': contacts,
        'footer': footer,
        'logo': next.logo.name,
        'logo_file': ?file,
      };
      if (file == null) {
        await (db.delete(
          db.shopSettings,
        )..where((s) => s.key.equals('logo_file'))).go();
      }
      for (final entry in values.entries) {
        await db
            .into(db.shopSettings)
            .insertOnConflictUpdate(
              ShopSettingsCompanion.insert(key: entry.key, value: entry.value),
            );
      }
      // Audit trail; the image itself stays on the terminal.
      await pos.appendEvent(
        PosRepository.uuid.v4(),
        'settings.receipt_updated',
        admin,
        pos.now().toUtc().toIso8601String(),
        {
          'shop_name': name,
          'contacts': contacts,
          'footer': footer,
          'logo': next.logo.name,
        },
      );
    });
  }
}
