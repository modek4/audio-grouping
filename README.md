# Audio Core

AutoHotkey v2 script for controlling Windows system volume and per-application audio groups (e.g., media, games, chat).

## Features

- Adjust system volume and group volumes via hotkeys
- Assign apps to groups by process name (e.g., `discord.exe`, `chrome.exe`)
- Automatic volume restoration for new sessions
- On-screen display (OSD) for volume changes
- Saves volume levels to `config.ini`
- Detects default audio device changes

## Requirements

- Windows 7 or later
- [AutoHotkey v2](https://www.autohotkey.com/)

## Quick Start

1. Install [AutoHotkey v2](https://www.autohotkey.com/)
2. Run `volume.ahk`
3. Edit `C:\Audio\config.ini` and `C:\Audio\groups.txt`
4. Restart the script

## Configuration

### `config.ini`

```ini
[Volume]
Step=2
DebounceTime=60
OSDTime=1200

[Groups]
Order=media,games,chat
DefaultVolume=50

[Hotkeys]
MediaUp=F13
MediaDown=F14
GamesUp=F15
GamesDown=F16
ChatUp=F17
ChatDown=F18
SystemUp=F19
SystemDown=F20

[OSD]
Width=320
Height=32
YOffset=75
BarColor=ba34f3
BackgroundColor=303030
Font=Segoe UI
FontSize=11
Opacity=192
```

### `groups.txt`

```ini
[media]
spotify.exe
firefox.exe
chrome.exe

[games]
ac.exe
Cyberpunk2077.exe
cs2.exe

[chat]
teams.exe
discord.exe
teamspeak.exe
```

## Usage

- Press hotkeys to adjust volumes (F13–F20 by default)
- Apps are matched by process name in `groups.txt`
- Volume levels are saved automatically
- OSD shows current volume on primary monitor
