# Windows 11 Portable Eclipse Setup

Dieser Ordner ist als eigenstaendiges Windows-11-Setup-Paket aufgebaut und enthaelt alles Relevante lokal in diesem Verzeichnis:

- WSL2 pruefen und bei Bedarf installieren
- Ubuntu unter WSL pruefen und bei Bedarf installieren
- portable Eclipse fuer Windows herunterladen
- Team-Plugins installieren
- Eclipse-Preferences importieren
- Repositories unter `portable\repos` klonen/aktualisieren
- Gradle-Eclipse-Metadaten erzeugen
- Projekte automatisch in den Eclipse-Workspace importieren
- lokale Konfiguration fuer Plugins, Preferences und Launches

## Start

Empfohlen:

```bat
win11-portable-eclipse\install-win11-portable-eclipse.bat
```

Mit Repo-Parametern:

```bat
win11-portable-eclipse\install-win11-portable-eclipse.bat ^
  -MasterRepoUrl "https://github.com/org/master.git" ^
  -SubRepoUrl1 "https://github.com/org/config-1.git" ^
  -SubRepoUrl2 "https://github.com/org/config-2.git"
```

## Hinweise

- Fuer die Installation von WSL/Ubuntu sind Administratorrechte noetig.
- Falls Windows einen Neustart verlangt, beendet sich das Skript mit Hinweis.
- Die Setup-Logik liegt lokal unter `win11-portable-eclipse\scripts`.
- Die Konfiguration liegt lokal unter `win11-portable-eclipse\config`.
- Eclipse wird unter `portable\eclipse-win` installiert.
- Der Windows-Workspace liegt unter `portable\workspace-win`.
- Geklonte Repositories liegen unter `portable\repos`.

## Eclipse starten

```bat
win11-portable-eclipse\start-eclipse-win11.bat
```
