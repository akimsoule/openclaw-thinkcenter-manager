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
- `CONTROL_UI_SERVER_IP=192.168.0.63` (IP du ThinkCentre pour l'acces distant)

## 3) Deploy

```bash
./scripts/manage-image.sh first-start
```

`first-start` fait: `prepare` + `pull` + `up` + `bootstrap` + `restart` + `health` + `dashboard`.

`bootstrap` applique aussi automatiquement `gateway.controlUi.allowedOrigins` si
`CONTROL_UI_SERVER_IP` ou `CONTROL_UI_ALLOWED_ORIGINS_JSON` est defini.

Si `CONTROL_UI_DISABLE_DEVICE_IDENTITY=true`, `bootstrap` applique aussi:
`gateway.controlUi.dangerouslyDisableDeviceAuth=true`.

`bootstrap` applique aussi automatiquement:

- le modele principal `ollama/<OLLAMA_PRIMARY_MODEL>`
- la policy Telegram (`TELEGRAM_DM_POLICY`, `TELEGRAM_GROUP_POLICY`, `TELEGRAM_GROUP_ALLOW_FROM`)

Commande manuelle si besoin:

```bash
./scripts/manage-image.sh allow-origin 192.168.0.63
```

Desactivation manuelle de l'identite appareil (DANGEROUS):

```bash
./scripts/manage-image.sh disable-device-identity
```

Reparation rapide complete (sans reset d'etat):

```bash
./scripts/manage-image.sh repair
```

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
