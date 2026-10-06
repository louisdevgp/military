# Cadrage — 6 octobre 2026

## État initial
Répertoire vide, sans dépôt Git ni code ni AGENTS.md préexistant. Cahier des charges fourni dans la conversation, conservé dans `docs/cahier-des-charges.txt`.

## Objectif et progression
V1 en deux semaines selon le périmètre fourni. Cette première tranche réalise le cadrage et le parcours vertical local article → vente → stock → ticket, puis valide tôt le contrat de synchronisation. Les modules suivants sont livrés séparément avec leurs validations. Ne pas qualifier cette tranche de V1 prête pour exploitation.

## Périmètre V1
Une boutique, un terminal vendeur, administrateur/vendeur, catégories/articles/variantes, mouvements de stock, ventes payées en totalité, tickets et duplicatas, retours/annulations/remboursements, dépenses, rapports/CSV, synchronisation, sauvegardes/restauration, catalogue public en lecture seule.

Exclusions : multi-boutiques, ventes simultanées multi-TPE, exécution de paiements bancaires ou Mobile Money, crédit, paiements partiels, commande sur le site, fiscalité non spécifiée, comptabilité réglementaire complète.

## Décisions
- Monolithe modulaire. Le TPE est la seule autorité de saisie ; le serveur applique les événements dans l'ordre et expose une projection. Aucune valeur serveur ne remplace le stock local.
- SQLite local : vente, snapshots de lignes, mouvements, compteur persistant et outbox dans une même transaction.
- UUID pour terminal et opérations ; numéro lisible `FACT-<année>-<séquence>` (format du ticket client, décision du 6/10/2026) avec compteur de vente persistant qui ne repart jamais à zéro. L'unicité après changement de terminal ou restauration repose sur la réconciliation serveur, non sur un préfixe.
- FCFA en entiers, validation des bornes. Pas de calcul monétaire flottant.
- Impression après commit. En cas de résultat matériel inconnu, proposer un duplicata, jamais recréer la vente.
- Premier APK de recette clairement marqué comme tel ; aucun compte de production prédéfini. L'activation sécurisée et l'authentification complète constituent un jalon bloquant avant exploitation.
- Ticket conforme à l'annexe fournie par le client le 6/10/2026 (logo, nom, contacts 0706842586/0152656552, pied « Votre satisfaction, notre motivation. »). Vendeur et mode non espèces ajoutés discrètement (choix client). Les règles de champs client obligatoires restent à configurer.
- Couleurs (client, 6/10/2026) : le stock doit refléter la réalité. Une variante n'existe que pour une combinaison couleur × taille réellement présente, avec sa quantité ; de nouvelles couleurs ou tailles s'ajoutent à un article existant. Couleurs saisies librement (« Camouflage » est une couleur), prix par variante.
- Duplicata (choix client, 6/10/2026) : il reprend les réglages boutique **actuels** (nom, contacts, logo, pied) ; les lignes, montants, numéro et paiement restent ceux de la vente (ou de sa correction).
- Tailles (client, 6/10/2026) : treillis M à XXXL, rangers 38 à 46 ; chaque taille est une variante avec référence, prix et stock propres sous un même article. Autres grilles à préciser par la boutique.
- Profils (choix client) : code PIN à 6 chiffres pour chaque opérateur, haché PBKDF2-HMAC-SHA256 salé, jamais synchronisé ; blocage temporaire après 5 erreurs (1 à 15 min, persistant) ; verrouillage après 5 min d'inactivité. Premier administrateur créé à l'activation, aucun compte prédéfini ; le serveur l'accepte une seule fois (aucun `user.created` antérieur).
- Erreur de somme remise (choix client) : confirmation avant validation si la monnaie atteint le total ou 50 000 FCFA, montants rapides ; après la vente, correction du mode ou de la somme remise par un administrateur, avec motif, en opération séparée liée à la vente. Total, lignes et stock ne sont jamais modifiés ; l'annulation et les retours restent des opérations distinctes du lot suivant.
- Révocation hors ligne : un terminal déconnecté ne peut connaître immédiatement une révocation distante. Les durées d'autorisation et la réactivation doivent être validées avant production.

## Matériel constaté
ADB Wi-Fi opérationnel. `ro.product.manufacturer=SENRAISE`, modèle `H10`, Android `14`, API `34`, ABI `armeabi-v7a,armeabi`. Ne pas extrapoler de ces valeurs la compatibilité de l'imprimante. Le H10P-OS01 annoncé reste à rapprocher de l'étiquette fournisseur.

## Dépendances externes
SDK officiel imprimante H10/Android 14, documentation erreurs et licence de redistribution ; papier et inspection du ticket ; clé de signature de production sauvegardée hors dépôt ; hébergement/domaine/HTTPS ; coordonnées et logo définitifs. Docker absent du PATH lors de l'inspection initiale.
