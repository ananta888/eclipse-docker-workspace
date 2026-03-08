# Architektur

## Zielbild

Das Repository trennt die Entwicklungsumgebung in drei Bereiche:

1. `shared/` als deklarative Source of Truth
2. klassische Eclipse-Laufzeit (`portable/` + `docker/`)
3. optionale Eclipse-Che-Variante (`che-local/`)

## Source-of-Truth-Prinzip

Die gemeinsame Konfiguration liegt in `shared/`:

- `p2/plugins.txt` für deklarative Plugin-Definitionen
- `prefs/eclipse.epf` für übertragbare Preferences
- `launch/*.launch` für wiederverwendbare Startkonfigurationen
- `oomph/*.setup` für initiale IDE- und Workspace-Setup-Aufgaben
- `scripts/` für reproduzierbare Automatisierung

Die klassische Desktop-Eclipse lokal und im Container konsumiert dieselben Dateien.

## Was bewusst shared ist

- Plugin-Definitionen über p2 director
- IDE-Preferences als EPF
- Launch-Konfigurationen
- Oomph-Setup-Dateien
- Skripte für Sync, Packaging, Import und Export

## Was bewusst nicht shared ist

- Laufende Workspace-`.metadata` als Hauptquelle
- UI-Laufzeitzustände wie offene Tabs oder Fensterpositionen
- Rechnerabhängige absolute Pfade

## Klassische Eclipse Runtime

### Lokal portable

`portable/` stellt die Zielstruktur bereit. Mit `shared/scripts/package-portable-eclipse.sh` kann diese Struktur reproduzierbar paketiert werden.

### Docker

`docker/eclipse` liefert eine Ubuntu-basierte Eclipse-Desktop-Umgebung mit Xvfb, XFCE, x11vnc und noVNC. Zugriff erfolgt lokal per Browser über Port `6080`.

`docker-compose.yml` bindet Workspace, Home-Konfiguration, Shared-Dateien und Backups als Volumes ein.

## Eclipse Che (optional)

`che-local/` kapselt eine lokale Minikube-basierte Che-Installation inklusive Devfile und CheCluster-Manifest. Die Che-Variante ergänzt Teamszenarien im Browser, ersetzt aber nicht die klassische Eclipse-Nutzung.

## Grenzen der Portabilität

- Unterschiedliche Host-Betriebssysteme können Theme- und Font-Unterschiede erzeugen.
- Manche Marketplace-Plugins können zusätzliche Laufzeitabhängigkeiten haben.
- Vollständige Session-Reproduktion (Fensterzustand) ist nicht Ziel.

## Empfehlungen für Java-Microservice-Teams

- Gemeinsame Plugins nur deklarativ über `shared/p2/plugins.txt` pflegen.
- Teamweite IDE-Regeln über `shared/prefs/eclipse.epf` versionieren.
- Service-Starts als `.launch` definieren und teilen.
- Workspace-spezifische Artefakte in `.gitignore` halten.
- Che nur dann aktivieren, wenn browserbasierte Kollaboration benötigt wird.
