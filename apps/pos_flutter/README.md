# Mono POS — recette 0.1.0

Caisse Flutter, Riverpod et SQLite/Drift. Voir le [guide d’installation](../../docs/installation.md) et les [résultats de recette](../../docs/recette.md).

`flutter run --dart-define=RECETTE_MODE=true` active le mode de recette explicite. L’application reste fermée sans ce paramètre. Aucune authentification de production ni impression matérielle n’est simulée comme un succès réel.

Tests locaux : `flutter test`. Test Android physique : `flutter test integration_test/pos_device_test.dart -d <identifiant-adb> --dart-define=RECETTE_MODE=true`.
