# Sauvegarde et mise à jour — exigences avant production

**La sauvegarde/restauration complète n’est pas implémentée dans cette première tranche.** Ne pas utiliser l’APK pour des opérations commerciales irremplaçables. Une synchronisation réussie ne sauvegarde pas les événements encore en attente ni tous les fichiers locaux.

## Politique à implémenter au lot continuité

- Copie SQLite cohérente via mécanisme de sauvegarde, incluant données, outbox, UUID terminal, compteurs, paramètres et pièces jointes nécessaires. Une copie isolée du `.db` pendant l’activité n’est pas suffisante en présence d’un journal WAL.
- Manifeste de version, empreintes d’intégrité, archive chiffrée, copie protégée hors du terminal. Définir avec l’exploitant fréquence, rétention et lieu de conservation.
- Sauvegarde PostgreSQL planifiée avec `pg_dump`, copie protégée hors serveur et restauration d’essai dans une base distincte. Journalisation sans données personnelles.
- Restauration réservée à l’administrateur authentifié, ventes arrêtées, sauvegarde préalable, vérification d’intégrité et de version. Ne pas fournir de bouton de restauration tant que ce protocole n’est pas implémenté et testé.
- Réconciliation obligatoire avec le serveur : même terminal, mêmes UUID d’opérations, compareur de séquences et récupération des événements déjà reçus. Une sauvegarde ancienne ne devient jamais un nouveau terminal automatiquement.

## Mise à jour Android

Installer avec `adb install -r` et la même identité de signature. Les numéros de version doivent croître. Conserver l’UUID terminal, les compteurs, les ventes, le stock et l’outbox. La première migration est figée dans le schéma version 1 ; les versions futures nécessitent un test depuis une base antérieure peuplée.

L’incrément 0.2.0 ajoute une table de photos locales au schéma 2. Les fichiers `files/catalog_images` doivent être inclus dans la future sauvegarde : copier seulement la base SQLite ne copie pas les images. Le schéma 1 reste figé dans `drift_schemas/schema_v1.sql`.

La clé debug permet uniquement les essais. La clé de production devra être générée et stockée hors dépôt, avec sauvegarde chiffrée et procédure d’accès. Aucun fallback automatique vers la clé debug n’est configuré en release.

## Retour arrière

Ne pas rétrograder un schéma en effaçant des colonnes/données. Le `downgrade` initial Alembic refuse une opération destructive. Avant une mise à jour serveur, réaliser une sauvegarde validée, vérifier la compatibilité du binaire précédent avec le nouveau schéma et prévoir une restauration dans un environnement isolé. Aucune migration de production existante n’est autorisée par les scripts de cette tranche.
