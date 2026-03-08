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

Falls ein Verzeichnislisting erscheint, direkt noVNC öffnen:

```text
http://localhost:6080/vnc.html?autoconnect=1&resize=remote
```

## Typische Workflows

### Windows 11: Portable Eclipse bootstrap (vorkonfiguriert)

PowerShell (empfohlen):

```powershell
shared\scripts\bootstrap-portable-eclipse-win11.ps1
```

oder CMD-Wrapper:

```bat
shared\scripts\bootstrap-portable-eclipse-win11.bat
```

Das Skript:

- lädt das Eclipse Java Package fuer Windows (Version/Build aus `docker/eclipse/Dockerfile`)
- entpackt nach `portable/eclipse-win`
- installiert deklarative Plugins aus `shared/p2/plugins.txt`
- importiert Preferences aus `shared/prefs/eclipse.epf`
- kopiert `.launch`-Dateien nach `portable/workspace/.launches`

Starten:

```bat
portable\start-eclipse-win11.bat
```

### Windows 11: Docker-Eclipse mit X11 Forwarding (direkte GUI)

1. X-Server auf Windows starten (PowerShell als Administrator):

```powershell
taskkill /IM vcxsrv.exe /F
& "C:\Program Files\VcXsrv\vcxsrv.exe" :0 -multiwindow -clipboard -ac -listen tcp
```

Prüfen:

```powershell
Get-CimInstance Win32_Process -Filter "Name='vcxsrv.exe'" | Select-Object CommandLine
Get-NetTCPConnection -State Listen -LocalPort 6000
```
2. Windows-Firewall für X11-Port freigeben (PowerShell als Administrator):

```powershell
New-NetFirewallRule -DisplayName "Allow VcXsrv 6000 from WSL" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 6000 -Profile Any
New-NetFirewallRule -DisplayName "Allow vcxsrv.exe" -Direction Inbound -Action Allow -Program "C:\Program Files\VcXsrv\vcxsrv.exe" -Profile Any
```
3. In `.env` setzen:

```dotenv
USE_HOST_X11=1
HOST_DISPLAY=host.docker.internal:0.0
```

Falls Docker direkt in WSL2 laeuft (ohne Docker Desktop), kann `host.docker.internal` auf eine falsche Adresse zeigen.
Dann `HOST_DISPLAY` auf die echte Windows-IP setzen (z. B. `192.168.178.100:0.0`):

```dotenv
USE_HOST_X11=1
HOST_DISPLAY=192.168.178.100:0.0
```

4. Container neu bauen/starten:

```bash
docker compose up -d --build
```

Dann öffnet sich Eclipse direkt im Windows-X-Server.  
Hinweis: In `USE_HOST_X11=1` ist noVNC absichtlich deaktiviert. X11-Forwarding und noVNC parallel sind im aktuellen Setup nicht gleichzeitig aktiv.

### Remote Pair-Development mit Saros (Eclipse-Container)

Saros ist als Eclipse-Plugin deklarativ eingebunden (`shared/p2/plugins.txt`) und wird beim Image-Build installiert.

1. Image neu bauen und Container starten:

```bash
docker compose up -d --build
```

2. In Eclipse prüfen: `Window -> Show View -> Other... -> Saros`.
3. Saros-Account anlegen oder anmelden.
4. Session starten: `Saros -> Start Session`.
5. Projekt/Freigaben auswaehlen und Partner einladen.

Hinweis: Alle Teilnehmer brauchen Saros in ihrer Eclipse-Installation.

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
