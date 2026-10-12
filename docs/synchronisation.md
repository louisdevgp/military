# Synchronisation v1 — premier parcours

Un événement contient `id` UUID, `terminal_id` UUID, `sequence` entier persistant, `version=1`, `kind`, `occurred_at` ISO 8601 avec fuseau, `actor_id`, `payload`. Exemples complets produits par le code Dart dans `contracts/vertical_v1.json` ; exclusivement données TEST.

Types : `catalog.created` (avec `color` et `size` facultatifs depuis 0.7.0), `sale.completed`, `variant.price_changed`, `sale.payment_corrected` (admin, motif, contrôle espèces sur le total serveur), `user.created`, `user.updated` (activation/désactivation), `user.pin_reset` (audit seul), `sale.returned` (admin ; RETURN ou CANCEL, prix et totaux recontrôlés sur l'instantané de la vente, cumul borné à la quantité vendue, annulation = exactement le reste), `expense.recorded`, `expense.cancelled` (admin ; double annulation refusée), `cash.closed` (admin ; attendu = fond + ventes − remboursements − dépenses, écart = compté − attendu, fond conservé ≤ compté), `backup.created` (admin ; audit seul), `stock.moved` (admin ; RECEPTION > 0, LOSS < 0, ADJUSTMENT ≠ 0, `counted` égal au stock résultant, stock négatif refusé), `variant.updated` (admin ; seuil, statut actif), `settings.receipt_updated` (admin ; nom, contacts, pied et type de logo, sans image ; journalisé sans projection serveur pour l'instant). Aucun événement ne contient de PIN ni d'empreinte de PIN ; un champ inattendu est refusé (422). Le premier `user.created` d'un administrateur qui se crée lui-même est accepté une seule fois ; ensuite seul un administrateur actif crée des comptes. Un opérateur désactivé ne peut plus soumettre d'opération. Le catalogue créé est non publié. Les évolutions devront conserver les lecteurs des anciennes versions ou fournir une migration explicitement testée.

## Garanties

L’outbox est écrite dans la transaction locale de l’opération. Le serveur verrouille la ligne du terminal provisionné dans PostgreSQL et exige la prochaine séquence. Les contraintes `events.id` et `(terminal_id, sequence)` assurent l’unicité. Le contenu complet est empreinté côté serveur après normalisation du schéma ; même clé et contenu différent → conflit 409. Le client ne fournit pas une empreinte faisant autorité.

Le serveur contrôle de nouveau prix historique, quantités, disponibilité, numéro, total, espèces et monnaie. Une erreur annule aussi les mouvements déjà préparés. Le serveur accuse `status=committed`, UUID, terminal, séquence et `received_at` seulement après commit. Un rejeu identique retrouve le même accusé et la même date de réception.

Le client contrôle les champs de l’accusé, marque l’événement synchronisé localement et conserve une date de dernière synchronisation. Il n’écrit jamais un stock reçu du serveur. En cas d’erreur : arrêt à la première opération, code technique sans payload personnel, compteur de tentatives et prochain délai 5 s, 10 s, 20 s… jusqu’à une heure. Le bouton manuel permet une reprise immédiate. Le service sait respecter le délai lors d’un appel non manuel ; depuis 0.10.0, l'application synchronise automatiquement (5 s après une opération, toutes les 2 min, application ouverte) avec des réglages chiffrés par le Keystore Android.

## Sécurité et limites de la recette

API privée protégée par un jeton aléatoire à expiration configurée, lié à un terminal. Les rôles admin/vendeur sont contrôlés dans les opérations et l’API. Depuis 0.4.0, chaque opération est attribuée à l'opérateur connecté par PIN local. Le PIN protège l'accès au terminal ; il ne remplace pas l'authentification serveur de production. Le jeton de recette ne constitue pas le futur mécanisme de renouvellement sécurisé.

Le mode production reste fermé (`MONO_RECETTE_MODE=false` et caisse sans `RECETTE_MODE`). Fait en 0.4.0 : authentification locale par PIN des opérateurs créés sur le terminal, limitation des tentatives, verrouillage d'inactivité. Restent à implémenter : activation en ligne, jetons d’accès courts avec renouvellement, secrets et clé de protection de la base dans Android Keystore (aujourd'hui, une copie de la base locale permettrait une recherche hors ligne des PIN à 6 chiffres).

Un appareil hors ligne ne reçoit pas une révocation distante. La politique de durée maximale hors ligne et de réactivation devra être validée avant exploitation. Une restauration ancienne ne doit pas changer le terminal ni remettre le compteur à zéro : comparaison des UUID et séquences avec le serveur, récupération des opérations manquantes, puis déblocage explicite des nouvelles opérations.

Synchronisation ≠ sauvegarde : perte du terminal avant envoi = perte possible des opérations non sauvegardées. Cette tranche ne propose pas encore de restauration ; aucune manipulation manuelle de la base n’est une procédure de restauration validée.


## Réconciliation d'un terminal restauré (0.12.0)

`GET /api/private/sync/state` → `{terminal_id, last_sequence, sale_sequence}` ; `GET /api/private/sync/events?after=N&limit≤200` → enveloppes telles qu'envoyées, par séquence croissante. Même jeton et même contrôle de terminal que l'envoi. Le terminal rejoue les opérations manquantes, vérifie que les opérations communes ont le même identifiant (sinon conflit et blocage maintenu), puis reprend ses compteurs après ceux du serveur. Détails : `sauvegarde-et-mise-a-jour.md`.
