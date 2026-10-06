# Installation et vérification de la première tranche

## Flutter

Flutter 3.47.6 stable / Dart 3.13.5. Utiliser le `pubspec.lock` versionné. Android nécessite le NDK 28.2.13676358. Le H10 constaté est ARMv7 32 bits / Android 14 API 34.

Sur ce Windows, la compilation des hooks natifs échoue avec le chemin SDK contenant des espaces. Le chemin court constaté est `C:\Users\LOUIS-~1\flutter\bin\flutter.bat` (ne pas le supposer identique sur un autre poste).

```powershell
cd apps/pos_flutter
& 'C:\Users\LOUIS-~1\flutter\bin\flutter.bat' pub get --enforce-lockfile
& 'C:\Users\LOUIS-~1\flutter\bin\dart.bat' run build_runner build
& 'C:\Users\LOUIS-~1\flutter\bin\flutter.bat' analyze
& 'C:\Users\LOUIS-~1\flutter\bin\flutter.bat' test
& 'C:\Users\LOUIS-~1\flutter\bin\flutter.bat' build apk --debug --target-platform android-arm --dart-define=RECETTE_MODE=true
```

Sortie : `build/app/outputs/flutter-apk/app-debug.apk`, package `ci.universdumono.mono_pos.recette`. C’est un APK signé **avec la clé Android de développement**, séparé d’une future application de production. Sans `RECETTE_MODE=true`, les opérations sont désactivées.

```powershell
adb devices -l
adb -s <identifiant-adb> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <identifiant-adb> shell am start -n ci.universdumono.mono_pos.recette/ci.universdumono.mono_pos.MainActivity
```

L’adresse/port Wi-Fi ADB peut changer. Ne pas désinstaller pour mettre à jour : `install -r` conserve normalement les données, à vérifier en recette. Ne pas accepter un remplacement par un APK signé différemment. La clé de production devra être créée, sauvegardée hors dépôt et conservée pour les mises à jour.

## API locale de recette

Python 3.13, uv 0.12.23, dépendances exactes dans `services/api/uv.lock`.

1. Dans `services/api`, lancer `uv sync --frozen`.
2. Copier `.env.example` en `.env` (ignoré par Git).
3. Pour la recette locale seulement, `MONO_DATABASE_URL=sqlite:///./recette.db`. En serveur utiliser PostgreSQL.
4. Relever l’UUID terminal dans les réglages de l’application et renseigner `MONO_TERMINAL_ID`. Mettre `MONO_RECETTE_MODE=true`.
5. Générer un jeton aléatoire de 32 caractères minimum hors dépôt, renseigner `MONO_SYNC_TOKEN` et une échéance UTC courte, par exemple 15 minutes, dans `MONO_TOKEN_EXPIRES_AT`. Aucun jeton n’est fourni ni fixé dans les sources.
6. `uv run alembic upgrade head`, puis `uv run python -m mono.provision`.
7. `uv run uvicorn mono.main:app --host 127.0.0.1 --port 8000 --no-access-log`.
8. Vérifier `/health/ready` et `/docs`.

Pour tester depuis le TPE par la connexion ADB autorisée : `adb -s <identifiant-adb> reverse tcp:8000 tcp:8000`. Renseigner `http://127.0.0.1:8000` dans les réglages de recette et le jeton éphémère. Le HTTP est limité à la boucle locale dans l’APK debug. Les autres connexions exigent HTTPS. Le jeton reste en mémoire et disparaît à la fermeture du processus.

Le service n’accepte pas spontanément un terminal inconnu. Ne pas modifier l’UUID d’un terminal déjà provisionné pour contourner une incohérence de séquence.

## Docker Compose (préparé, à exécuter sur un poste équipé)

Depuis `infra`, créer `.env` à partir de `.env.example`, définir les secrets et l’URL `postgresql+psycopg://mono:<mot-de-passe-encodé>@db:5432/mono`.

```sh
docker compose up -d db
docker compose build api
docker compose run --rm api alembic upgrade head
docker compose run --rm api python -m mono.provision
docker compose up -d api
```

PostgreSQL n’expose aucun port. L’API n’écoute que sur la boucle locale de l’hôte. Pas de migration automatique au démarrage de l’API. Les images doivent être épinglées par digest et validées avant un déploiement de production. Nginx/HTTPS, domaine, sauvegardes planifiées et site public seront ajoutés avec les lots concernés.

## Contrôles

- Flutter : format, analyse, tests SQLite/UI ; export optionnel du contrat avec `flutter test --dart-define=EXPORT_CONTRACT=true`.
- Python : `uv run ruff check .`, `uv run ruff format --check .`, `uv run pytest -q`.
- Test PostgreSQL réel : définir `MONO_TEST_DATABASE_URL` sur une base de test dédiée, relancer pytest. Le rôle doit pouvoir créer/supprimer les schémas de test, jamais utiliser un accès production.
- CI préparée dans `.github/workflows/verify.yml`, mais son existence ne prouve pas son exécution. Aucun dépôt distant n’est encore configuré.
