# UNIVERS DU MONO

Première tranche de recette : caisse Flutter Android hors ligne et API de synchronisation. **Ce dépôt n’est pas encore une V1 exploitable en production.** Le plan de livraison complet est dans [docs/plan.md](docs/plan.md).

## Ce qui est implémenté

- Catégories, articles et variantes avec référence unique, prix entier FCFA et stock initial tracé.
- Catalogue illustré avec filtres par catégorie, jusqu’à trois photos locales par article, panier illustré et paiement avec aperçu de la monnaie.
- Recherche, panier, paiement complet, monnaie, client facultatif, historique immuable.
- Transaction SQLite/Drift atomique : vente, stock, mouvements, compteur et outbox.
- Aperçu de ticket et duplicata après validation ; imprimante simulée explicitement.
- API FastAPI/SQLAlchemy/Alembic : terminal unique provisionné, ordre strict, idempotence avec contraintes uniques, refus des conflits, validation des snapshots, projection publique séparée.
- Synchronisation manuelle depuis la caisse, erreurs visibles, tentatives et délai progressif persistés.

## Démarrage

Voir [installation](docs/installation.md), [guide de recette utilisateur](docs/utilisateur-recette.md), [résultats et limites](docs/recette.md), [matériel](docs/materiel.md), [contrat de synchronisation](docs/synchronisation.md).

```sh
cd apps/pos_flutter
flutter pub get --enforce-lockfile
flutter test
flutter run --dart-define=RECETTE_MODE=true -d <identifiant-adb>
```

```sh
cd services/api
uv sync --frozen
uv run ruff check .
uv run pytest -q
```

Les tests PostgreSQL s’exécutent avec `MONO_TEST_DATABASE_URL` vers une base de test dédiée ; chaque test crée un schéma isolé. Sans cette variable, SQLite est utilisé et le test de concurrence PostgreSQL est explicitement ignoré.

## Limites de cette tranche

Impression intégrée via le service SRPrinter du H10 : premier ticket papier observé, papier absent non testé, aucun état papier remonté par le service. Profils par PIN local (0.4.0) sans clé Keystore ni authentification serveur de production. Provisionnement de production, sauvegarde/restauration, catalogue complet, retours, dépenses, rapports et site public restent les lots suivants. L’accès serveur de recette utilise un jeton éphémère et ne remplace pas l’authentification de production. Aucun déploiement en production ni envoi sur GitHub n’a été effectué.

Les photos restent dans le stockage privé du TPE ; elles ne sont pas encore transmises au serveur, publiées ni sauvegardées hors appareil. Voir [photos et migration](docs/photos.md).
