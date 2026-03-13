# OpenClaw ThinkCentre Image Manager

Repo dedie a l'exploitation de l'image Docker OpenClaw publiee sur Docker Hub.

## Objectif

- versionner la configuration de deploiement
- garder les variables sensibles hors git
- deployer rapidement sur ThinkCentre

## 1) Initialisation

```bash
cp .env.example .env
./scripts/manage-image.sh init
```

Ne jamais committer `.env`.

## 2) Variables importantes

- `OPENCLAW_IMAGE=akimsoule/openclaw-thinkcenter:latest` (ou tag date)
- `TELEGRAM_BOT_TOKEN` (optionnel)
- `NVIDIA_API_KEY` (optionnel)

## 3) Deploy

```bash
./scripts/manage-image.sh first-start
```

`first-start` fait: `prepare` + `pull` + `up` + `bootstrap` + `restart` + `health` + `dashboard`.

## 4) Pairing recovery

```bash
./scripts/manage-image.sh pairing-recover
```

## 5) Reset propre (si besoin)

```bash
./scripts/manage-image.sh reset-state
./scripts/manage-image.sh first-start
```

`reset-state` sauvegarde l'ancien state dans `~/.openclaw-thinkcenter.bak.<timestamp>` puis repart proprement.

## 6) Mise a jour de version image

Dans `.env`, change:

```bash
OPENCLAW_IMAGE=akimsoule/openclaw-thinkcenter:2026.03.12
```

Puis:

```bash
./scripts/manage-image.sh pull
./scripts/manage-image.sh restart
```

## 7) Diagnostic rapide

```bash
./scripts/manage-image.sh diagnose
```
