# Reproduzierbare Eclipse-Entwicklungsumgebung

## Ziel

Dieses Repository stellt eine einheitliche, deklarative Eclipse-Konfigurationsbasis bereit, die in drei Varianten genutzt werden kann:

1. lokale portable Eclipse
2. klassische Eclipse im Docker-Container mit Browserzugriff
3. optionale Eclipse-Che-Umgebung für browserbasiertes Team-Setup

## Gesamtidee

`shared/` ist die zentrale Quelle für Plugins, Preferences, Launch-Dateien und Setup-Definitionen. Sowohl portable Eclipse als auch Container-Eclipse verwenden diese gemeinsame Basis.

## Varianten im Vergleich

### Lokale portable Eclipse

- ideal für lokale Entwicklung mit nativer Performance
- nutzt dieselben `shared/`-Definitionen
- kann als Archiv paketiert und verteilt werden

### Eclipse im Docker-Container

- vollständige Desktop-Eclipse im Container
- Zugriff über noVNC im Browser (`http://localhost:6080`)
- gleiche Shared-Konfiguration via Volumes

### Eclipse Che (optional)

- browserbasierte Workspaces auf Minikube
- geeignet für Team-/Remote-Szenarien
- klar von der klassischen Eclipse-Lösung getrennt

## Projektstruktur

```text
.
├─ shared/
├─ docker/eclipse/
├─ portable/
├─ eclipse-data/home/
├─ backup/
├─ che-local/
└─ docs/
```

## Schnellstart (klassische Docker-Eclipse)

```bash
cp .env.example .env
docker compose build
docker compose up -d
```

Danach im Browser öffnen:

```text
http://localhost:6080
```

## Typische Workflows

### Plugins deklarativ installieren

```bash
shared/scripts/install-plugins.sh
```

Optional mit eigener Eclipse-Installation:

```bash
ECLIPSE_HOME=/pfad/zu/eclipse shared/scripts/install-plugins.sh
```

### Preferences importieren

```bash
shared/scripts/import-prefs.sh
```

### Preferences exportieren

```bash
shared/scripts/export-prefs.sh
```

### Shared-Dateien synchronisieren

```bash
shared/scripts/sync-shared.sh
```

### Portable Eclipse paketieren

```bash
shared/scripts/package-portable-eclipse.sh
```

## Backup und Restore

Im Container:

```bash
docker exec -it eclipse-classic backup-config.sh
docker exec -it eclipse-classic restore-config.sh /backup/eclipse-home-YYYYMMDD-HHMMSS.tar.gz
```

## Plugin-Management

Die Plugin-Liste liegt in `shared/p2/plugins.txt` im Format `Repository|InstallableUnit`.

## Preference-Management

Die teamweit relevanten Preferences liegen in `shared/prefs/eclipse.epf`.

## Wann welche Variante?

- **Portable lokal:** wenn lokale GUI und Offline-Nutzung im Vordergrund stehen
- **Docker-Eclipse:** wenn reproduzierbare Laufzeit und isolierte Umgebung wichtig sind
- **Eclipse Che:** wenn browserbasierte Team-Workspaces benötigt werden

## Optionale Eclipse-Che-Nutzung

```bash
cd che-local
./scripts/install-deps.sh
./scripts/install-chectl.sh
./scripts/start-minikube.sh
./scripts/deploy-che.sh
./scripts/status-che.sh
./scripts/open-che.sh
```
