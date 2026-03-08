# Eclipse Che lokal (optional)

Dieser Bereich ist optional und ergänzt die klassische Eclipse-Desktop-Nutzung um eine browserbasierte Team-Variante.

## Voraussetzungen

- Minikube in WSL2
- Docker Engine innerhalb WSL2
- kubectl

## Schnellstart

```bash
cd che-local
./scripts/install-deps.sh
./scripts/install-chectl.sh
./scripts/start-minikube.sh
./scripts/deploy-che.sh
./scripts/status-che.sh
./scripts/open-che.sh
```

## Entfernen

```bash
./scripts/delete-che.sh
```
