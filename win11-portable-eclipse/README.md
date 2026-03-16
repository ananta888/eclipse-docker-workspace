# Windows 11 Portable Eclipse Setup

Dieser Ordner enthaelt nur den relevanten Windows-11-Setup fuer:

- WSL2 pruefen und bei Bedarf installieren
- Ubuntu unter WSL pruefen und bei Bedarf installieren
- portable Eclipse fuer Windows herunterladen
- Team-Plugins installieren
- Eclipse-Preferences importieren
- Repositories unter `portable\repos` klonen/aktualisieren
- Gradle-Eclipse-Metadaten erzeugen
- Projekte automatisch in den Eclipse-Workspace importieren

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
- Eclipse wird unter `portable\eclipse-win` installiert.
- Der Windows-Workspace liegt unter `portable\workspace-win`.
- Geklonte Repositories liegen unter `portable\repos`.

## Eclipse starten

```bat
win11-portable-eclipse\start-eclipse-win11.bat
```
