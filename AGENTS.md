# UNIVERS DU MONO — conventions

Application de caisse Android hors ligne, une boutique et un seul terminal actif.
Lire `docs/cadrage.md`, `docs/plan.md` et `docs/recette.md` avant de modifier le projet.

- Flutter/Dart, Riverpod, SQLite/Drift ; FastAPI, SQLAlchemy, Alembic, PostgreSQL ; React/TypeScript/Vite pour le futur catalogue public.
- Organisation par fonctionnalités ; domaine indépendant des widgets, SQL dans la couche de données, matériel derrière `PrinterService`.
- Montants FCFA entiers, horodatages UTC avec fuseau, périodes métier Africa/Abidjan.
- Toute mutation métier écrit ses mouvements et son événement outbox dans une seule transaction. Stock négatif interdit. Historique immuable.
- UUID d'opération distinct du numéro de vente ; idempotence et ordre garantis par contraintes uniques et transactions.
- Aucun SDK ni résultat de test inventé. Distinguer simulation, essai Android et résultat physique observé.
- Catalogue vide au démarrage. Jeux de données réservés aux tests. Aucune coordonnée commerciale inventée.
- Ne jamais journaliser secrets ou données client. Aucune clé de signature ni base locale dans Git.
- Verrouiller les dépendances et versionner les migrations. Pas de migration destructive ni de déploiement sur production existante sans autorisation.
- Valider chaque tranche avant de poursuivre : format/analyse Flutter + tests, Ruff/pytest, puis TypeScript/lint/build quand le site existe.
- Documenter les limites effectives dans `docs/recette.md`. Une base technique ou un APK de développement ne constitue pas une livraison de production.
