# Versions et sources — vérification du 6 octobre 2026

| Composant | Version retenue / constatée | Validation |
|---|---|---|
| Flutter / Dart | 3.47.6 stable / 3.13.5 | `flutter --version`, `flutter doctor -v` ; [archive officielle](https://docs.flutter.dev/install/archive) |
| Riverpod | 3.4.3 | [pub.dev](https://pub.dev/packages/flutter_riverpod), résolution et analyse |
| Drift / drift_dev | 2.35.1 | [pub.dev](https://pub.dev/packages/drift), tests SQLite et générateur |
| drift_flutter | 0.3.1 | [installation officielle](https://drift.simonbinder.eu/setup/), verrouillage Pub |
| Python | 3.13.14 installé | exécution et tests |
| FastAPI | 0.142.2 | [PyPI](https://pypi.org/project/fastapi/), résolution uv et tests |
| SQLAlchemy | 2.0.54 | [PyPI](https://pypi.org/project/SQLAlchemy/), résolution uv et tests |
| Alembic / Psycopg | 1.20.0 / 3.3.6 | registre PyPI via uv, migration testée sur SQLite ; Psycopg/PostgreSQL à valider en CI |
| PostgreSQL | 18.6 retenu pour Compose/CI | [versions supportées](https://www.postgresql.org/support/versioning/), [image officielle](https://hub.docker.com/_/postgres) ; pas installé localement |
| uv | 0.12.23 | installation et verrouillage réussis |
| Node / npm | 22.21.1 / 10.9.4 installés | constat CLI ; frontend non commencé |
| Android du TPE | 14 / API 34 / ARMv7 32 bits | valeurs `adb shell getprop` |
| NDK | 28.2.13676358 | paquet officiel Google requis par Flutter |

Les dépendances résolues sont conservées dans `apps/pos_flutter/pubspec.lock` et `services/api/uv.lock`. Les écarts de version disponibles hors contraintes Flutter ne sont pas forcés. React/TypeScript/Vite, Nginx et leurs versions seront vérifiés au démarrage du lot site/déploiement.

Deux difficultés Windows ont été observées : chemin long avec espaces pour les hooks natifs (résolu par chemin court) et ancien wrapper `sdkmanager.bat` traduisant incorrectement l’identifiant NDK. Installation réussie avec `android.exe --sdk=C:\Android\Sdk sdk install 'ndk;28.2.13676358'`, suivant l’aide de l’[outil Android officiel](https://developer.android.com/tools/agents/android-cli).
