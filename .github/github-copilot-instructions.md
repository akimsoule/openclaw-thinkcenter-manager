# Gestion de l'image OpenClaw ThinkCentre

Ce dépôt contient les scripts et la configuration nécessaire pour déployer et exécuter **OpenClaw** dans un conteneur Docker sur une machine ThinkCentre.

## 1) Objectif

- Fournir une configuration versionnée pour OpenClaw.
- Garder les secrets hors du dépôt (`.env` non commité).
- Démarrer OpenClaw rapidement via `docker compose` + scripts.

## 2) Structure principale

- `docker-compose.yml` : lance le service OpenClaw et son CLI.
- `scripts/manage-image.sh` : script d’aide pour démarrer, configurer et réparer.
- `.env.example` : exemple de configuration des variables d’environnement.

## 3) Démarrage rapide

1. Copier l’exemple d’environnement :

```bash
cp .env.example .env
```

2. Remplir les clés dans `.env` (notamment : `MOONSHOT_API_KEY`, `TELEGRAM_BOT_TOKEN`, et `CONTROL_UI_ALLOWED_ORIGINS_JSON` si besoin).

3. Lancer OpenClaw (premier démarrage) :

```bash
./scripts/manage-image.sh first-start
```

4. Pour relancer le service :

```bash
./scripts/manage-image.sh up
```

## 4) Commandes utiles

- `./scripts/manage-image.sh bootstrap` : génère/écrit la config dans le conteneur (gateway.mode, modèle, etc.)
- `./scripts/manage-image.sh repair` : répare la configuration et redémarre le gateway.
- `./scripts/manage-image.sh down` : stoppe et supprime le conteneur.
- `./scripts/manage-image.sh logs` : affiche les logs du gateway.

## 5) Contrôle UI (interface web)

La Control UI s’ouvre normalement sur :

- `http://localhost:18789`

Si le navigateur refuse l’accès pour origine non autorisée, adapter la liste dans `.env` (ligne `CONTROL_UI_ALLOWED_ORIGINS_JSON`).

## 6) Config spécifiques

### Autoriser l’accès Control UI

Dans `.env` :

```env
CONTROL_UI_ALLOWED_ORIGINS_JSON='["http://localhost:18789","http://127.0.0.1:18789","http://192.168.0.63:18789"]'
```

### Paramètres modèle

- `PRIMARY_MODEL` (par défaut: `moonshot/kimi-k2.5`)
- `MOONSHOT_API_KEY` (obligatoire si `PRIMARY_MODEL` est `moonshot/*`)

## 7) Points d’attention

- **Ne pas committer `.env`** (ce fichier contient les clés privées).
- Si le conteneur refuse d’écrire `openclaw.json`, vérifier les permissions du volume Docker.
- Si OpenClaw se bloque à cause de `models.providers.moonshot.models`, c’est généralement un problème de config générée incorrectement (le script `manage-image.sh` contient une logique de correction).

---

_Ce fichier sert de documentation interne pour l’utilisation du dépôt et peut être adapté selon le besoin._
