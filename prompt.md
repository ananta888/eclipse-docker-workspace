Du arbeitest in einem Repository für eine reproduzierbare Eclipse-Entwicklungsumgebung. Ziel ist eine einheitliche Lösung, bei der dieselbe Eclipse-Konfiguration und dieselben Plugins sowohl für eine lokale portable Eclipse-Installation als auch für eine Eclipse-Instanz im Docker-Container verwendet werden.

Arbeite direkt an Dateien im Repository. Erzeuge eine saubere, produktionsnahe, nachvollziehbare Struktur. Triff sinnvolle technische Entscheidungen selbstständig, wenn etwas nicht vollständig vorgegeben ist. Vermeide unnötige Rückfragen. Vermeide lange Vorreden. Liefere funktionierende Dateien.

ZIELE

1. Es soll eine gemeinsame deklarative Konfigurationsbasis geben.
2. Dieselben Plugins, Preferences, Launch-Konfigurationen und Setup-Dateien sollen für beide Betriebsarten gelten:
   - lokale portable Eclipse
   - Eclipse im Docker-Container
3. Docker soll nicht nur die Container-Variante bereitstellen, sondern optional auch die portable lokale Eclipse reproduzierbar provisionieren oder vorbereiten können.
4. Eclipse Che soll zusätzlich als optionale browserbasierte Team-/Remote-Variante im Repository enthalten sein, aber klar getrennt von der klassischen Desktop-Eclipse-Lösung.
5. Die Struktur soll für Java-Microservice-Projekte geeignet sein.
6. Alles soll möglichst portabel, versionierbar und teamfähig sein.
7. Keine implizite Abhängigkeit auf manuelle Klick-Konfigurationen.

ARCHITEKTURVORGABEN

Die Lösung soll aus 3 klar getrennten Bereichen bestehen:

A) shared Eclipse definition
Gemeinsame Quelle für:
- Plugin-Definitionen
- Preferences
- Launch-Dateien
- Oomph-Setup
- gemeinsame Skripte

B) classic Eclipse runtime
Zwei Nutzungsarten, aber gleiche Konfigurationsbasis:
- lokale portable Eclipse
- Eclipse im Docker-Container mit grafischem Zugriff per Browser/noVNC

C) Eclipse Che
Optionale separate browserbasierte Workspace-Lösung für Remote/Teambetrieb mit Devfile und lokaler Minikube-Variante

ERWARTETE ZIELSTRUKTUR

Lege eine sinnvolle, saubere Struktur an, die ungefähr so aussieht und bei Bedarf verbessert werden darf:

.
├─ README.md
├─ docker-compose.yml
├─ .env.example
├─ shared/
│  ├─ p2/
│  │  └─ plugins.txt
│  ├─ prefs/
│  │  └─ eclipse.epf
│  ├─ launch/
│  │  └─ app-local.launch
│  ├─ oomph/
│  │  └─ portable-eclipse.setup
│  └─ scripts/
│     ├─ install-plugins.sh
│     ├─ import-prefs.sh
│     ├─ export-prefs.sh
│     ├─ sync-shared.sh
│     └─ package-portable-eclipse.sh
├─ docker/
│  └─ eclipse/
│     ├─ Dockerfile
│     └─ scripts/
│        ├─ entrypoint.sh
│        ├─ backup-config.sh
│        └─ restore-config.sh
├─ portable/
│  ├─ eclipse/
│  ├─ workspace/
│  └─ config/
├─ eclipse-data/
│  └─ home/
├─ backup/
├─ che-local/
│  ├─ .env
│  ├─ README.md
│  ├─ devfile.yaml
│  ├─ checluster.yaml
│  └─ scripts/
│     ├─ install-deps.sh
│     ├─ install-chectl.sh
│     ├─ start-minikube.sh
│     ├─ deploy-che.sh
│     ├─ status-che.sh
│     ├─ open-che.sh
│     └─ delete-che.sh
└─ docs/
   └─ architecture.md

FUNKTIONALE ANFORDERUNGEN

1. Shared-Konfiguration
Erzeuge eine zentrale gemeinsame Konfigurationsbasis:
- plugins.txt im Format Repository|InstallableUnit
- eclipse.epf für exportierbare Preferences
- mindestens eine geteilte .launch-Datei
- Oomph-Setup-Datei für Workspace-/IDE-Initialisierung
- gemeinsame Shell-Skripte, die lokal und im Container nutzbar sind, soweit sinnvoll

2. Docker-Eclipse
Erzeuge eine klassische Eclipse-Desktop-Variante im Container:
- Ubuntu-basierte Lösung
- Java Runtime
- Eclipse Java Package
- Xvfb
- XFCE
- x11vnc
- noVNC
- Browserzugriff auf Port 6080
- Workspace, Home-Konfiguration, Shared-Ordner und Backups per Volume
- beim Start sollen shared launch-Dateien bereitgestellt werden
- sinnvolle ENV-Variablen
- brauchbare Default-Größe für Shared Memory
- keine unnötigen Kommentare in Scripts oder YAML

3. Lokale portable Eclipse
Bereite die Struktur so vor, dass eine portable lokale Eclipse dieselbe shared-Konfiguration verwenden kann:
- shared/scripts/install-plugins.sh soll auch für eine lokale Eclipse-Installation benutzbar sein
- shared/scripts/import-prefs.sh und export-prefs.sh sollen für lokale Ausführung geeignet sein
- package-portable-eclipse.sh soll eine portable Eclipse-Struktur vorbereiten oder paketieren
- keine Abhängigkeit auf hartcodierte absolute Pfade
- sinnvolle Parameter per Umgebungsvariablen oder Skriptargumenten

4. Eclipse Che
Zusätzlich soll eine optionale Eclipse-Che-Lösung enthalten sein:
- lokale Minikube-Variante
- .env
- Devfile
- CheCluster YAML
- Start-/Deploy-/Status-/Open-/Delete-Skripte
- README im che-local Ordner
- klar als optional kennzeichnen
- nicht mit der klassischen Eclipse-Lösung vermischen

5. Dokumentation
Erzeuge eine gute README.md auf Repo-Ebene mit:
- Ziel
- Zweck
- Gesamtidee
- Unterschied zwischen lokaler Eclipse, Container-Eclipse und Eclipse Che
- grobe Funktionsweise
- Startanleitung
- typische Workflows
- Backup/Restore
- Plugin-Installation
- Preference-Import/Export
- wann welche Variante sinnvoll ist

Zusätzlich docs/architecture.md:
- architektonische Beschreibung
- Source of truth Prinzip
- was shared ist und was bewusst nicht shared ist
- Grenzen der Portabilität
- Empfehlungen für Java-Microservice-Teams

NICHT-SHARED / WICHTIGE GRENZEN

Behandle folgende Punkte bewusst:
- Der komplette laufende .metadata-Ordner soll nicht als alleinige Quelle der Wahrheit betrachtet werden.
- Absolute Pfade sollen vermieden werden.
- UI-Zustände wie offene Tabs sind nicht primäres Portierungsziel.
- Shared werden sollen primär:
  - Plugin-Definitionen
  - Preferences
  - Launches
  - Oomph-Setup
  - reproduzierbare Skripte

QUALITÄTSANFORDERUNGEN

- Schreibe robuste Shell-Skripte mit `set -euo pipefail`
- Verwende nachvollziehbare Dateinamen
- Halte Dateien sauber formatiert
- Keine Platzhaltertexte wie TODO, FIXME, coming soon
- Keine Erklärkommentare im Code, außer absolut nötig
- README und docs dürfen natürlich erklärend sein
- Docker, Shell, YAML und XML sollen syntaktisch korrekt sein
- Wenn du Annahmen treffen musst, triff sinnvolle Standardannahmen
- Halte die Struktur realistisch für ein echtes Teamprojekt

BEVORZUGTE TECHNISCHE DETAILS

- Linux x86_64 als Standardannahme
- Zeitzone Europe/Berlin
- Eclipse Java Package
- Plugin-Installation per p2 director
- Launch-Dateien als shared files
- Devfile für Java 21 Workspace
- Containerzugriff standardmäßig lokal gedacht, nicht offen ins Internet
- Docker Compose für die klassische Eclipse-Container-Variante
- Minikube + chectl für Che lokal

ARBEITSWEISE

1. Analysiere die Zielstruktur.
2. Erzeuge oder überarbeite alle relevanten Dateien.
3. Stelle sicher, dass die Dateien zusammenpassen.
4. Gib am Ende eine knappe Übersicht:
   - welche Dateien erstellt oder geändert wurden
   - welche Startbefehle relevant sind
   - welche Annahmen du getroffen hast

AUSGABEERWARTUNG

Arbeite direkt im Repository.
Erzeuge alle Dateien mit vollständigem Inhalt.
Bevorzuge funktionierende, vollständige Artefakte gegenüber Diskussion.
Keine langen Vorab-Erklärungen.
