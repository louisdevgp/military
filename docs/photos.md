# Photos locales — incrément 0.2.0

Le sélecteur Android `ACTION_OPEN_DOCUMENT` fournit un accès au seul fichier choisi, sans permission générale de lecture du stockage. Trois photos maximum par article, couverture en première position. L’import est facultatif et ne publie pas l’article.

La passerelle Kotlin accepte JPEG, PNG et WebP, limite la source à 12 Mio et 64 mégapixels, décode avec échantillonnage, corrige l’orientation EXIF des JPEG, réduit le plus grand côté à 1280 pixels et réencode en JPEG qualité 85 sur fond blanc. Les métadonnées source ne sont pas recopiées. La sortie doit rester inférieure à 2 Mio. Les fichiers sont stockés dans `files/catalog_images/<UUID>.jpg` dans l’espace privé de l’application.

La migration SQLite **1 → 2** ajoute `local_product_photos`, liée aux articles, avec positions 0 à 2 et chemins uniques. Le nom de la base ne change pas. Le rattachement des photos, la création de l’article, le mouvement initial et l’événement sont transactionnels. Une erreur de rafraîchissement après commit ne transforme pas la création réussie en échec et ne déclenche pas la suppression des photos enregistrées.

L’annulation normale de la fiche et le retrait d’une image suppriment seulement la copie provisoire. Si le processus Android est tué pendant une fiche non enregistrée, des fichiers orphelins peuvent rester : aucun nettoyage automatique n’est encore lancé. Un futur nettoyage devra comparer les chemins référencés et tenir compte des fiches actives.

Les fichiers ne sont **pas encore synchronisés ni sauvegardés hors du TPE**. Les chemins privés sont exclus des événements serveur. La synchronisation des données ne constitue donc pas une sauvegarde des photos. Il faudra ajouter un transport de médias authentifié, une validation serveur, des références stables et une restauration des fichiers avant la publication sur le site.

Depuis 0.6.2, l'administrateur modifie les photos d'un article existant (ajout, retrait, couverture) ; la liste est remplacée dans une transaction et les fichiers retirés sont supprimés après commit. La prise de vue directe et le recadrage manuel restent hors périmètre. Les résultats exécutés sont consignés dans [recette.md](recette.md), en distinguant tests avec sélecteur simulé et import Android réel.
