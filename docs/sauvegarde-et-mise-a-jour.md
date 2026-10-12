# Sauvegarde, restauration et mise à jour

Synchronisation ≠ sauvegarde. Le serveur garde une copie des opérations synchronisées, mais ni les codes PIN (jamais transmis), ni les photos, ni les opérations encore en attente. La sauvegarde du terminal et celle de la base serveur sont donc complémentaires.

## 1. Sauvegarde du terminal (depuis 0.12.0)

**Administration → Sauvegarde → Créer et enregistrer la sauvegarde** (administrateur).

- Copie cohérente de la base SQLite par `VACUUM INTO` (prise sans arrêter l'application, journal compris), plus les photos des articles et le logo personnalisé.
- Manifeste : format, version de schéma, terminal, compteurs d'opérations et de ventes, date, empreintes SHA-256 de la base et de chaque fichier.
- Archive chiffrée **AES-256-GCM**, clé dérivée du mot de passe de sauvegarde (PBKDF2-HMAC-SHA256, 210 000 itérations, sel aléatoire), en-tête authentifié. Mot de passe ≥ 10 caractères, jamais enregistré : **sans lui, la sauvegarde est illisible**.
- Fichier `.monobak` enregistré **hors du terminal** via le sélecteur de documents Android (Drive, clé USB, PC) ; aucune permission de stockage.
- Date de la dernière sauvegarde affichée ; événement d'audit `backup.created` synchronisé (l'archive ne part jamais vers le serveur).

Recommandation d'exploitation : une sauvegarde par jour après la clôture de caisse, conservée au moins 30 jours, dans deux lieux distincts ; mot de passe conservé séparément du fichier.

## 2. Restauration du terminal

**Administration → Sauvegarde → Restaurer…** (administrateur), ou sur l'**écran d'activation** d'un terminal neuf (remplacement après perte ou panne).

1. Déchiffrement (mot de passe incorrect ou fichier modifié → refus), contrôle du format, refus d'une sauvegarde créée par une version plus récente, vérification des empreintes de la base et de chaque fichier.
2. **Copie de sécurité** de l'état actuel du terminal (`app_flutter/safety/avant-restauration-<date>.sqlite`).
3. Préparation, puis redémarrage : la base est remplacée **avant** son ouverture, l'intégrité SQLite est vérifiée, les photos sont remises en place.
4. **Blocage** : toute nouvelle opération (vente, stock, dépense…) est refusée tant que le terminal n'est pas réconcilié.

## 3. Réconciliation avec le serveur

**Administration → Synchronisation → Réconcilier maintenant** (serveur enregistré au préalable).

- Le serveur fournit son état (dernière séquence, compteur de ventes) et les opérations reçues après la dernière opération synchronisée de la sauvegarde.
- Une opération présente des deux côtés doit avoir le même identifiant : sinon **conflit**, le terminal reste bloqué.
- Chaque opération absente de la sauvegarde est rejouée localement avec ses effets exacts (ventes, stock et mouvements, retours, corrections, dépenses, clôtures, articles, réglages).
- Les compteurs reprennent après ceux du serveur : aucune séquence ni numéro `FACT` réutilisé.
- Les comptes créés après la sauvegarde existent mais n'ont pas de code PIN (jamais transmis) : un administrateur doit leur en donner un.
- Échappatoire : « Aucun serveur utilisé » lève le blocage sans contrôle, réservé à un terminal jamais synchronisé ; sinon la synchronisation sera refusée.

## 4. Sauvegarde de la base serveur

L'offre gratuite Supabase ne propose pas de sauvegarde. Scripts fournis :

- `infra/backup/pg_backup.sh` : `pg_dump` (format custom, schéma `public`, sans propriétaire ni droits), chiffré **AES-256** par `gpg` avec `BACKUP_PASSPHRASE` (≥ 20 caractères), empreinte dans `SHA256SUMS`.
- `infra/backup/pg_restore.sh` : vérification d'empreinte, **refus si la base cible contient déjà des tables**, déchiffrement, `pg_restore`, affichage de la version Alembic. Restaurer toujours dans une base neuve, vérifier, puis basculer.
- `.github/workflows/db-backup.yml` : export quotidien à 02:30 (Abidjan), conservé 30 jours en artefact. À activer en ajoutant les secrets du dépôt `SUPABASE_DB_URL` (URI session pooler) et `BACKUP_PASSPHRASE`.

Essai local réalisé (PostgreSQL 18.6) : export chiffré → restauration dans une base neuve → lignes identiques table par table, empreinte de l'historique des événements identique, RLS conservée ; seconde restauration refusée (base non vide) ; mauvais mot de passe refusé.

## 5. Mise à jour Android

Installer avec `adb install -r` et la même identité de signature ; numéros de version croissants. Les migrations SQLite sont additives et testées depuis les schémas figés `drift_schemas/schema_v*.sql`. **Ne jamais lancer `flutter test integration_test` sur le terminal de production** : l'outil désinstalle l'application en fin de test (incident du 6/10/2026).

La clé debug permet uniquement les essais. La clé de production devra être générée et stockée hors dépôt, avec sauvegarde chiffrée et procédure d'accès (lot livraison).

## 6. Mise à jour du serveur et retour arrière

Toutes les migrations Alembic sont additives ; tout `downgrade` destructif est bloqué. Avant une mise à jour serveur : sauvegarde validée (§4), déploiement du serveur **avant** le terminal (sinon les nouveaux types d'opération sont refusés puis renvoyés plus tard), vérification `/health/ready` et liste OpenAPI. Retour arrière = restauration de la sauvegarde dans une base neuve, jamais par suppression de colonnes. Aucune migration sur une production existante sans autorisation explicite.
