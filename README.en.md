# Quake Live Dedicated Server + minqlx — automated installer

[🇵🇱 Polska wersja](README.md)

The `install_minqlx_server.sh` script sets up a Quake Live Dedicated Server
(QLDS) from scratch with minqlx and a full plugin pack (MinoMino +
BarelyMiSSeD + tjone270 + several external ones) on a clean Debian/Ubuntu
(x86_64) system.

You control the servers with the **`qlds-ctl`** tool (installed into
`~/qlds/`): each instance runs in its own named `screen` session (`qlds-tdm`,
`qlds-ffa`, ...) with a supervising loop that **relaunches the server after
every crash**. You alone decide when a server is up or down — `qlds-ctl stop`
shuts it down **permanently** (it won't come back after a crash or a reboot),
and after a host reboot only the servers you did NOT stop are started
automatically (cron `@reboot`). The installer does **not** create systemd
services for the QL servers.

```bash
~/qlds/qlds-ctl start all      # start all enabled servers
~/qlds/qlds-ctl stop ffa       # shut down permanently
~/qlds/qlds-ctl status         # what's enabled / what's actually running
~/qlds/qlds-ctl console tdm    # server console (detach: Ctrl+A, D)
```

## Requirements

- Debian 10/11/12 or Ubuntu 20.04/22.04/24.04 (apt-based)
- **x86_64** architecture
- User with `sudo` rights (NOT root)

## Quick install (one-liner from GitHub)

```bash
QLX_OWNER=76561198799965164 \
RCON_PASSWORD=myRconPassword \
STATS_PASSWORD=myStatsPassword \
bash <(curl -fsSL https://raw.githubusercontent.com/goof3r/quakelive-server/master/install_minqlx_server.sh)
```

`bash <(curl ...)` keeps stdin attached to the terminal — the interactive
prompt *"Add another server now?"* will work. The `curl | bash` alternative
also works but simply skips that prompt.

## Install from a repo clone (recommended)

```bash
git clone https://github.com/goof3r/quakelive-server.git
cd quakelive-server
QLX_OWNER=76561198799965164 ./install_minqlx_server.sh
```

In this mode the installer automatically uses local files from the repo:

| Directory / file | What it does during install |
|---|---|
| `configs and mappool/ffa.cfg` `tdm.cfg` `ft.cfg` | Copied directly to `$QLDS_DIR/baseq3/` instead of generating from a template |
| `configs and mappool/mappool_*.txt` `access.txt` | Copied to `$QLDS_DIR/baseq3/` |
| `configs and mappool/workshop.txt` | Copied to `$QLDS_DIR/workshop.txt` (with comments and grouping) |
| `minqlx-plugins/*.py` | Copied as the **last step** — overwrites versions from MinoMino/BarelyMiSSeD/tjone270 |
| `minqlx-plugins/Map_Names/` `extras/` `mbot_maps.json` | Copied together with the plugins |
| `commands.py` `serverhelp.py` `permoverride.py` | Copied from the directory next to the script instead of pulling from GitHub |
| `qlds-ctl` | Copied to `$QLDS_DIR/qlds-ctl` — the start/stop/restart/status/console tool |

## Configuration via environment variables

| Variable | Default | What it does |
|---|---|---|
| `QLX_OWNER` | `76561198799965164` | **YOUR SteamID64 (17 digits)** |
| `SV_HOSTNAME` | `^2My minqlx Server` | server name in the list |
| `NET_PORT` | `27960` | UDP port of the base server |
| `RCON_PASSWORD` | `zmien_to_haslo_rcon` | rcon password (CHANGE IT) |
| `STATS_PASSWORD` | `zmien_to_haslo_stats` | zmq stats password (CHANGE IT) |
| `INSTALL_GAMETYPE_SERVERS` | `1` | `0` = don't install the FFA/TDM/FT servers |
| `QLDS_DIR` | `$HOME/qlds` | where the server will be installed |

You can find your SteamID64 at <https://steamid.io>.

## Controlling the servers — qlds-ctl

The installer creates the three gametype start scripts plus the
`~/qlds/qlds-ctl` tool:

| Instance | UDP port | Start script | Screen session |
|---|---|---|---|
| tdm | 27960 | `~/qlds/start-tdm.sh` | `qlds-tdm` |
| ffa | 27961 | `~/qlds/start-ffa.sh` | `qlds-ffa` |
| ft  | 27962 | `~/qlds/start-ft.sh`  | `qlds-ft`  |
| base | 27960 | `~/qlds/start.sh` | `qlds-base` (**disabled** by default — shares the port with tdm) |

```bash
~/qlds/qlds-ctl start tdm      # start a server (clears the stop flag)
~/qlds/qlds-ctl start all      # start all ENABLED servers (skips stopped ones)
~/qlds/qlds-ctl stop ffa       # shut down PERMANENTLY — won't return after a crash or reboot
~/qlds/qlds-ctl restart ft     # quick restart (enabled/disabled flag untouched)
~/qlds/qlds-ctl status         # table: what's enabled / what's actually running
~/qlds/qlds-ctl console tdm    # interactive minqlx console (detach: Ctrl+A, D)
```

How it works:

- Each server runs in a named `screen` session (`screen -ls` shows them too)
  with a **supervising loop** that relaunches it after **every** process exit —
  a crash, `quit` typed in the console, etc. Restarts are 3 s apart; if the
  server dies right after startup 5 times in a row, the delay grows to 60 s.
- The **only** way to shut a server down for good is `qlds-ctl stop` — it
  creates the `~/qlds/state/<name>.stopped` flag and kills the process. The
  server stays down until you run `qlds-ctl start`.
- **After a host reboot** the `@reboot` crontab entry (added by the installer)
  runs `qlds-ctl boot`: only instances without the `.stopped` flag come up —
  each in its own screen session, no action needed from you.
- Loop events (starts, crashes, restarts) go to `~/qlds/state/<name>.log`
  and to the session console (scrollback in `qlds-ctl console`).

## Migrating an older install (servers "come back on their own")

Hosts set up with an earlier version of the installer have systemd services
`qlserver.service` / `qlserver-tdm/ffa/ft/...` with `Restart=on-failure` —
they are what resurrects the servers after you stop them manually. **Just
re-run the installer** — it detects, stops and removes them (then run
`qlds-ctl start all`). Manually:

```bash
sudo systemctl disable --now 'qlserver*.service'
sudo rm -f /etc/systemd/system/qlserver*.service
sudo systemctl daemon-reload
screen -ls   # also kill any old manually started start-* sessions
```

Note: the `restartserver.py` plugin (not in the default plugin list; it issues
`quit` and requires an external supervisor) now works as intended under
qlds-ctl — the loop relaunches the server after its scheduled `quit`.

## Gametype definitions (gametypes-factories)

The `gametypes-factories` file contains 10 gametype definitions used by the
server:

| ID | Title | Base gametype |
|---|---|---|
| `mg_ft_fullclassic` | Full Classic Freeze Tag | FT |
| `mg_ft_allweapons` | All Weapons Freeze Tag | FT |
| `mg_ft_promode` | Q3 Freeze Tag | FT |
| `mg_ft_uft` | Ultra Freeze Tag | FT |
| `mg_tdm_utdm` | Ultra TDM | TDM |
| `maido` | Maido | TDM |
| `sparing` | Sparing (RG & LG) | TDM |
| `mg_race_classic` | Classic Race | Race |
| `mg_ffa_aw` | All Weapons FFA | FFA |
| `mg_tdm_fullclassic` | Full Classic TDM | TDM |

The file is installed to `$QLDS_DIR/baseq3/scripts/gametypes.factories`.

## Adding more servers

```bash
~/qlds/add_server.sh              # interactively asks for name and port
~/qlds/add_server.sh duel 27970   # inline arguments
```

Creates `baseq3/<name>.cfg`, `start-<name>.sh` and the `instances/<name>/`
directory. The new instance is immediately visible to `qlds-ctl` (discovered
by the start-script name):

```bash
~/qlds/qlds-ctl start duel
~/qlds/qlds-ctl status
```

Open the UDP port (and TCP `port+1000` for rcon) in your firewall.

## What the script installs

1. apt: python3-dev, redis-server, build-essential, lib32gcc, screen
   (used by qlds-ctl), ...
2. SteamCMD + QLDS (app 349090, login anonymous)
3. Compiling minqlx from source (MinoMino/minqlx)
4. Plugins (in order — the last one wins):
   - **MinoMino/minqlx-plugins** (official)
   - **BarelyMiSSeD/minqlx-plugins** (specqueue, serverBDM, kills, ...)
   - **tjone270/Quake-Live/minqlx-plugins** (q3resolver, branding, ...)
   - Single files: queue, autospec, iouonegirl, checkplayers
   - **Local `minqlx-plugins/`** from this repo (overrides everything above — newer versions)
   - Patched `commands.py`, `serverhelp.py`, `permoverride.py`
5. `commlink.py` (IRC bridge) and `changemap.py` (auto map reset) are removed.
6. `server.cfg`, `start.sh`, `workshop.txt`
7. Gametype configs from `configs and mappool/` (ffa/tdm/ft.cfg + mappools)
8. `gametypes.factories` (10 gametype definitions)
9. Start scripts `start-tdm.sh` / `start-ffa.sh` / `start-ft.sh`
10. **`qlds-ctl`** + the `state/` directory (the `base` instance disabled by
    default) + an `@reboot` crontab entry (auto-start of enabled servers);
    also removes legacy `qlserver*.service` units from older installer versions
11. `add_server.sh` for future instances

## Updating

Just run the installer again — it will update QLDS, minqlx and all plugins.
Your `server.cfg` is left intact (only the `qlx_plugins` line is synced, and
a backup is saved as `.bak.<timestamp>`).

## Commands added by this installer

### `serverhelp` plugin

| Command | What it does |
|---|---|
| `!help` | Lists all available commands with permission level and owning plugin |
| `!version` | Prints minqlx version + plugin pack version |
| `!perms` | Lists permission levels 0–5 and highlights your current level |

### `permoverride` plugin

Lets you change the permission level of any command without patching its
plugin. Configuration in `server.cfg`:

```
set qlx_permFor_kick    "1"   // !kick defaults to perm 2, lowered here to 1
set qlx_permFor_map     "3"   // !map only for head-admins
```

| Command | What it does |
|---|---|
| `!permset <command> <0-5>` | Change level on the fly (perm 5) |
| `!permshow <command>` | Current level and owning plugin (perm 0) |
| `!permlist` | Lists active overrides from `qlx_permFor_*` (perm 0) |
| `!permreload` | Reloads cvars from server.cfg (perm 5) |

## Post-install test

```
!myperm          // shows a level > 0 if you are the owner
!help            // lists all commands
!version         // minqlx version
!perms           // permission levels
```

## License

The installer itself and the custom plugins (`serverhelp.py`,
`permoverride.py`) — no restrictions. `commands.py` is GPL-3.0 (derivative
of BarelyMiSSeD's work).
