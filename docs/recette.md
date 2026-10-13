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

## Incrément 0.9.0+13 — retours et annulations (lot 2)

- Historique (administrateur) : menu **Actions sur la vente** → **Retour ou annulation**. Retour partiel par quantité, cumul borné à la quantité vendue ; article **revendable** (remis en stock, mouvement RETURN) ou **endommagé** (non remis en vente) ; **Annuler la vente** rembourse tout ce qui reste ; motif obligatoire ; mode de remboursement. Ticket **REMBOURSEMENT / ANNULATION** imprimé ; le duplicata de la vente indique « VENTE ANNULÉE » ou « RETOUR PARTIEL » et le montant remboursé. La vente n'est jamais modifiée.
- Idempotence par identifiant d'opération (rejeu identique = même résultat, contenu différent = conflit) ; double annulation et dépassement refusés localement et par le serveur (`RETURN_EXCEEDS_SALE`, prix et totaux recontrôlés, annulation exacte du reste `CANCEL_INCOMPLETE`).
- SQLite v7 (`sale_returns`, `sale_return_lines`), Alembic 0006 avec RLS. Événement `sale.returned`.
- Correctif d'affichage trouvé par les tests : ligne de l'historique et ligne de quantité du retour débordaient sur les 360 dp du H10 (actions regroupées dans un menu, puce revendable/endommagé sur sa ligne).
- Flutter : analyse sans anomalie, **48 tests réussis**. Contrat régénéré (13 événements, dont un retour). API : **24 réussis sur PostgreSQL 18.6**, 23 + 1 ignoré sur SQLite ; base de contrôle en `0006 (head)`.
- APK 0.9.0+13 mis à jour par USB (données conservées). Artefact `livrables/mono-recette-0.9.0-debug.apk`, SHA-256 `3D7BBACACDC3051ED007DBCF46E800F2E1DC9A70151E282AC366BFA8965518A3`. Essai sur l'appareil : à faire par l'utilisateur.

## 0.9.1+14 — revue visuelle des tickets générés, code sur GitHub

- Rendu PNG des tickets produits par l'application (vente, duplicata d'une vente annulée, remboursement, ticket test) via `test/receipt_render_test.dart` (à la demande : `--dart-define=RENDER_RECEIPTS=true --dart-define=FONT_DIR=<polices Material du SDK>`), sortie `.artifacts/receipts/`. Conformes à l'annexe client. Rendu écran : il ne remplace pas une vérification papier (police et retours à la ligne du service d'impression).
- Le point médian « · » est retiré des désignations imprimées (caractère non vérifié sur l'imprimante) ; les accents ont été observés corrects sur papier.
- Flutter : **48 tests réussis** (+1 de rendu ignoré par défaut). APK 0.9.1+14 mis à jour par USB, données conservées. Artefact `livrables/mono-recette-0.9.1-debug.apk`, SHA-256 `6C609644EE1CC78C8CB02AF60C355C5660A382CBFAABC5FF66DD11EDFB7B36E2`.
- Code poussé sur `git@github.com:louisdevgp/military.git`, branche `main`.

## 12 octobre 2026 — déploiement de recette en ligne et intervention sur l'accès administrateur

- API Render en ligne (`https://mono-api-recette.onrender.com`) reliée à Supabase (Frankfurt, session pooler) : `/health/live` et `/health/ready` OK, synchronisation sans jeton refusée (401), catalogue public vide. Deux corrections pendant le déploiement : URI `postgresql://` acceptée (pilote psycopg) ; URL mal formée refusée sans être affichée (un mot de passe non encodé avait fait apparaître une partie du mot de passe dans les journaux Render : mot de passe Supabase réinitialisé).
- APK 0.9.1 recompilé depuis `0797ea2` et mis à jour sur le H10 (données conservées). État avant synchronisation : 10 opérations en attente, terminal `c4fc8f41-…`.
- **Intervention hors application** à la demande de l'utilisateur : l'administrateur était bloqué (6 erreurs de PIN) et l'application n'offre aucune récupération du code administrateur. Base sauvegardée sur le PC (`.artifacts/backups/`, non versionné), puis, application arrêtée, seul le compte administrateur modifié via `run-as` : nouveau PIN provisoire (PBKDF2-HMAC-SHA256, 20 000 itérations, sel aléatoire), compteur d'erreurs remis à zéro, blocage levé. Intégrité SQLite OK, opérations en attente inchangées, base recopiée vérifiée par empreinte. **Aucun événement d'audit n'a été produit pour cette modification.** Code provisoire communiqué à l'utilisateur, à remplacer depuis Utilisateurs → Nouveau code PIN.

## 12 octobre 2026 — synchronisation réelle H10 → Render → Supabase

- Répétition à blanc : les 10 opérations en attente du H10 rejouées dans l'ordre sur une copie locale du serveur (PostgreSQL 18.6, même terminal) : 10/10 acceptées.
- Synchronisation réelle depuis le H10 vers `https://mono-api-recette.onrender.com` : **réussie selon l'utilisateur** (« tout marche » : synchronisation, nouvelle vente, contrôle dans Supabase). Constat sur l'appareil par lecture de la base : **11/11 opérations `synced`**, aucune en attente ni en erreur, dernière synchronisation `2026-10-12T21:13:04Z`, 3 ventes.
- Limites inchangées : synchronisation manuelle, configuration à ressaisir après redémarrage (lot 4), jeton de recette partagé.

## Incrément 0.10.0+15 — synchronisation automatique et réglages sécurisés (lot 4)

- Réglages serveur (origine, jeton, interrupteur automatique) chiffrés AES-GCM avec une clé AndroidKeyStore non exportable (`SecureStoreBridge.kt`, sans dépendance tierce), stockés en préférences privées ; `allowBackup=false` déjà en place ; clés autorisées limitées ; valeur illisible → oubliée et redemandée. Plus de ressaisie au redémarrage.
- Synchronisation automatique : 5 s après chaque opération enregistrée et toutes les 2 minutes, en arrière-plan (jamais pendant une validation, jamais en double), respect du délai progressif d'une opération en erreur ; la synchronisation manuelle réessaie immédiatement. Interrupteur administrateur.
- Écran **Synchronisation** (Administration) : opérations en attente, dernière synchronisation, dernière erreur expliquée avec le code technique du serveur (`HTTP_409:SALE_NUMBER_MISMATCH`…), nombre d'essais et prochain essai, serveur enregistré (changer / oublier).
- Codes d'erreur : seul un code majuscule du corps de réponse est conservé, jamais un fragment de contenu.
- Flutter : analyse sans anomalie, **51 tests réussis** (refus vendeur, HTTPS obligatoire, jeton tronqué, réglages retrouvés après redémarrage, envoi automatique, erreur conservée et délai respecté, arrêt et oubli, filtrage des codes). API inchangée.
- APK 0.10.0+15 mis à jour par USB (données conservées). Artefact `livrables/mono-recette-0.10.0-debug.apk`, SHA-256 `8AEE9E3296F4FCA46B66441EDB897F59E641672937AC9C5F35FF2D6543B24791`. **Coffre Keystore non encore vérifié sur l'appareil** : à constater par l'utilisateur (configuration conservée après fermeture forcée).
- Limite : la synchronisation automatique ne tourne que lorsque l'application est ouverte (pas de tâche Android en arrière-plan).

## Correctif 0.10.1+16 — écran rouge au changement de code PIN

- Constat sur le H10 (capture) : écran d'erreur Flutter `_dependents.isEmpty` après **Utilisateurs → Nouveau code PIN**. Reproduit par un test d'écran : champs de la fenêtre libérés pendant sa fermeture (« TextEditingController used after being disposed »). Correction : libération après la fin de l'animation, comme pour les autres fenêtres ; inventaire fait, plus aucune fenêtre concernée.
- Flutter : **52 tests réussis** (dont `users_screen_test.dart`). APK 0.10.1+16 mis à jour par USB (données conservées). Artefact `livrables/mono-recette-0.10.1-debug.apk`, SHA-256 `E7520A690FBB023DBE183F0FD8CEA3592A864B85655D28CDDC7DCCCF0B7913E1`.

## Incrément 0.11.0+17 — dépenses, clôture de caisse, rapports et CSV (lot 3)

- **Dépenses** (Administration, admin) : type (charge / achat de stock / mouvement de trésorerie, pour ne jamais déduire deux fois le même argent), catégorie avec suggestions, montant, date (passée ou du jour), motif, mode de règlement ; jamais modifiées, annulation tracée avec motif.
- **Clôture de caisse** : espèces attendues = fond de caisse + ventes en espèces (mode effectif après correction) − remboursements en espèces − dépenses réglées en espèces depuis la clôture précédente (bornes strictes : une opération à l'instant d'une clôture appartient à la période close — défaut trouvé et corrigé par les tests) ; montant compté, écart (commentaire obligatoire), fond conservé ≤ compté ; fond initial saisi à la première clôture.
- **Rapports** jour / semaine ISO / mois / année / période libre, Africa/Abidjan (UTC+0, bornes [début, fin)) : ventes brutes, remboursements, nettes, quantités, paiements (modes effectifs), remboursements par mode, catégories, variantes, dépenses par type et catégorie, clôtures et écart cumulé, stock et alertes. Pas de « bénéfice » : marge déclarée non calculable (pas de prix d'achat).
- **Export CSV** (synthèse, lignes de vente, dépenses) via le sélecteur de documents Android (aucune permission) ; « ; », UTF-8 avec BOM, formules neutralisées.
- SQLite v8, Alembic 0007 (RLS). Événements `expense.recorded`, `expense.cancelled`, `cash.closed` (cohérence arithmétique contrôlée). Point privé `/api/private/reports/summary` ; **concordance testée** : le rapport du jour calculé par le terminal (contrat, 17 événements) est identique au rapport du serveur après rejeu.
- Flutter : analyse sans anomalie, **57 tests réussis** (finances, CSV, parcours écran dépense → clôture → rapport sur 360 dp). API : **27 réussis sur PostgreSQL 18.6**, 26 + 1 ignoré sur SQLite ; base de contrôle en `0007 (head)`.
- Serveur Render redéployé (liste OpenAPI : `/api/private/reports/summary` et les 14 types d'événements), puis APK 0.11.0+17 mis à jour par USB (données conservées). Artefact `livrables/mono-recette-0.11.0-debug.apk`, SHA-256 `52A816BDA2FEA0CBEA0A18C343E37A4B5F0A2CB39DDAD18E92569BB7A94873A7`.
- Limites : dépenses et clôtures réservées à l'administrateur ; caisse attendue calculée sur le terminal (le serveur vérifie la cohérence, pas les montants) ; enregistrement CSV non encore essayé sur l'appareil.

## Incrément 0.12.0+18 — sauvegarde, restauration et réconciliation (lot 5)

- Sauvegarde du terminal : `VACUUM INTO` + photos + logo, manifeste et empreintes SHA-256, archive chiffrée AES-256-GCM (PBKDF2 210 000 itérations, `BackupBridge.kt`), enregistrée via le sélecteur Android. Restauration (administrateur, ou écran d'activation d'un terminal neuf) : déchiffrement, contrôles de format, de version et d'empreintes, copie de sécurité préalable, remplacement au redémarrage avant ouverture de la base, contrôle d'intégrité, blocage des nouvelles opérations jusqu'à la réconciliation.
- Réconciliation : points serveur `/api/private/sync/state` et `/api/private/sync/events` ; rejeu local des opérations absentes de la sauvegarde avec leurs effets exacts, conflit d'identifiant → blocage maintenu, compteurs repris après le serveur ; comptes créés après la sauvegarde sans PIN (à redonner).
- **Scénario de perte testé** (`backup_test.dart`) : terminal A sauvegarde puis continue (compte, ventes, retour, réception, dépense, clôture, synchronisés) ; terminal B neuf restaure, est bloqué, se réconcilie (1 opération confirmée, 7 rejouées, pages de 3), retrouve exactement stock, compteurs, rapport et mouvements de A, puis vend `FACT-2026-00004` sans doublon et synchronise. Refus testés : mauvais mot de passe, version future, base modifiée, vendeur.
- Base serveur : `infra/backup/pg_backup.sh` / `pg_restore.sh` (gpg AES-256, empreintes, refus si base cible non vide) et tâche GitHub quotidienne (`db-backup.yml`, secrets à ajouter). **Aller-retour local réussi** sur PostgreSQL 18.6 (lignes, empreinte des événements, RLS identiques ; seconde restauration et mauvais mot de passe refusés) après correction de deux défauts du script trouvés par l'essai (format d'empreinte Windows, schéma `public`).
- Flutter : analyse sans anomalie, **59 tests réussis**. API : **28 réussis sur PostgreSQL 18.6**, 27 + 1 ignoré sur SQLite.
- Artefact `livrables/mono-recette-0.12.0-debug.apk`, SHA-256 `E16F052D9728904F625666905E1DF7BBB3A9E179BE9EA98D29749E7B67F1D254`.
- Non encore vérifié sur l'appareil : chiffrement natif, enregistrement et ouverture du fichier `.monobak`, redémarrage après restauration. Tâche GitHub non exécutée (secrets absents).

## Incrément 0.13.0+19 — informations client obligatoires (lot 6)

- Choix appliqué (cahier des charges §7, l'utilisateur n'ayant pas tranché) : nom, prénoms, unité et téléphone rendus **obligatoires ou facultatifs par l'administrateur** (Ticket et boutique), tous facultatifs par défaut ; **pas de carnet de clients** (données personnelles non conservées hors des ventes). Téléphone saisi vérifié (8 à 15 chiffres, « + » et espaces).
- Contrôle à l'enregistrement de la vente (dans la transaction, avant tout numéro ni mouvement) ; rejeu d'une vente déjà enregistrée non bloqué. Encaissement : champs obligatoires marqués « * », section client ouverte d'office.
- Événement d'audit `settings.customer_fields_updated` (admin, liste validée) ; rejoué par la réconciliation.
- Flutter : analyse sans anomalie, **60 tests réussis**. Contrat régénéré (18 événements). API : **29 réussis sur PostgreSQL 18.6**, 28 + 1 ignoré sur SQLite.
- Sur le H10 avant installation : aucune sauvegarde encore créée (essai de sauvegarde 0.12.0 à faire).

## Incrément 0.14.0+20 — sécurité de production (lot 7)

Détails et procédures : `securite.md`.

- **Récupération de l'accès administrateur** :
  - code de secours affiché une seule fois à l'activation ou depuis Utilisateurs ;
  - « PIN administrateur oublié ? » sur l'écran de verrouillage ;
  - code à usage unique, remplacé aussitôt ; essais limités ;
  - alerte quand un seul administrateur est actif ;
  - événements d'audit `user.admin_recovered` et `security.recovery_code_created`.
- **Activation du terminal et jetons courts** :
  - code d'activation à usage unique (15 min, 5 essais) demandé par l'administrateur avec `MONO_ADMIN_TOKEN` ;
  - identifiant d'appareil dans le Keystore ; jetons d'accès signés de 15 min, renouvelés automatiquement ;
  - révocation immédiate ; une réactivation révoque l'appareil précédent ;
  - empreintes SHA-256 seules en base (migration additive 0008, sécurité par ligne) ;
  - ancien jeton de recette accepté en mode recette jusqu'à l'activation.
- **Base locale chiffrée** :
  - SQLite3 Multiple Ciphers 2.5.0, clé de 256 bits dans le Keystore ;
  - chiffrement sur place de la base existante au démarrage, avec copie conservée jusqu'à la vérification ;
  - sauvegardes déchiffrées avant d'être scellées par leur mot de passe, donc restaurables sur un autre terminal ;
  - essai sur PC : le fichier ne contient plus de texte lisible, et toute lecture sans la bonne clé est refusée.
- **Vérifications** : analyse Flutter sans anomalie, **71 tests Flutter réussis** (1 ignoré, rendu des tickets à la demande). Contrat régénéré (21 événements). API : **37 tests réussis sur PostgreSQL 18.6**, 36 + 1 ignoré sur SQLite. Render redéployé : migration 0008 appliquée et clé de signature présente (un code factice est refusé avec `ACTIVATION_INVALID`).
- **H10** : essai sur l'appareil en attente (appareil déconnecté d'adb). Avant l'installation, la base du H10 sera copiée sur le PC, car l'installation la chiffre. Activation par code et création du code de secours à faire par l'administrateur.

## Incrément 0.14.1+21 — retirer un article de la vente

- **Stock → Retirer l'article de la vente** désactive toutes les couleurs et tailles d'un article en une transaction, après confirmation avec rappel du stock restant ; **Remettre tout l'article en vente** l'annule. Pas de suppression physique : historique, tickets, retours et rapports conservés. Un événement `variant.updated` audité par variante modifiée (type déjà validé par le serveur et rejoué par la réconciliation).
- Flutter : analyse sans anomalie, **72 tests réussis** (1 ignoré). Pas de changement serveur.

## Incrément 0.14.2+22 — historique selon le profil

- Un vendeur ne reçoit que ses propres ventes dans l'historique (filtre sur `seller_id` de l'instantané de vente, appliqué dans la requête) ; l'administrateur voit toutes les ventes avec le nom du vendeur et un filtre par vendeur. L'historique est vidé dès que l'opérateur connecté change. Pas de migration.
- Flutter : analyse sans anomalie, **75 tests réussis** (1 ignoré). Pas de changement serveur.

## Limites matérielles et fonctionnelles

L’impression passe par le service SRPrinter du H10 (voir 0.3.0) ; un premier ticket papier a été observé. Le service ne signale ni papier absent ni capot ouvert : le résultat reste « transmis, à vérifier ». La compatibilité de l'interface n'est établie que par l'essai sur ce terminal et ce firmware (H10P-OS01 14.0.182, SRPrinter 8.3.5).

L'APK de production signé, le mode production de l'application, les photos serveur et le site public restent à réaliser (lots 8 et 9). Aucune recette de redémarrage complet du téléphone, papier absent ou mode avion n’est déclarée réussie. Les opérations commerciales réelles ne sont pas autorisées par cette recette.

## Distinction obligatoire
Un retour de méthode SDK ne prouve pas que le papier est sorti ni qu'il est lisible. Un APK signé avec une clé de développement ne vaut pas APK de production. Les tests serveur SQLite ne valent pas tests PostgreSQL.
