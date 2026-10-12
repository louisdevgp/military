# Guide utilisateur — recette uniquement

L’écran affiche en permanence « Recette · <utilisateur> · <imprimante> ». Toucher cette mention donne les limites de la version et le **Ticket test**. Les opérations ne doivent pas servir à des ventes réelles.

## Comptes et code PIN

- Au premier lancement, créer le compte **administrateur** : nom et code PIN à 6 chiffres (pas 000000, 123456 ou 654321). Le PIN reste sur le terminal : le noter en lieu sûr.
- L’administrateur ajoute les vendeurs avec l’icône **Utilisateurs** (nom, rôle, PIN), peut leur donner un nouveau PIN ou les désactiver. Il reste toujours au moins un administrateur actif.
- Pour se connecter : choisir son nom puis taper le PIN sur le pavé. Après 5 erreurs, l’accès est bloqué temporairement (1 min, puis plus longtemps) ; un administrateur peut redonner un PIN.
- Le terminal se verrouille après 5 minutes sans toucher l’écran, ou avec l’icône cadenas. Le vendeur ne voit ni la création d’articles, ni les utilisateurs, ni les réglages serveur, ni la correction de paiement.

## Erreur sur la somme remise

- Les boutons **Montant exact** et billets ronds évitent la saisie. Si la monnaie à rendre atteint le total ou 50 000 FCFA, l’application demande de vérifier la somme avant de valider.
- Après la vente, seul un administrateur peut **corriger le paiement** depuis l’historique (icône crayon) : mode de paiement ou somme réellement remise, avec un motif obligatoire. La vente d’origine reste dans l’historique ; le duplicata affiche le paiement corrigé et la mention « Paiement corrigé le … ». Le total et les articles ne se corrigent pas ainsi : une annulation ou un retour sera une opération distincte.

## Dépenses, clôture de caisse, rapports

- **Administration → Dépenses** : bouton **Dépense** ; choisir le type (**Charge** : loyer, transport… ; **Achat de stock** ; **Mouvement de trésorerie** : retrait, dépôt en banque), la catégorie, le montant, le motif, le mode de règlement et la date. Une erreur se corrige avec **Annuler la dépense** (motif obligatoire) ; la dépense reste visible, barrée.
- **Administration → Clôture de caisse** (fin de journée) : l'écran calcule les espèces attendues. Saisir les espèces comptées ; en cas d'écart, un commentaire est obligatoire. Indiquer le fond de caisse conservé pour le lendemain. À la toute première clôture, saisir le fond de caisse de départ.
- **Administration → Rapports** : Jour, Semaine, Mois, Année ou Période ; flèches pour changer de période. Ventes brutes, retours, ventes nettes, paiements, catégories, variantes, dépenses, caisse, stock et alertes. L'icône de téléchargement exporte la synthèse, les lignes de vente ou les dépenses en CSV (ouvrable dans Excel) à l'endroit choisi.

## Retour, remboursement, annulation

Administrateur : **Historique** → menu ⋮ de la vente → **Retour ou annulation**. Indiquer la quantité rendue par article (+/−), choisir **Revendable** (remis en stock) ou **Endommagé** (pas remis en vente), le mode de remboursement et le motif, puis **Rembourser**. **Annuler la vente** rembourse tout ce qui n'a pas encore été rendu. Un ticket de remboursement s'imprime. On ne peut jamais rendre plus que la quantité vendue ni annuler deux fois ; la vente reste dans l'historique avec la mention du retour.

## Stock

Administrateur : **Administration → Stock**. Toucher une variante pour enregistrer une **Réception** (marchandise reçue), une **Perte** (casse, vol) ou une **Correction** (+ ou −), toujours avec un motif ; régler le **seuil d'alerte** (badge « Stock faible » au catalogue) ; **Désactiver** une variante qui ne se vend plus (elle disparaît de la caisse, son historique reste) ; consulter l'**historique**. Le stock ne peut jamais devenir négatif.

**Inventaire** (bouton en haut de l'écran Stock) : saisir la quantité réellement comptée pour chaque variante vérifiée (laisser vide si non comptée) ; chaque écart est enregistré comme correction avec la quantité comptée.

## Modifier un prix

Administrateur : toucher l'article dans le catalogue, puis **Modifier le prix**. Saisir le nouveau prix de chaque taille, ou utiliser **Même prix pour toutes** puis **Appliquer**. Le prix vaut pour les prochaines ventes ; les ventes déjà faites et leurs duplicatas gardent leur prix.

## Modifier les photos

Administrateur : toucher l'article, puis **Modifier les photos**. Ajouter jusqu'à 3 photos, retirer une photo (corbeille) ou toucher une photo pour la mettre en couverture, puis **Enregistrer**. Les photos ne sont pas imprimées sur le ticket.

## Ticket et boutique

Menu **Administration** → **Ticket et boutique** : nom de la boutique, contacts, pied de ticket et logo (logo d'origine, **Choisir une image** depuis le téléphone, ou **Sans logo**). L'aperçu montre le ticket avant d'enregistrer. Après enregistrement, imprimer un **Ticket test** pour vérifier le papier. Les tickets déjà imprimés ne changent pas ; un duplicata est toujours imprimé avec les coordonnées et le logo à jour (choix de la boutique).

## Créer un article avec ses couleurs et tailles

Dans **Créer un article**, choisir **Tailles treillis** (M à XXXL) ou **Pointures rangers** (38 à 46), saisir une référence de base (ex. RAN) et le prix de vente. Ajouter les couleurs réellement reçues (ex. Noir, Marron ; les couleurs déjà utilisées sont proposées). Pour chaque couleur, saisir le **stock réel** de chaque taille : case vide = cette combinaison n'existe pas, 0 = elle existe mais est épuisée. Seules les combinaisons saisies sont créées (ex. RAN-NOIR-42). Sans couleur, une seule ligne de tailles est proposée. **Variante unique** sert aux autres articles.

Quand une nouvelle couleur ou taille arrive : toucher l'article, **Couleurs / tailles**, ajouter la couleur ou saisir le stock des nouvelles tailles (les combinaisons existantes sont marquées « existe »).

À la vente, choisir la couleur puis la taille.

## Parcours de vente

1. Dans **Articles**, toucher **+** ou **Créer mon premier article**. Ajouter jusqu’à trois images depuis le sélecteur Android ; la première est la couverture. Saisir nom, catégorie, référence unique, variante, prix FCFA entier et stock initial, puis **Enregistrer l’article**. Les photos sont facultatives. Aucun article n’est préchargé ni publié sur le site.
2. Rechercher l’article ou filtrer par catégorie. Toucher la photo ouvre sa fiche ; faire glisser les photos pour consulter les autres. Toucher **+** sur l’article pour l’ajouter au panier. Le stock n’est pas modifié à ce stade.
3. Dans **Panier**, ajuster les quantités et toucher **Passer au paiement**.
4. Choisir un seul mode de paiement. Pour les espèces, saisir une somme remise couvrant le total. Les modes Mobile Money et virement sont des déclarations, sans transfert exécuté par l’application.
5. Les données client sont facultatives dans cette tranche. Valider : la vente, le stock et l’opération à synchroniser sont enregistrés ensemble.
6. Le ticket est envoyé à l’imprimante intégrée du H10, ou à la simulation si le service ne répond pas (le nom de l’imprimante est indiqué au-dessus de l’aperçu). Le service ne dit pas si le papier est sorti : vérifier le ticket. Un échec d’impression ne justifie jamais une nouvelle vente ; utiliser le duplicata.
7. Dans **Historique**, l’icône d’impression affiche un **DUPLICATA** du même numéro. Les 100 dernières ventes sont affichées.
8. **Administration → Synchronisation** (administrateur) : saisir une seule fois l'adresse du serveur et le jeton ; ils sont conservés de façon chiffrée. La synchronisation est ensuite automatique (après chaque opération et toutes les 2 minutes, application ouverte) ; l'écran indique les opérations en attente, la dernière synchronisation et la dernière erreur avec son explication. Le compteur diminue seulement après confirmation du serveur.

Si la synchronisation échoue, les ventes restent locales et visibles. Ne pas réinstaller l’application, effacer ses données ni remplacer sa base pour résoudre une erreur réseau. En cas de conflit d’identité/séquence, conserver la base et les journaux techniques sans données personnelles pour analyse.

Les règles rendant certains champs client obligatoires, les coordonnées et le logo boutique, le stock détaillé, les retours et les rapports seront configurables dans les prochains lots.

La monnaie à rendre s’affiche avant validation du paiement en espèces. Les informations client se déplient à la demande.

Photos : JPEG, PNG ou WebP, 12 Mo maximum à l’import. Elles sont copiées et redimensionnées dans l’application. Annuler la fiche supprime ses copies provisoires, sans toucher aux originaux. La prise de vue directe, la modification d’un article existant, le transfert au serveur et la restauration des images restent à réaliser.
