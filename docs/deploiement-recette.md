# Déploiement de recette — Supabase + Render

Environnement de **recette** : API en mode recette (jeton temporaire), données de test uniquement, pas de données client réelles. Ce n'est pas un déploiement de production.

| Élément | Service | Offre |
|---|---|---|
| Base PostgreSQL | Supabase, région Central EU (Frankfurt) | gratuite : 500 Mo, pause après 7 jours sans activité |
| API FastAPI | Render, région Frankfurt | gratuite : veille après 15 min sans requête, réveil ≈ 1 min |
| Caisse | APK de recette sur le SENRAISE H10 | synchronisation manuelle |

Aucun secret n'est dans le dépôt : le mot de passe de la base se saisit dans Render ; Render génère le jeton de synchronisation.

## 1. Base Supabase

1. Créer un projet : région **Central EU (Frankfurt)**, mot de passe de base long **en lettres et chiffres uniquement** (≥ 24 caractères, gestionnaire de mots de passe ; jamais dans le dépôt ni dans une conversation). Les caractères `@ # / :` cassent l'adresse s'ils ne sont pas encodés et une adresse mal découpée peut faire apparaître une partie du mot de passe dans les journaux du pilote (constaté le 12/10/2026 : mot de passe réinitialisé). L'API refuse désormais une adresse mal formée sans l'afficher.
2. Bouton **Connect** → onglet **Session pooler** (compatible IPv4, nécessaire depuis Render). Copier l'URI.
3. Remplacer `[YOUR-PASSWORD]` par le mot de passe et ajouter `?sslmode=require` à la fin :
   `postgresql://postgres.<ref>:<MOT_DE_PASSE>@aws-<n>-eu-central-1.pooler.supabase.com:5432/postgres?sslmode=require`
   - le préfixe `postgresql://` (ou `postgres://`) donné par Supabase est accepté tel quel : l'API le convertit en `postgresql+psycopg://` (pilote installé) ;
   - garder l'hôte et l'utilisateur exacts donnés par Supabase ;
   - encoder les caractères spéciaux du mot de passe (`@` → `%40`, `#` → `%23`, `/` → `%2F`, `:` → `%3A`).
4. Recommandé : **Project Settings → Data API** : désactiver l'API de données (l'application ne l'utilise pas). La migration 0004 active en plus la sécurité par ligne (RLS) sur toutes les tables, ce qui bloque l'accès par cette API même si elle reste active.

Les tables sont créées automatiquement par l'API au démarrage (migrations Alembic 0001 → 0004).

## 2. API Render

1. Compte Render relié au compte GitHub, accès au dépôt privé.
2. **New → Blueprint**, choisir le dépôt : Render lit `render.yaml` (service `mono-api-recette`, Docker, Frankfurt, gratuit).
3. Renseigner les valeurs demandées :
   - `MONO_DATABASE_URL` : l'URI de l'étape 1.3 ;
   - `MONO_TERMINAL_ID` : identifiant du H10 (Administration → Synchronisation sur la caisse). Pour le H10 de recette : `c4fc8f41-9b3c-46d6-afc6-eb9206699b4c` ;
   - `MONO_TOKEN_EXPIRES_AT` : fin de la recette en UTC, ex. `2026-10-20T23:59:00Z`. Après cette date, l'API refuse le jeton (401) ; la prolonger dans Render si besoin.
4. **Apply**. Le journal doit afficher `Terminal de recette provisionné` puis `Application startup complete`.
5. Vérifier `https://<service>.onrender.com/health/ready` → `{"status":"ok"}`.
6. Onglet **Environment** : copier la valeur générée de `MONO_SYNC_TOKEN`, à saisir une seule fois sur le H10.

Au démarrage, le conteneur exécute `alembic upgrade head`, puis `python -m mono.provision` (sans effet si le terminal existe ; **refus de démarrer** si un autre terminal est déjà enregistré), puis l'API.

## 3. Caisse H10

1. Se connecter en administrateur → **Administration → Synchronisation**.
2. Origine : `https://<service>.onrender.com` (sans chemin). Jeton : valeur `MONO_SYNC_TOKEN`. **Configurer**.
3. Toucher l'icône de synchronisation. Si le serveur dort, la première connexion peut prendre jusqu'à 1 min. Le compteur « en attente » doit revenir à 0 et la date de dernière synchronisation s'afficher.
4. La configuration n'est conservée que pour la session : la ressaisir après un redémarrage de l'application.

Contrôle : dans Supabase, **Table Editor** → `events`, `sales`, `variants` reflètent les opérations du H10.

## Limites et précautions

- Mode recette : jeton partagé et temporaire, pas d'authentification de production ni de renouvellement ; à ne pas utiliser pour l'exploitation.
- Le serveur ne remplace jamais le stock local ; il refuse une opération hors ordre ou incohérente (la caisse affiche le code et s'arrête à cette opération).
- Projet Supabase en pause après 7 jours sans activité : le réactiver depuis le tableau de bord avant de synchroniser.
- Changer de terminal ou réinstaller le H10 (nouvel identifiant) exige une réconciliation : ne pas modifier `MONO_TERMINAL_ID` sur une base qui contient déjà des opérations.
- Fin de recette : supprimer le service Render et le projet Supabase, ou au minimum révoquer le jeton (changer `MONO_SYNC_TOKEN`).
