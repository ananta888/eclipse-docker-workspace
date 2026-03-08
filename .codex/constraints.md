# Constraints

## Plattform

- Hauptzielplattform: Windows 11
- Entwicklungsumgebung basiert auf WSL2
- Linux Distribution in WSL2: Ubuntu oder kompatibel
- Architektur: x86_64

## Docker

- Docker darf **nicht über Docker Desktop** laufen
- Docker Engine wird **direkt innerhalb der WSL2 Linux Distribution installiert**
- Docker läuft vollständig in der Linux Umgebung der WSL2 Distribution
- Alle Container werden ausschließlich über diese Docker Engine gestartet

Typische Installation innerhalb WSL2:

- docker-ce
- docker-ce-cli
- containerd
- docker compose plugin

Docker CLI wird direkt aus der WSL2 Shell verwendet.

## Docker Compose

- Verwendung von `docker compose` (Compose v2 Plugin)
- keine Abhängigkeit von Docker Desktop Features
- keine Nutzung proprietärer Docker Desktop Integrationen

## Dateisystem

Repository kann liegen:

- im WSL2 Linux Dateisystem (empfohlen)
- im Windows Dateisystem unter `/mnt/c/...`

Skripte müssen robust sein für beide Varianten.

Keine fest kodierten absoluten Pfade.

Workspace Pfade müssen konfigurierbar sein.

## Skripte

Shell-Skripte müssen:

- unter WSL2 Bash funktionieren
- POSIX kompatibel sein
- `set -euo pipefail` verwenden
- ohne interaktive Eingaben funktionieren

Optional dürfen Wrapper bereitgestellt werden:

- `.ps1`
- `.bat`

Diese Wrapper rufen intern die WSL2 Skripte auf.

## Eclipse

Unterstützte Varianten:

1. Portable Eclipse lokal auf Windows
2. Eclipse Desktop im Docker Container
3. Eclipse Che als optionale browserbasierte Umgebung

Alle Varianten müssen möglichst dieselben Konfigurationsquellen verwenden.

## Gemeinsame Konfiguration

Gemeinsame Konfiguration liegt unter:
shared/

Dort befinden sich:

- p2 Plugin Definition
- Eclipse Preferences
- Launch Konfigurationen
- Oomph Setup
- gemeinsame Skripte

## Plugin Installation

Plugins müssen deklarativ installiert werden über:

- p2 director
- plugins.txt Definition

Manuelle Installation über GUI ist nicht erforderlich.

## Workspace

Workspace ist **nicht** die Quelle der Wahrheit.

Portable Konfiguration:

- Plugin Definition
- Preferences
- Launch Dateien
- Setup Dateien
- Skripte

Nicht portable:

- `.metadata`
- UI Layout
- offene Editor Tabs

## Netzwerk

Container sind lokal erreichbar.

Keine Annahme über:

- öffentliche Ports
- Reverse Proxy
- DNS Infrastruktur

## Eclipse Che

Che ist optional.

Ziel:

- lokale Installation
- Minikube Cluster innerhalb WSL2
- Devfile basierte Workspaces

Che ersetzt nicht die klassische Eclipse Umgebung.

## Ziel der Architektur

Die Entwicklungsumgebung muss:

- reproduzierbar sein
- deklarativ konfiguriert sein
- zwischen Rechnern portierbar sein
- lokal oder containerisiert nutzbar sein
- für Java Microservice Entwicklung geeignet sein

## Nicht-Ziele

Dieses Repository soll nicht:

- CI/CD Pipelines definieren
- Produktionsdeployment bereitstellen
- Kubernetes Produktionscluster konfigurieren
