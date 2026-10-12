# Journal de recette

## 6 octobre 2026 — inspection
- Répertoire initial vide, aucun code préexistant.
- Flutter 3.47.6 stable, Dart 3.13.5 ; `flutter doctor -v` sans anomalie.
- Python 3.13.14, Node 22.21.1, npm 10.9.4, Git 2.52.0.
- Android via ADB Wi-Fi : SENRAISE H10, Android 14 / API 34, ARM 32 bits.
- Ces constats décrivent l’inspection initiale ; les validations suivantes ont ensuite été exécutées.

## Première tranche 0.1.0+2 — validée le même jour

- 15 tests Flutter réussis, analyse sans anomalie. Parcours SQLite, paiement, stock insuffisant, concurrence, idempotence, panne imprimante, synchronisation/rejeu et interface.
- 14 tests API réussis ; 1 test PostgreSQL ignoré faute de serveur local. Ruff et format Python réussis. Avertissement de dépréciation Starlette/httpx, sans échec de test.
- Contrat JSON exporté par Flutter puis consommé par le test API. Docker, PostgreSQL réel et workflow GitHub non exécutés sur ce poste.
- Test d’intégration Flutter exécuté sur le SENRAISE H10 réel via ADB Wi-Fi : SQLite persistante, panier, paiement, stock, duplicata simulé, réouverture et intégrité. Base temporaire distincte du catalogue installé, supprimée après le test.
- APK normal 0.1.0+2 compilé, signature Android Debug vérifiée, installé et ouvert sur le H10. Capture : `recette/h10-catalogue.png`.
- Artefact conservé : `livrables/mono-recette-0.1.0-debug.apk`, SHA-256 `5C99AE6DDCD14B8E3C8E380603FE4F4EC5DD996B94B10220EF159347987F298D`.

## Incrément 0.2.0+3 — photos et interface

Catalogue en grille avec catégories, photos et fiche détaillée ; formulaire plein écran avec trois photos ; panier illustré ; paiement avec monnaie calculée avant validation ; historique retravaillé. Photos locales privées, non synchronisées. Migration additive SQLite 1 → 2.

- Format Dart appliqué, `flutter analyze` : **aucune anomalie**.
- `flutter test --no-pub --reporter expanded` : **23 tests réussis**. Le lot photos couvre import simulé dans le formulaire, annulation et suppression des brouillons, absence de fichier, doublon de chemin, rollback outbox, erreur de lecture après commit, réouverture SQLite avec photos et aperçu de monnaie. Les tests UI attendent le décodage réel des images avant le nettoyage des fichiers Windows.
- Migration depuis le SQL v1 figé et peuplé : identité terminal, compteurs, article, stock, prix, historique et outbox conservés ; table de photos créée et version 2 vérifiée.
- `flutter build apk --debug --target-platform android-arm --dart-define=RECETTE_MODE=true` : **réussi**. Passerelle Kotlin photos compilée.
- Test d’intégration sur le **H10 physique : 1 réussi**, avec base temporaire isolée et supprimée. Parcours panier/paiement, conservation du stock et de la vente, duplicata simulé et refus explicite du canal imprimante non intégré.
- APK normal réinstallé avec `adb install -r` après le test : **Success**, `versionName=0.2.0`, `versionCode=3`. La signature Android Debug est identique à celle de 0.1.0. Aucune désinstallation ni réinitialisation des données.
- Interface de création inspectée sur le H10, sans débordement visible. Capture sans données : `recette/h10-0.2-article.png`.
- L’utilisateur a ensuite importé trois photos dans le formulaire sur le H10 ; trois fichiers JPEG privés de 26 145 octets et les trois aperçus ont été observés. La saisie a été laissée intacte à l’utilisateur. Cela ne remplace pas une recette exhaustive des formats, orientations et limites de taille sur appareil.
- Artefact normal : `livrables/mono-recette-0.2.0-debug.apk`, SHA-256 **`DC77C60C151F380E8FB4F851E528F4CE4FC65ED6C91E40458470D161059A271E`**.
- Preuves locales : `.artifacts/flutter-tests-0.2.log`, `.artifacts/android-build-0.2.log`, `.artifacts/device-test-0.2.log`. Les avertissements Java/Gradle concernant les futurs accès natifs n’ont pas empêché la compilation. Drift avertit de plusieurs instances dans les tests isolés ; aucun exécuteur SQLite n’y est partagé.

Les déconnexions du service d’approbation automatique ont empêché certaines commandes de démarrer ; les relances ont utilisé le même contrôle d’approbation. Les tests initialement demandés ont pu être relancés : 15 Flutter et 14 API réussis avant la dernière refonte.

## Incrément 0.3.0+4 — impression intégrée H10 et ticket client

- Service constaté sur le H10 : application système SRPrinter `recieptservice.com.recieptservice` 8.3.5, service `.service.PrinterService` déclaré `exported=true` sans permission (manifeste lu avec `aapt2`). Interface déclarée dans `android/app/src/main/aidl` d'après des signatures publiques (paquet pub.dev `senraise_printer`, éditeur non vérifié) ; aucun code tiers intégré.
- Pont `PrinterBridge.kt` : liaison avec délai, réponse unique succès/erreur, validation complète du ticket avant tout ordre. Le service n'expose aucun état papier/capot : la caisse annonce « transmis, à vérifier », jamais « imprimé ».
- Ticket construit d'après l'annexe client (logo, contacts, client/unité, `FACT-<année>-<séquence>`, tableau DESIGNATION/P.U/Qte/MONTANT, TOTAL FACTURE, SOMME REMISE, RENDU, pied). Vendeur et mode non espèces ajoutés discrètement sur décision client. Numérotation `FACT-2026-00001` ; le serveur accepte encore l'ancien format des outbox 0.2.
- Flutter : analyse sans anomalie, **27 tests réussis** (dont rendu du ticket, blocs transmis au canal, refus du service). API : **16 tests réussis sur PostgreSQL 18.6 réel** (binaires portables EDB, SHA-256 vérifié, `.tools/`), y compris le test de concurrence ; 15 réussis + 1 ignoré sur SQLite.
- APK 0.3.0+4 installé avec `adb install -r` (données conservées) ; liaison de l'application au `PrinterService` constatée avec `dumpsys activity services`.
- **Premier ticket papier observé (photo utilisateur, 6/10/2026)** : duplicata d'une vente de recette. Logo, accents (« Opérateur »), montants, DUPLICATA, totaux et pied lisibles. Défauts constatés : logo aligné à gauche et nom de boutique imprimé à côté du logo ; « DESIGNATION » coupé à 10 caractères en taille 24 ; ancien numéro long sur deux lignes. Corrections : logo centré sur une bande de 384 points puis saut de ligne, tableau en taille 20. **À revérifier sur papier.**
- Non testé : papier absent, capot ouvert, ticket test complet après corrections, largeur imprimable confirmée par le fournisseur.

## Incrément 0.4.0+5 — profils PIN et erreurs de caisse

- Schéma SQLite v3 (migration additive v1/v2 → v3 : tables `users` et `sale_corrections`). Tests de migration depuis les schémas v1 et v2 figés : identité terminal, compteurs, ventes et outbox conservés.
- Activation du premier administrateur, déverrouillage par PIN sur pavé numérique, blocage persistant après 5 erreurs, verrouillage après 5 min d'inactivité (jamais pendant une validation en cours), gestion des utilisateurs par l'administrateur, actions d'administration masquées aux vendeurs et refusées dans les opérations locales et l'API.
- Somme remise : montants rapides, confirmation si monnaie ≥ total ou ≥ 50 000 FCFA ; correction après vente par un administrateur avec motif, visible dans l'historique et sur le duplicata (« Paiement corrigé le … »).
- Flutter : analyse sans anomalie, **36 tests réussis** (vecteurs PBKDF2 publiés, règles PIN, blocage, droits, correction, migration v2 → v3, parcours écran activation/verrouillage/PIN). Contrat régénéré : 6 événements Dart (admin, vendeur, article, vente, prix, correction) rejoués par l'API.
- API : migration Alembic 0002 additive (nom d'opérateur, table `sale_corrections`, retour arrière destructif bloqué). **19 tests réussis sur PostgreSQL 18.6**, 18 + 1 ignoré sur SQLite. `alembic upgrade head` appliqué sur une base PostgreSQL déjà en 0001 → `0002 (head)`.
- APK 0.4.0+5 installé avec `adb install -r` sur le H10 ; écran d'activation constaté après migration (capture d'écran). Création des comptes, durée réelle du calcul PIN sur le H10 et parcours complet sur l'appareil : **à faire par l'utilisateur**.
- Artefact : `livrables/mono-recette-0.4.0-debug.apk`, SHA-256 `1E4ED1D0E8FFFE6DAF562CE7C00F650EBBAE39A15FDC7D730E5C09657E33AD51` (signature Android Debug, pas un APK de production).
- Limite : le travail PBKDF2 (20 000 itérations, Dart pur dans un isolat) est à mesurer sur le H10 ; sans clé Keystore, une copie de la base permettrait une attaque hors ligne sur un PIN à 6 chiffres.

## Incrément 0.5.0+6 — grilles de tailles

- Grilles transmises par le client le 6/10/2026 : treillis M, L, XL, XXL, XXXL ; rangers pointures 38 à 46. Les autres articles gardent une variante libre en attendant ses précisions.
- Création d'un article avec toutes ses tailles en une transaction : référence `BASE-TAILLE`, libellé « Couleur · Taille XL », prix commun ou par taille, stock par taille (mouvement INITIAL seulement si stock > 0), un événement `catalog.created` par variante partageant le même article. Une référence déjà prise annule toute la création.
- Catalogue : une carte par article (« 9 tailles », « Dès 15 000 FCFA », stock total), choix de la taille avec stock et prix, taille épuisée non sélectionnable.
- Serveur : une nouvelle variante d'un article connu est acceptée si catégorie et nom correspondent, sinon `PRODUCT_CONFLICT`.
- Flutter : analyse sans anomalie, **38 tests réussis**. Contrat régénéré (8 événements dont deux tailles d'un article). API : **20 tests réussis sur PostgreSQL 18.6**, 19 + 1 ignoré sur SQLite. Schéma SQLite inchangé (v3).
- APK 0.5.0+6 installé (`adb install -r`). Artefact `livrables/mono-recette-0.5.0-debug.apk`, SHA-256 `34F4D6EDAE79609ADC9BB72A6CF3E172805A4BA73FBB89F15AE255113B8491CB`. Création d'une grille sur l'appareil : à faire par l'utilisateur.

## Incrément 0.6.0+7 — réglages du ticket, icône et écran de démarrage

- Menu **Administration** (admin seulement) : Utilisateurs, **Ticket et boutique**, Synchronisation. La page Ticket et boutique modifie le nom (40 caractères), les contacts (64), le pied (80) et le logo (d'origine, image choisie via le sélecteur Android, ou aucun), avec aperçu en direct. Réglages en SQLite (schéma v4, migration additive), un événement d'audit `settings.receipt_updated` sans image ; un logo personnalisé disparu revient au logo d'origine.
- Icône de l'application : logo client (icônes classiques rondes et icône adaptative Android 8+, logo dans la zone de sécurité 66 dp). Écran de démarrage : API SplashScreen Android 12+ (fond blanc, ou vert foncé en mode sombre) et fond de lancement pour les versions antérieures ; écran Flutter au logo pendant la lecture des comptes.
- Flutter : analyse sans anomalie, **40 tests réussis** (réglages par défaut de l'annexe, validation, refus vendeur, audit, logo manquant, migration vers v4). Contrat régénéré (9 événements). API : **21 tests réussis sur PostgreSQL 18.6**, 20 + 1 ignoré sur SQLite.
- APK 0.6.0+7 installé (`adb install -r`), application lancée sans plantage (processus actif, aucun FATAL dans logcat). Le H10 était verrouillé : icône et écran de démarrage **non observés**, à vérifier par l'utilisateur. Artefact `livrables/mono-recette-0.6.0-debug.apk`, SHA-256 `A8EFE432D5E690628CB5419D426DD8988198D3159DE0D29B2BC06833BDC53295`.
- Limite : le logo choisi est recompressé en JPEG (1280 px max) par le sélecteur ; sa netteté à l'impression thermique reste à vérifier sur papier.

## Incrément 0.6.1+8 — modification des prix

- Fiche article (administrateur) : **Modifier le prix**, une taille à la fois ou même prix pour toutes. Transaction unique, tout ou rien ; prix inchangés ignorés ; un événement `variant.price_changed` par prix modifié (déjà validé par le serveur). Ventes passées et duplicatas gardent leur prix figé.
- Flutter : analyse sans anomalie, **41 tests réussis**. APK 0.6.1+8 installé (`adb install -r`, données de test conservées). Artefact `livrables/mono-recette-0.6.1-debug.apk`, SHA-256 `032B97608700A2D2CFCD928358AAE195B19C0D7429FC2D35AECF10D52B78A3FE`. Essai sur l'appareil : à faire par l'utilisateur.

## Incrément 0.6.2+9 — modification des photos

- Fiche article (administrateur) : **Modifier les photos** — ajout (3 max), retrait, choix de la couverture. Remplacement transactionnel de la liste ; fichiers retirés supprimés après commit ; nouvelles images abandonnées supprimées à l'annulation. Photos locales, absentes du ticket et des événements (aucune synchronisation ni sauvegarde des fichiers).
- Flutter : analyse sans anomalie, **42 tests réussis**. APK 0.6.2+9 installé (`adb install -r`, données conservées). Artefact `livrables/mono-recette-0.6.2-debug.apk`, SHA-256 `40A69CCD621E028ADC5F019482AE10DDE7F8976F31DE8F6393B9DB340E59A1DA`. Essai sur l'appareil : à faire par l'utilisateur.

## Revérification complète 0.6.2+9 — 6 octobre 2026, 17 h 30

- Aucun fichier de code modifié depuis la construction 0.6.2 (contrôle des dates).
- Flutter : format sans changement, analyse sans anomalie, **42 tests réussis** (`.artifacts/flutter-tests-0.6.2.log`).
- API : Ruff et format OK ; **20 réussis + 1 ignoré sur SQLite**, **21 réussis sur PostgreSQL 18.6** (serveur portable relancé, il était arrêté) ; base de contrôle Alembic en `0002 (head)`.
- Test d'intégration sur le **H10 physique : 1 réussi** (`.artifacts/device-test-0.6.2.log`) : panier, paiement, stock, duplicata, réouverture SQLite, liaison au service SRPrinter sans impression.
- APK normal réinstallé ; écran de démarrage (logo sur fond blanc) observé par capture, puis écran d'activation.
- **Incident — perte des données de recette du H10.** L'outil `flutter test integration_test -d <H10>` a mis à jour l'application en conservant ses données (17:38:08), puis l'a **désinstallée** en fin de test ; la réinstallation suivante (17:39:09) était donc une première installation (nouvel UID, base recréée, aucune photo). Perdus : ventes de recette 0.1/0.2 et toute saisie faite sur l'appareil depuis 0.4.0 ; rien n'avait été synchronisé. Cause : l'affirmation antérieure « aucune désinstallation » n'avait pas été revérifiée. **Règle : ne plus lancer de test d'intégration sur le H10 sans accord explicite et sauvegarde préalable de la base**, tant que les tests n'utilisent pas un identifiant d'application distinct.
- Non revérifié sur papier lors de cette passe : impression réelle, papier absent.

## Incrément 0.7.0+10 — couleurs et stock réel par combinaison

- Variantes structurées : `color` et `size` (SQLite v5 et Alembic 0003, migrations additives). Création par matrice couleurs × tailles : seule une case de stock saisie crée la variante (vide = n'existe pas, 0 = existe épuisée). Référence `BASE-COULEUR-TAILLE` (accents retirés), libellé « Noir · Pointure 42 ». Limite 60 variantes par opération.
- **Ajout de variantes** à un article existant (nouvelle couleur ou taille reçue) : combinaisons existantes affichées « existe », doublon de libellé ou de référence → rien n'est créé. Suggestions des couleurs déjà utilisées.
- Vente : carte « 2 couleurs · 3 variantes », choix de la couleur puis de la taille.
- `catalog.created` porte `color` et `size` facultatifs ; les anciens événements restent valides. Le serveur les enregistre.
- Flutter : analyse sans anomalie, **44 tests réussis**. Contrat régénéré (variantes couleur). API : **22 réussis sur PostgreSQL 18.6**, 21 + 1 ignoré sur SQLite ; base de contrôle en `0003 (head)`.
- APK 0.7.0+10 mis à jour par `adb install -r` (première installation inchangée : données conservées). **Aucun test d'intégration sur l'appareil.** Artefact `livrables/mono-recette-0.7.0-debug.apk`, SHA-256 `9923DE28E0536D750DB9440F67FF446337D49F0E6925CEB6BF5C4A904C943B5F`.

## Incrément 0.7.1+11 — préparation du déploiement de recette (Supabase + Render)

- Conteneur API : `alembic upgrade head` → `python -m mono.provision` (idempotent, refus si autre terminal) → uvicorn sur `$PORT`. `render.yaml` (Frankfurt, gratuit, jeton généré par Render, secrets saisis dans le tableau de bord). Migration 0004 : RLS activée sur toutes les tables PostgreSQL (accès REST Supabase bloqué, propriétaire non concerné). Guide : `deploiement-recette.md`.
- Caisse : réveil du serveur (`/health/ready`, 90 s) avant la synchronisation.
- Simulation locale de la commande de démarrage sur PostgreSQL 18.6 : migrations, provisionnement, `/health/ready` OK, **9/9 événements du contrat acceptés en HTTP** avec rejeu identique, mauvais jeton → 401 ; redémarrage idempotent ; autre terminal → démarrage refusé. Image Docker **non construite** (Docker absent du poste).
- API : 21 + 1 ignoré (SQLite), **22 réussis sur PostgreSQL** avec RLS. Flutter : **44 tests réussis**.
- APK 0.7.1+11 mis à jour (`adb install -r`, données conservées). Artefact `livrables/mono-recette-0.7.1-debug.apk`, SHA-256 `F53A0B99C92A4F835B9374E2519B2EADEC78B39FC4C13D1EA08132452B4C8C19`.
- Déploiement Supabase/Render : **non effectué à ce stade** (comptes à créer par l'utilisateur).

## Incrément 0.8.0+12 — mouvements de stock (lot 1)

- Écran **Stock** (Administration, admin seulement) : recherche, filtre stock faible/épuisé, par variante **Réception** (+), **Perte** (−), **Correction** (±) avec motif obligatoire, **seuil d'alerte**, **désactivation/réactivation** (variante retirée de la vente, historique conservé) et **historique** des mouvements (type, quantité, date Abidjan, opérateur, motif). Écran **Inventaire** : quantités comptées, chaque écart crée une correction tracée avec la quantité comptée ; compte identique = aucun mouvement.
- Stock négatif refusé en SQL dans la transaction (mouvement + événement), refus = rien écrit. Catalogue : badge « Stock faible ».
- SQLite v6 (seuil, quantité comptée) et Alembic 0005, additifs. Événements `stock.moved` (quantité signée, cohérence du signe et du compte contrôlée par le serveur) et `variant.updated`.
- Flutter : analyse sans anomalie, **46 tests réussis** (dont parcours écran Stock). Contrat régénéré (12 événements). API : **23 réussis sur PostgreSQL 18.6**, 22 + 1 ignoré sur SQLite ; base de contrôle en `0005 (head)`.
- APK 0.8.0+12 mis à jour par USB (`adb -s H10P736253F0010 install -r`, données conservées). Artefact `livrables/mono-recette-0.8.0-debug.apk`, SHA-256 `CEDD1780AEA3D121C182C69A918F4D1EDD525B44CBAA53AC664524AEFFCAED6A`. Essai sur l'appareil : à faire par l'utilisateur.

## Limites matérielles et fonctionnelles

L’impression passe par le service SRPrinter du H10 (voir 0.3.0) ; un premier ticket papier a été observé. Le service ne signale ni papier absent ni capot ouvert : le résultat reste « transmis, à vérifier ». La compatibilité de l'interface n'est établie que par l'essai sur ce terminal et ce firmware (H10P-OS01 14.0.182, SRPrinter 8.3.5).

L’authentification de production, les photos serveur, la sauvegarde/restauration complète, les retours, dépenses, rapports et site public restent à réaliser. Aucune recette de redémarrage complet du téléphone, papier absent ou mode avion n’est déclarée réussie. Les opérations commerciales réelles ne sont pas autorisées par cette recette.

## Distinction obligatoire
Un retour de méthode SDK ne prouve pas que le papier est sorti ni qu'il est lisible. Un APK signé avec une clé de développement ne vaut pas APK de production. Les tests serveur SQLite ne valent pas tests PostgreSQL.
