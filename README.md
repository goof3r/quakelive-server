# Quake Live Dedicated Server + minqlx — automatyczny instalator

Skrypt `install_minqlx_server.sh` stawia od zera serwer Quake Live (QLDS) z
minqlx i kompletem pluginów (MinoMino + BarelyMiSSeD + tjone270 + kilka
zewnętrznych) na czystym Debianie/Ubuntu (x86_64).

Bazowy serwer trafia do systemd (autostart). **Dodatkowe instancje dodawane
przez `add_server.sh` świadomie NIE są rejestrowane w systemd** — uruchamiasz
je ręcznie. Tak chciał właściciel; uzasadnienie: pełna kontrola nad tym, co i
kiedy startuje (np. testowe serwery, eventy, prywatne configi).

## Wymagania

- Debian 10/11/12 lub Ubuntu 20.04/22.04/24.04 (apt-based)
- Architektura **x86_64**
- Użytkownik z `sudo` (NIE root)

## Szybka instalacja (one-liner, prosto z GitHuba)

```bash
QLX_OWNER=7656119XXXXXXXXXX \
RCON_PASSWORD=mojeRconHaslo \
STATS_PASSWORD=mojeStatsHaslo \
bash <(curl -fsSL https://raw.githubusercontent.com/goof3r/quakelive-server/main/install_minqlx_server.sh)
```

`bash <(curl ...)` zachowuje stdin do terminala — interaktywne pytanie
*„Dodać teraz kolejny serwer?”* zadziała. Alternatywa `curl | bash` też
zadziała, ale po prostu pominie ten prompt.

Skrypt sam pobierze `commands.py` (załatany plugin `!lc`) z tego repo.

## Instalacja z klona repo

```bash
git clone https://github.com/goof3r/quakelive-server.git
cd quakelive-server
QLX_OWNER=7656119XXXXXXXXXX ./install_minqlx_server.sh
```

W tym wariancie instalator użyje `commands.py` leżącego obok skryptu — nie
wykonuje żadnego `curl` do GitHuba na ten plik (działa offline po klonie).

## Konfiguracja przez zmienne środowiskowe

Wszystkie wartości w sekcji KONFIGURACJA na początku `install_minqlx_server.sh`
można nadpisać z linii poleceń. Najczęściej używane:

| Zmienna | Domyślnie | Co robi |
|---|---|---|
| `QLX_OWNER` | `0000000000000000` | **TWÓJ SteamID64 (17 cyfr)** — bez tego nie zadziałają komendy admina |
| `SV_HOSTNAME` | `^2My minqlx Server` | nazwa serwera na liście |
| `NET_PORT` | `27960` | port UDP bazowego serwera (gdy NIE używasz trybów FFA/TDM/FT) |
| `RCON_PASSWORD` | `zmien_to_haslo_rcon` | hasło rcon (ZMIEŃ) |
| `STATS_PASSWORD` | `zmien_to_haslo_stats` | hasło zmq stats (ZMIEŃ) |
| `INSTALL_SYSTEMD` | `1` | `0` = nie instaluj `qlserver.service` ani serwisów trybów |
| `INSTALL_GAMETYPE_SERVERS` | `1` | `0` = nie instaluj serwerów trybów FFA/TDM/FT na portach 27960-27962 |
| `QLDS_DIR` | `$HOME/qlds` | gdzie wyląduje serwer |
| `COMMANDS_PY_URL` | raw URL z tego repo | nadpisz, jeśli forkujesz — instalator weźmie Twoją wersję commands.py |

SteamID64 znajdziesz na <https://steamid.io>.

## Dodawanie kolejnych serwerów

Po instalacji w `$QLDS_DIR/add_server.sh`:

```bash
~/qlds/add_server.sh           # interaktywnie pyta o nazwę i port
~/qlds/add_server.sh duel 27970   # od razu z argumentami
```

Tworzy `baseq3/<nazwa>.cfg`, `start-<nazwa>.sh`, katalog `instances/<nazwa>/`.
**Nie tworzy** żadnego unitu systemd. Uruchom ręcznie jednym z:

```bash
~/qlds/start-duel.sh
nohup ~/qlds/start-duel.sh > ~/qlds/duel.log 2>&1 &
screen -dmS qlserver-duel ~/qlds/start-duel.sh    # potem: screen -r qlserver-duel
```

Otwórz w firewallu port UDP (oraz `port+1000` TCP dla rcon).

Owner/hasła rcon/stats dziedziczone są z `~/qlds/start.sh` — wystarczy je
ustawić raz na początku.

## Co instaluje skrypt (skrót)

1. apt: python3-dev, redis-server, build-essential, lib32gcc, ...
2. SteamCMD + QLDS (app 349090, login anonymous)
3. Kompilacja minqlx ze źródeł (MinoMino/minqlx)
4. Pluginy:
   - **MinoMino/minqlx-plugins** (oficjalne)
   - **BarelyMiSSeD/minqlx-plugins** (specqueue, serverBDM, kills, ...)
   - **tjone270/Quake-Live/minqlx-plugins** (q3resolver, branding, ...)
   - Pojedyncze: queue (mattiZed/Melodeiro), autospec+iouonegirl (dsverdlo),
     checkplayers (x0rnn)
   - **Załatany `commands.py`** (`!lc`/`!plugins`) z tego repo — naprawia crash
     QLDS przy pełnej liście pluginów
5. Wbudowany `commlink.py` (most IRC) i `changemap.py` (auto-reset mapy na
   pustym serwerze) są usuwane jako niezgodne / niechciane.
6. `server.cfg`, `start.sh`, `qlserver.service` (jeśli `INSTALL_SYSTEMD=1`)
7. Serwery trybów FFA/TDM/FT + `gametypes.factories` (crobartie) na portach
   27960/27961/27962 (gdy `INSTALL_GAMETYPE_SERVERS=1`).
8. `add_server.sh` do późniejszych instancji (bez systemd, ręczny start).

## Aktualizacja

Uruchom instalator ponownie — zaktualizuje QLDS (SteamCMD `validate`), minqlx
(`git pull` + rebuild) i wszystkie pluginy. Twój `server.cfg` zostanie
nietknięty (sync tylko linii `qlx_plugins`, kopia jako `.bak.<timestamp>`).

## Test

Wejdź na serwer i wpisz na czacie:

```
!myperm
```

Jeśli pokaże poziom uprawnień > 0 — jesteś rozpoznany jako właściciel.

## Licencja

Sam instalator (ten plik + `install_minqlx_server.sh`) — bez ograniczeń.
`commands.py` to GPL-3.0 (pochodna pracy BarelyMiSSeD), załatka v1.1.
