# Plan de développement et critères de validation

Calendrier indicatif à partir du 6 octobre 2026, jours calendaires. Gel fonctionnel au jour 10. Le délai est exposé si le SDK, la recette physique ou les décisions commerciales arrivent tard.

| Jours | Lot | Critères de sortie |
|---|---|---|
| J1 | Cadrage, outils, matériel | Versions consignées, dépôt et conventions ; Android mesuré ; APK installé ; ticket physique si SDK validé, sinon simulateur explicite et demande fournisseur précise. |
| J1–J3 | Parcours vertical local | Catégorie/article/variante, stock initial, panier, paiement complet, vente atomique, historique, ticket et duplicata ; tests stock insuffisant, double validation, panne impression et conservation après réouverture. |
| J3–J4 | API et synchronisation | Migration, contraintes UUID et terminal/séquence, rejeu identique accepté, conflit de contenu refusé, ordre strict, réponse perdue puis rejeu ; stock et ventes identiques après synchronisation. |
| J4–J5 | Catalogue et stock | Désactivation, variantes, réceptions/pertes/inventaires tracés, autorisations et stock négatif bloqué. |
| J5–J7 | Corrections et pilotage | Retours cumulés bornés, remboursement unique, distinction endommagé/revendable, dépenses, bornes de périodes, rapports concordants et CSV. |
| J7–J8 | Site public | React/Vite responsive français, projection publique autorisée seulement, photos validées, prix optionnels, WhatsApp configuré, accessibilité et build. |
| J8–J9 | Sécurité et continuité | Provisionnement, RBAC local/API, accès courts, stockage Android sécurisé, limitation tentatives, verrouillage, sauvegardes et restauration réconciliée testée. |
| J10–J12 | Gel et recette | Tests critiques, PostgreSQL réel, réseau interrompu, impression/papier absent, redémarrage, mise à jour sans perte, restauration, revue secrets. |
| J13–J14 | Pilote et livraison | APK signé avec clé durable, backend/site compilés, CI, HTTPS, guides, PV de recette et limites explicites. |

Chaque lot : implémenter → exécuter les contrôles → corriger → consigner les preuves. Ne pas multiplier les modules avant validation du parcours et de la synchronisation.

## Suite validée le 12 octobre 2026

État : 0.7.1 (impression H10, profils PIN, couleurs × tailles, corrections de paiement, réglages ticket) ; déploiement de recette Supabase/Render préparé, en attente du dépôt GitHub.

Lots à réaliser, dans cet ordre, chacun validé (analyse, tests, PostgreSQL, APK) avant le suivant :

1. ✅ (0.8.0) Mouvements de stock : réception, perte, correction, inventaire (quantité comptée et écart tracés), seuil de stock faible, désactivation/réactivation, historique par variante.
2. ✅ (0.9.0) Retours et annulations : annulation complète, retour partiel cumulé borné, remboursement unique, revendable/endommagé.
3. Dépenses, rapports (jour, semaine, mois, année, période libre, fuseau Africa/Abidjan), alertes stock, export CSV, clôture de caisse.
4. Synchronisation automatique et réglages serveur conservés de façon sécurisée.
5. Sauvegarde et restauration (base et photos), réconciliation des séquences.
6. Fiches client et champs obligatoires configurables.
7. Sécurité de production : activation du terminal, jetons courts renouvelés, Keystore, base chiffrée.
8. Livraison : APK de production signé (clé hors dépôt), CI, tests sur l'appareil avec identifiant d'application distinct, recette matérielle (papier absent, redémarrage, hors ligne, mise à jour).
9. Site public React/TypeScript/Vite.

Gardé en amélioration, non planifié : lecteur de codes-barres du H10, impression d'étiquettes code-barres.
