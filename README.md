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
./scripts/manage-image.sh pull
./scripts/manage-image.sh up
./scripts/manage-image.sh health
./scripts/manage-image.sh dashboard
```

## 4) Pairing recovery

```bash
./scripts/manage-image.sh pairing-recover
```

## 5) Mise a jour de version image

Dans `.env`, change:

```bash
OPENCLAW_IMAGE=akimsoule/openclaw-thinkcenter:2026.03.12
```

Puis:

```bash
./scripts/manage-image.sh pull
./scripts/manage-image.sh restart
```
