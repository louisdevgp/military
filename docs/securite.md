# Sécurité du terminal et du serveur (lot 7, 0.14.0)

## 1. Activation du terminal et jetons courts

Le terminal n'utilise plus de jeton partagé. Il est activé une fois avec un **code d'activation** :

- le code compte 12 caractères (`XXXX-XXXX-XXXX`, environ 59 bits) ;
- il est valable **15 minutes** et ne sert **qu'une fois** ;
- demander un nouveau code annule le précédent ;
- **5 essais erronés** l'annulent aussi.

Le serveur échange ce code contre un **identifiant d'appareil**, que le H10 garde chiffré par le Keystore Android. Cet identifiant ne sert qu'à obtenir des **jetons d'accès de 15 minutes** signés (HMAC-SHA256). Le terminal les renouvelle tout seul, et il redemande un jeton si le serveur le juge expiré (horloge du terminal décalée).

Le serveur ne garde que des **empreintes SHA-256** du code et de l'identifiant, jamais les valeurs. Les tables `activation_codes` et `terminal_credentials` viennent de la migration additive 0008 ; la sécurité par ligne y est activée.

Un identifiant est refusé dans trois cas :
- il a été révoqué ;
- il n'a pas servi depuis 90 jours ;
- une nouvelle activation a eu lieu : il n'y a qu'un terminal actif à la fois.

### Obtenir un code (administrateur de la boutique)

1. Sur Render, ouvrir le service, puis **Environment**, et copier la valeur de `MONO_ADMIN_TOKEN`. C'est un secret : il ne faut ni le coller dans une discussion ni l'envoyer par message.
2. Sur le PC, dans PowerShell :

   ```powershell
   $admin = Read-Host -AsSecureString "Jeton administrateur"
   $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($admin))
   curl.exe -s -X POST -H "Authorization: Bearer $plain" https://mono-api-recette.onrender.com/api/admin/activation-code
   ```

   La réponse donne `code` et `expires_at`. Si le serveur dormait, la commande peut prendre jusqu'à une minute.
3. Sur le H10 : se connecter en administrateur, puis **Administration → Synchronisation → Activer** (ou **Réactiver**). Saisir l'origine du serveur et le code, puis toucher **Activer la synchronisation**.

### Révoquer le terminal (perte, vol, remplacement)

Même commande, avec l'adresse `/api/admin/revoke-terminal`. Elle répond `{"revoked": n}` et l'effet est immédiat : le terminal ne peut plus synchroniser, et les opérations restent en attente sur lui. Une nouvelle activation révoque aussi automatiquement l'appareil précédent.

### Ancien jeton de recette

En mode recette, le jeton `MONO_SYNC_TOKEN` reste accepté jusqu'à l'activation, pour que le H10 déjà configuré continue de synchroniser. Une fois le H10 activé, on peut supprimer `MONO_SYNC_TOKEN` et `MONO_TOKEN_EXPIRES_AT` sur Render. En production (`MONO_RECETTE_MODE=false`), seul le parcours par activation fonctionne.

## 2. Base locale chiffrée

La base SQLite du terminal est chiffrée avec SQLite3 Multiple Ciphers : chiffrement ChaCha20-Poly1305 par défaut, licence MIT, binaires vérifiés par le paquet `sqlite3`.

- **Clé** : 256 bits aléatoires, créée au premier démarrage et gardée dans le coffre chiffré par le Keystore Android.
- **Bases existantes** : une base encore en clair (installation antérieure ou sauvegarde restaurée) est chiffrée sur place au démarrage. Une copie est conservée jusqu'à ce que la base chiffrée ait été rouverte et vérifiée (`integrity_check`) ; en cas d'échec, la base en clair est remise et l'application affiche un message sans rien effacer.
- **Clé introuvable** : l'application ne crée jamais de nouvelle clé pour une base déjà chiffrée. Elle affiche un message (« Clé de la base locale introuvable »).
- **Sauvegardes** : l'instantané est déchiffré avant d'être scellé par le mot de passe de sauvegarde (AES-256-GCM, PBKDF2 210 000 itérations). Une sauvegarde se restaure donc sur un autre terminal, puis y est chiffrée avec la clé de ce terminal.
- **Non chiffrés** : les photos et le logo (fichiers privés de l'application) restent en clair. La sauvegarde Android automatique est désactivée (`allowBackup=false`).

Conséquence : une copie brute de la base, par exemple par `adb` sur un appareil de développement, ne permet plus de lire les ventes ni de chercher les PIN hors ligne.

## 3. Récupération de l'accès administrateur

- À l'activation du premier administrateur, un **code de secours** de 16 caractères (`XXXX-XXXX-XXXX-XXXX`, environ 79 bits) s'affiche **une seule fois**. Il faut confirmer l'avoir noté pour continuer.
- Les terminaux déjà en service n'en ont pas encore : **Utilisateurs → Code de secours administrateur → Créer**. Renouveler un code annule le précédent.
- **PIN oublié** : sur l'écran de verrouillage, toucher **PIN administrateur oublié ?**, saisir le code de secours, choisir l'administrateur, puis entrer le nouveau PIN deux fois. Le code est alors **remplacé** par un nouveau, à noter de la même façon.
- Après 5 essais erronés, la récupération est bloquée 1 minute, puis plus longtemps (jusqu'à 15 minutes).
- Seule l'empreinte PBKDF2 du code est gardée. Les événements d'audit `user.admin_recovered` et `security.recovery_code_created` ne contiennent ni le PIN ni le code. Le serveur exige que l'auteur soit l'administrateur récupéré.
- L'écran Utilisateurs signale quand il n'y a qu'**un seul administrateur actif**. Il est recommandé d'en créer un second.
- **Limite** : un terminal restauré et bloqué en attente de réconciliation n'accepte aucune nouvelle opération, récupération comprise. Il faut se connecter avec un PIN administrateur connu dans la sauvegarde restaurée.

## 4. Limites restantes

- Un appareil hors ligne ne reçoit pas la révocation : elle s'applique à sa prochaine connexion.
- L'identifiant d'appareil n'est pas renouvelé à chaque usage : il reste valable tant qu'il sert au moins une fois tous les 90 jours et qu'il n'a pas été révoqué.
- L'APK de production signé, le mode production de l'application et la recette matérielle relèvent du lot 8.
