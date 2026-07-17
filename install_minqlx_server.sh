#!/usr/bin/env bash
###############################################################################
#  install_minqlx_server.sh
#  Automatyczna instalacja serwera Quake Live (QLDS) + minqlx + pluginy.
#
#  Co robi skrypt:
#    1. Instaluje zależności systemowe (Python3, redis, git, build-essential...)
#    2. Pobiera SteamCMD i instaluje QLDS (Steam app 349090, login anonymous)
#    3. Klonuje i KOMPILUJE minqlx ze źródeł (gotowych binarek już nie ma)
#    4. Kopiuje binarki minqlx do katalogu serwera
#    5. Klonuje pluginy MinoMino (oficjalne) oraz BarelyMiSSeD (dodatkowe)
#    6. Instaluje zależności pip pluginów
#    7. Generuje server.cfg, skrypty startowe oraz narzędzie qlds-ctl:
#       każdy serwer w nazwanej sesji screen, auto-restart po padzie,
#       trwałe wyłączanie (qlds-ctl stop) i autostart po reboocie (cron @reboot)
#
#  Wymagania: Debian 10/11/12 lub Ubuntu 20.04/22.04/24.04 (system apt),
#             architektura x86_64, użytkownik z prawami sudo (NIE root).
#
#  Użycie:
#    1) Edytuj sekcję KONFIGURACJA poniżej (przede wszystkim QLX_OWNER!)
#    2) chmod +x install_minqlx_server.sh
#    3) ./install_minqlx_server.sh
#
#  Wszystkie zmienne można też nadpisać przez środowisko, np.:
#    QLX_OWNER=76561198799965164 NET_PORT=27960 ./install_minqlx_server.sh
###############################################################################

set -euo pipefail

# ───────────────────────────── KONFIGURACJA ─────────────────────────────────
# TWÓJ SteamID64 (17 cyfr) — WŁAŚCICIEL serwera. Bez tego nie zadziałają
# komendy admina. Konwerter: https://steamid.io  (pole steamID64)
: "${QLX_OWNER:=76561198799965164}"

# Nazwa serwera widoczna na liście
: "${SV_HOSTNAME:=^2My minqlx Server}"

# Port UDP serwera
: "${NET_PORT:=27960}"

# Hasła dla zdalnej konsoli (rcon) i statystyk (zmq) — ZMIEŃ na własne!
: "${RCON_PASSWORD:=zmien_to_haslo_rcon}"
: "${STATS_PASSWORD:=zmien_to_haslo_stats}"

# Katalogi instalacji (domyślnie w katalogu domowym użytkownika)
: "${STEAMCMD_DIR:=$HOME/steamcmd}"
: "${QLDS_DIR:=$HOME/qlds}"          # tu wyląduje serwer QL + minqlx
: "${BUILD_DIR:=$HOME/minqlx-build}" # tu klonujemy i kompilujemy źródła

# Czy zainstalować gotowe serwery trybów FFA/TDM/FT (z dołączonymi factory
# crobartie). 1 = tak. Generuje skrypty startowe start-<gt>.sh; serwerami
# sterujesz przez qlds-ctl (start/stop/restart/status/console).
: "${INSTALL_GAMETYPE_SERVERS:=1}"

# Repozytoria (zwykle nie trzeba zmieniać)
MINQLX_REPO="https://github.com/MinoMino/minqlx.git"
PLUGINS_REPO="https://github.com/MinoMino/minqlx-plugins.git"
BARELY_REPO="https://github.com/BarelyMiSSeD/minqlx-plugins.git"
TJONE_REPO="https://github.com/tjone270/Quake-Live.git"   # pluginy w podkatalogu minqlx-plugins/
# Pojedyncze pluginy zewnętrzne używane przez przykładowe cfg trybów FFA/TDM/FT
# (nie ma ich w MinoMino/BarelyMiSSeD/tjone270 — pobierane bezpośrednio z repo autorów):
QUEUE_RAW="https://raw.githubusercontent.com/Melodeiro/minqlx-plugins_mattiZed/master/queue.py"
AUTOSPEC_RAW="https://raw.githubusercontent.com/dsverdlo/minqlx-plugins/master/autospec.py"
IOUONE_RAW="https://raw.githubusercontent.com/dsverdlo/minqlx-plugins/master/iouonegirl.py"  # klasa bazowa dla autospec
CHECKPLAYERS_RAW="https://raw.githubusercontent.com/x0rnn/minqlx-plugins/master/checkplayers.py"
WEAPONSPAWNFIXER_RAW="https://raw.githubusercontent.com/roasticle/minqlx-plugins/master/weaponspawnfixer.py"
# Repo TEGO instalatora (źródło załatanego commands.py, gdy instalator uruchamiany
# przez 'curl | bash' bez lokalnej kopii). Nadpiszesz np. forkując i ustawiając
# COMMANDS_PY_URL=...  w środowisku przed uruchomieniem.
: "${COMMANDS_PY_URL:=https://raw.githubusercontent.com/goof3r/quakelive-server/main/commands.py}"
# Plugin serverhelp (własny: !help / !version / !perms — patrz serverhelp.py w repo).
: "${SERVERHELP_PY_URL:=https://raw.githubusercontent.com/goof3r/quakelive-server/main/serverhelp.py}"
# Plugin permoverride (własny: cvar qlx_permFor_<komenda> + !permset/!permshow/!permlist/!permreload).
: "${PERMOVERRIDE_PY_URL:=https://raw.githubusercontent.com/goof3r/quakelive-server/main/permoverride.py}"
# Narzędzie qlds-ctl (start/stop/restart/status/console serwerów — patrz qlds-ctl w repo).
: "${QLDS_CTL_URL:=https://raw.githubusercontent.com/goof3r/quakelive-server/main/qlds-ctl}"
# Definicje factory trybów (gametypes.factories — patrz plik gametypes-factories w repo).
: "${GAMETYPES_FACTORIES_URL:=https://raw.githubusercontent.com/goof3r/quakelive-server/main/gametypes-factories}"
QLDS_APPID="349090"
STEAMCMD_URL="https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz"

# Lista Steam Workshop ID-ków ładowanych na starcie serwera. Generuje:
#   1) $QLDS_DIR/workshop.txt (jeden ID na linię — łatwa edycja ręczna),
#   2) cvar 'qlx_workshopReferences' (comma-lista) w server.cfg i tdm/ffa/ft.cfg
#      — plugin 'workshop' (MinoMino) faktycznie czyta TĘ wartość, plik .txt to
#      tylko ludzka kopia listy.
WORKSHOP_IDS=(
  623144451 539421982 539421606 546664071 547252823 573808557 583820600
  573807159 584964611 564894881 575312620 586817666 584984610 565025333
  638618725 638531198 637351306 617896584 564946744 641499246 641587915
  637350852 641575854 643615147 675534589 679928531 679928822 568582691
  582665687 584815070 673213646 726131097 726132863 726133798 726134197
  663160788 774095795 803438741 824405313 827249184 827250713 827252336
  824405003 850146040 852034378 572015381 1502166021
)
WORKSHOP_IDS_CSV="$( IFS=, ; echo "${WORKSHOP_IDS[*]}" )"
WORKSHOP_IDS_TXT="$(printf '%s\n' "${WORKSHOP_IDS[@]}")"
# ─────────────────────────────────────────────────────────────────────────────

# ── Pomocnicze ───────────────────────────────────────────────────────────────
c_ok="\033[1;32m"; c_warn="\033[1;33m"; c_err="\033[1;31m"; c_info="\033[1;36m"; c_end="\033[0m"
log()  { echo -e "${c_info}[*]${c_end} $*"; }
ok()   { echo -e "${c_ok}[OK]${c_end} $*"; }
warn() { echo -e "${c_warn}[!]${c_end} $*"; }
err()  { echo -e "${c_err}[X]${c_end} $*" >&2; }
die()  { err "$*"; exit 1; }

# Klonuje LUB aktualizuje (git pull) repo z pluginami i kopiuje pliki .py do
# katalogu pluginów serwera. Dzięki temu ta sama funkcja obsługuje pierwszą
# instalację oraz każdą późniejszą aktualizację (ponowne uruchomienie skryptu).
#   $1 = etykieta (do logów)
#   $2 = URL repo git
#   $3 = lokalny katalog klona (w BUILD_DIR)
#   $4 = podkatalog w repo z pluginami ("." = korzeń repo)
sync_plugin_repo() {
  local label="$1" url="$2" dir="$3" subdir="$4"
  log "Pobieram/aktualizuję pluginy: ${label}..."
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --ff-only || warn "git pull ${label} nieudany — używam lokalnej kopii."
  else
    git clone "$url" "$dir" || { warn "Nie udało się sklonować ${label} — pomijam."; return 0; }
  fi
  local src="$dir/$subdir"
  if compgen -G "$src/*.py" >/dev/null 2>&1; then
    # Uwaga: jeśli dwa repozytoria mają plik o tej samej nazwie, wygrywa to
    # kopiowane później (kolejność wywołań w sekcji 5).
    cp -v "$src"/*.py "$QLDS_DIR/minqlx-plugins/" || warn "Kopiowanie .py z ${label} częściowo nieudane."
    ok "Pluginy ${label} skopiowane."
  else
    warn "Brak plików .py w ${src} (${label}) — nic nie skopiowano."
  fi
}

# ── Kontrole wstępne ─────────────────────────────────────────────────────────
[ "$(id -u)" -ne 0 ] || die "Nie uruchamiaj jako root. Użyj zwykłego użytkownika z sudo (SteamCMD i serwer NIE mogą działać jako root)."
command -v sudo  >/dev/null 2>&1 || die "Brak 'sudo'. Zainstaluj sudo i dodaj użytkownika do grupy sudo."
command -v apt-get >/dev/null 2>&1 || die "Skrypt obsługuje tylko systemy z apt (Debian/Ubuntu). Zobacz README dla innych systemów."
[ "$(uname -m)" = "x86_64" ] || warn "Wykryto architekturę $(uname -m). Serwer QL wymaga x86_64 — może nie zadziałać."

if ! [[ "$QLX_OWNER" =~ ^[0-9]{17}$ ]]; then
  warn "QLX_OWNER nie jest poprawnym SteamID64 (17 cyfr). Zainstaluję serwer, ale"
  warn "PAMIĘTAJ ustawić qlx_owner później (w start.sh), inaczej nie będziesz adminem."
fi

log "Katalog QLDS:  $QLDS_DIR"
log "Katalog build: $BUILD_DIR"
echo

# ── 1. Zależności systemowe ──────────────────────────────────────────────────
log "Instaluję zależności systemowe (apt)..."
sudo dpkg --add-architecture i386 || true
sudo apt-get update -y
sudo apt-get install -y \
  python3 python3-dev python3-pip \
  redis-server git build-essential make \
  wget curl ca-certificates tar locales screen \
  || die "Nie udało się zainstalować pakietów bazowych."

# Biblioteki 32-bit potrzebne SteamCMD (nazwy różnią się między wersjami)
sudo apt-get install -y lib32gcc-s1     || sudo apt-get install -y lib32gcc1 || warn "Nie zainstalowano lib32gcc — SteamCMD może protestować."
sudo apt-get install -y lib32stdc++6    || warn "Nie zainstalowano lib32stdc++6."
ok "Zależności gotowe."

PYVER="$(python3 -c 'import sys;print(".".join(map(str,sys.version_info[:2])))')"
log "Wersja Pythona: $PYVER"

# ── 2. Redis ─────────────────────────────────────────────────────────────────
log "Uruchamiam i włączam usługę redis-server..."
sudo systemctl enable --now redis-server 2>/dev/null \
  || sudo systemctl enable --now redis 2>/dev/null \
  || warn "Nie udało się włączyć redis przez systemd — sprawdź ręcznie."
ok "Redis skonfigurowany (domyślnie 127.0.0.1:6379)."

# ── 3. SteamCMD + QLDS ───────────────────────────────────────────────────────
log "Instaluję SteamCMD..."
mkdir -p "$STEAMCMD_DIR"
if [ ! -f "$STEAMCMD_DIR/steamcmd.sh" ]; then
  ( cd "$STEAMCMD_DIR" && curl -sqL "$STEAMCMD_URL" | tar zxvf - ) \
    || die "Nie udało się pobrać/rozpakować SteamCMD."
fi
ok "SteamCMD gotowy."

log "Pobieram / aktualizuję Quake Live Dedicated Server (app $QLDS_APPID)..."
mkdir -p "$QLDS_DIR"
"$STEAMCMD_DIR/steamcmd.sh" \
  +force_install_dir "$QLDS_DIR" \
  +login anonymous \
  +app_update "$QLDS_APPID" validate \
  +quit \
  || die "SteamCMD nie zainstalował QLDS. Uruchom ponownie skrypt (czasem trzeba 2x)."
[ -f "$QLDS_DIR/run_server_x64.sh" ] || die "Brak run_server_x64.sh — instalacja QLDS niepełna."
ok "QLDS zainstalowany w $QLDS_DIR."

# ── 4. Kompilacja minqlx ─────────────────────────────────────────────────────
log "Klonuję i kompiluję minqlx ze źródeł..."
mkdir -p "$BUILD_DIR"
if [ -d "$BUILD_DIR/minqlx/.git" ]; then
  git -C "$BUILD_DIR/minqlx" pull --ff-only || warn "git pull minqlx nieudany, kompiluję istniejącą wersję."
else
  git clone "$MINQLX_REPO" "$BUILD_DIR/minqlx"
fi
( cd "$BUILD_DIR/minqlx" && make clean >/dev/null 2>&1 || true; make ) \
  || die "Kompilacja minqlx nie powiodła się. Najczęstsza przyczyna: brak python3-dev lub bardzo nowy Python. Zobacz README (sekcja Docker / starszy Python)."
[ -f "$BUILD_DIR/minqlx/bin/minqlx.x64.so" ] || die "Nie powstał plik bin/minqlx.x64.so — kompilacja niepełna."
ok "minqlx skompilowany."

log "Kopiuję binarki minqlx do katalogu serwera..."
cp -rv "$BUILD_DIR/minqlx/bin/." "$QLDS_DIR/"
chmod +x "$QLDS_DIR"/run_server_x64_minqlx.sh 2>/dev/null || true
[ -f "$QLDS_DIR/run_server_x64_minqlx.sh" ] || die "Brak run_server_x64_minqlx.sh po kopiowaniu."
ok "Binarki minqlx na miejscu."

# ── 5. Pluginy ───────────────────────────────────────────────────────────────
log "Klonuję oficjalne pluginy MinoMino..."
if [ -d "$QLDS_DIR/minqlx-plugins/.git" ]; then
  git -C "$QLDS_DIR/minqlx-plugins" pull --ff-only || warn "git pull pluginów nieudany."
else
  git clone "$PLUGINS_REPO" "$QLDS_DIR/minqlx-plugins"
fi
ok "Pluginy MinoMino gotowe."

log "Dodaję pluginy BarelyMiSSeD (specqueue, serverBDM, protect, kills itd.)..."
sync_plugin_repo "BarelyMiSSeD" "$BARELY_REPO" "$BUILD_DIR/barely" "."
# Dodatkowy folder z nazwami map (używany przez listmaps):
[ -d "$BUILD_DIR/barely/Map_Names" ] && cp -rv "$BUILD_DIR/barely/Map_Names" "$QLDS_DIR/minqlx-plugins/" || true

log "Dodaję pluginy tjone270 (q3resolver, branding, botmanager, quiet itd.)..."
# W tym repo pluginy leżą w PODKATALOGU minqlx-plugins/, dlatego 4. argument:
sync_plugin_repo "tjone270" "$TJONE_REPO" "$BUILD_DIR/tjone270" "minqlx-plugins"

# commlink (most IRC) jest zbędny i niezgodny z Pythonem 3.11+ — USUWAMY plik
# całkowicie z instalacji (także przy aktualizacji, po ponownym skopiowaniu).
rm -f "$QLDS_DIR/minqlx-plugins/commlink.py"
ok "Plugin commlink usunięty z instalacji (zbędny most IRC)."

# changemap (tjone270) automatycznie zmienia mapę na DOMYŚLNĄ, gdy serwer się
# opróżnia (hook player_disconnect przy <=1 graczu). Efekt uboczny: po reconnect
# mapa/gametyp wracają do qlx_defaultMapToChangeTo/...Factory (domyślnie
# campgrounds + ffa). USUWAMY go całkowicie (także przy aktualizacji).
rm -f "$QLDS_DIR/minqlx-plugins/changemap.py"
ok "Plugin changemap usunięty z instalacji (auto-reset mapy na pustym serwerze)."

# Wgrywamy ZAŁATANĄ wersję pluginu 'commands' (komendy !lc / !plugins).
# Oryginał z BarelyMiSSeD wysyłał osobny komunikat player.tell() na KAŻDY plugin —
# przy pełnej liście pluginów potrafiło to wypchnąć kilkadziesiąt komend 'reliable'
# w jednej klatce, przepełnić bufor silnika QL i wywalić CAŁY proces serwera
# (systemd podnosił go z Restart=on-failure -> wyglądało jak 'reset'). Ta wersja
# buduje całą listę, pakuje ją w kilka komunikatów <=900 znaków i rozkłada na
# kolejne klatki.
#
# Źródło pliku:
#   1) jeśli instalator uruchomiony z klona repo (commands.py LEŻY OBOK skryptu) —
#      kopiujemy lokalny (szybciej, działa offline po sklonowaniu),
#   2) inaczej (np. instalacja przez 'curl | bash') — pobieramy z GitHub raw URL
#      (COMMANDS_PY_URL) jednym żądaniem.
SCRIPT_DIR="$( (cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || true )"
CONFIGS_DIR=""
[ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/configs and mappool" ] && CONFIGS_DIR="$SCRIPT_DIR/configs and mappool"
SRC_COMMANDS=""
[ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/commands.py" ] && SRC_COMMANDS="$SCRIPT_DIR/commands.py"
DST_COMMANDS="$QLDS_DIR/minqlx-plugins/commands.py"
if [ -n "$SRC_COMMANDS" ]; then
  log "Wgrywam załataną wersję pluginu commands (!lc) z lokalnego $SRC_COMMANDS..."
  cp -f "$SRC_COMMANDS" "$DST_COMMANDS"
  ok "Plugin commands (załatany) wgrany z $SRC_COMMANDS."
else
  log "Pobieram załataną wersję pluginu commands (!lc) z $COMMANDS_PY_URL..."
  if curl -fsSL "$COMMANDS_PY_URL" -o "$DST_COMMANDS" && [ -s "$DST_COMMANDS" ]; then
    # Lekka walidacja: ma być plik Pythona z klasą 'commands'.
    if grep -qE '^class[[:space:]]+commands' "$DST_COMMANDS"; then
      ok "Plugin commands (załatany) pobrany z GitHub."
    else
      warn "Pobrany commands.py wygląda na uszkodzony (brak 'class commands') — pozostawiam wersję z repo BarelyMiSSeD."
      cp -f "$BUILD_DIR/barely/commands.py" "$DST_COMMANDS" 2>/dev/null || true
    fi
  else
    warn "Nie udało się pobrać commands.py z $COMMANDS_PY_URL — pozostaje wersja z repo BarelyMiSSeD"
    warn "(może wywalać serwer przy !lc z pełną listą pluginów)."
  fi
fi

# ── 5a-bis. Plugin serverhelp (własny: !help / !version / !perms) ─────────────
# Przejmuje !help (lista WSZYSTKICH komend, jedna pod drugą) oraz !version
# (zwraca wersję minqlx) — robi to przez priority=PRI_HIGH + RET_STOP_ALL,
# więc handler cmd_help z essentials nie zostanie wywołany dla tych aliasów.
# Dodaje też !perms (poziomy 0..5 + bieżący poziom gracza).
#
# Źródło pliku: tak samo jak commands.py — lokalne obok skryptu albo curl.
SRC_SERVERHELP=""
[ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/serverhelp.py" ] && SRC_SERVERHELP="$SCRIPT_DIR/serverhelp.py"
DST_SERVERHELP="$QLDS_DIR/minqlx-plugins/serverhelp.py"
if [ -n "$SRC_SERVERHELP" ]; then
  log "Wgrywam plugin serverhelp (!help/!version/!perms) z lokalnego $SRC_SERVERHELP..."
  cp -f "$SRC_SERVERHELP" "$DST_SERVERHELP"
  ok "Plugin serverhelp wgrany z $SRC_SERVERHELP."
else
  log "Pobieram plugin serverhelp z $SERVERHELP_PY_URL..."
  if curl -fsSL "$SERVERHELP_PY_URL" -o "$DST_SERVERHELP" && [ -s "$DST_SERVERHELP" ]; then
    if grep -qE '^class[[:space:]]+serverhelp' "$DST_SERVERHELP"; then
      ok "Plugin serverhelp pobrany z GitHub."
    else
      warn "Pobrany serverhelp.py wygląda na uszkodzony (brak 'class serverhelp') — usuwam."
      rm -f "$DST_SERVERHELP"
    fi
  else
    warn "Nie udało się pobrać serverhelp.py z $SERVERHELP_PY_URL — !help pozostanie domyślne."
  fi
fi

# ── 5a-ter. Plugin permoverride (nadpisywanie qlx perm dla komend cvarami) ────
# Czyta `qlx_permFor_<komenda>` z server.cfg i podmienia .permission na
# obiektach minqlx.Command po starcie. Dodaje !permset/!permshow/!permlist/
# !permreload. Powinien być ZA innymi pluginami w qlx_plugins — installer
# ustawia go na samym końcu listy automatycznie.
SRC_PERMOVERRIDE=""
[ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/permoverride.py" ] && SRC_PERMOVERRIDE="$SCRIPT_DIR/permoverride.py"
DST_PERMOVERRIDE="$QLDS_DIR/minqlx-plugins/permoverride.py"
if [ -n "$SRC_PERMOVERRIDE" ]; then
  log "Wgrywam plugin permoverride z lokalnego $SRC_PERMOVERRIDE..."
  cp -f "$SRC_PERMOVERRIDE" "$DST_PERMOVERRIDE"
  ok "Plugin permoverride wgrany z $SRC_PERMOVERRIDE."
else
  log "Pobieram plugin permoverride z $PERMOVERRIDE_PY_URL..."
  if curl -fsSL "$PERMOVERRIDE_PY_URL" -o "$DST_PERMOVERRIDE" && [ -s "$DST_PERMOVERRIDE" ]; then
    if grep -qE '^class[[:space:]]+permoverride' "$DST_PERMOVERRIDE"; then
      ok "Plugin permoverride pobrany z GitHub."
    else
      warn "Pobrany permoverride.py wygląda na uszkodzony (brak 'class permoverride') — usuwam."
      rm -f "$DST_PERMOVERRIDE"
    fi
  else
    warn "Nie udało się pobrać permoverride.py z $PERMOVERRIDE_PY_URL — override'y cvarami nie zadziałają."
  fi
fi

ok "Pluginy dodatkowe skopiowane (włączysz wybrane w server.cfg → qlx_plugins)."

# ── 5b. Pluginy zewnętrzne używane przez cfg trybów FFA/TDM/FT ────────────────
# Te pluginy NIE występują w repo MinoMino/BarelyMiSSeD/tjone270 — pobieramy je
# pojedynczo z repozytoriów ich autorów (świeża wersja przy każdym uruchomieniu):
#   queue        (mattiZed/Melodeiro) — kolejka graczy do gry
#   autospec     (dsverdlo)           — auto-spec przy nierównych drużynach;
#                                        wymaga klasy bazowej iouonegirl.py + pip 'requests'
#   checkplayers (x0rnn)              — !checkplayers: lista perm/ban/silence/leaver
#   weaponspawnfixer (roasticle)      — wymusza g_weaponRespawn na starcie mapy/gry
#                                        (obejście buga silnika QL ignorującego cvar)
# UWAGA: są tylko POBIERANE (dostępne), ale NIE włączone w domyślnym server.cfg.
# Włączają je dopiero konfiguracje trybów (qlx_plugins w ffa/tdm/ft.cfg).
# Pluginów 'patch' i 'specvote' z tamtych cfg NIE pobieramy — to bespoke pluginy
# konkretnego serwera (twarde, obce ustawienia), bezużyteczne na innym serwerze.
log "Pobieram zewnętrzne pluginy (queue, autospec, checkplayers, weaponspawnfixer)..."
fetch_plugin() {  # $1=URL  $2=docelowa_nazwa_pliku
  if curl -sfqL "$1" -o "$QLDS_DIR/minqlx-plugins/$2" && [ -s "$QLDS_DIR/minqlx-plugins/$2" ]; then
    ok "  pobrano: $2"
  else
    warn "  nie udało się pobrać $2 (z $1) — plugin pominięty."
  fi
}
fetch_plugin "$QUEUE_RAW"        "queue.py"
fetch_plugin "$AUTOSPEC_RAW"     "autospec.py"
fetch_plugin "$IOUONE_RAW"       "iouonegirl.py"   # klasa bazowa wymagana przez autospec
fetch_plugin "$CHECKPLAYERS_RAW" "checkplayers.py"
fetch_plugin "$WEAPONSPAWNFIXER_RAW" "weaponspawnfixer.py"

# ── 5c. Lokalne pluginy z katalogu minqlx-plugins/ (nadpisują wersje z repo) ─
# Jeśli obok skryptu instalatora istnieje katalog minqlx-plugins/ (lokalny klon
# repo z nowszymi wersjami), jego zawartość jest kopiowana jako ostatnia —
# nadpisuje wszystko pobrane wcześniej z MinoMino/BarelyMiSSeD/tjone270 i przez
# fetch_plugin. Lokalne wersje zawsze wygrywają.
PLUGINS_LOCAL_DIR=""
[ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/minqlx-plugins" ] && PLUGINS_LOCAL_DIR="$SCRIPT_DIR/minqlx-plugins"
if [ -n "$PLUGINS_LOCAL_DIR" ]; then
  log "Kopiuję lokalne pluginy z $PLUGINS_LOCAL_DIR (nadpisują wersje z repo)..."
  if compgen -G "$PLUGINS_LOCAL_DIR/*.py" >/dev/null 2>&1; then
    cp -v "$PLUGINS_LOCAL_DIR"/*.py "$QLDS_DIR/minqlx-plugins/" \
      || warn "Kopiowanie lokalnych pluginów częściowo nieudane."
  fi
  [ -f "$PLUGINS_LOCAL_DIR/requirements.txt" ] && \
    cp -f "$PLUGINS_LOCAL_DIR/requirements.txt" "$QLDS_DIR/minqlx-plugins/requirements.txt"
  [ -f "$PLUGINS_LOCAL_DIR/mbot_maps.json" ] && \
    cp -f "$PLUGINS_LOCAL_DIR/mbot_maps.json" "$QLDS_DIR/minqlx-plugins/mbot_maps.json"
  [ -d "$PLUGINS_LOCAL_DIR/Map_Names" ] && \
    cp -rv "$PLUGINS_LOCAL_DIR/Map_Names" "$QLDS_DIR/minqlx-plugins/"
  [ -d "$PLUGINS_LOCAL_DIR/extras" ] && \
    cp -rv "$PLUGINS_LOCAL_DIR/extras" "$QLDS_DIR/minqlx-plugins/"
  ok "Lokalne pluginy skopiowane z $PLUGINS_LOCAL_DIR."
else
  log "Brak lokalnego katalogu minqlx-plugins/ obok skryptu — używam wersji z repo."
fi

# ── 6. Zależności pip pluginów ───────────────────────────────────────────────
log "Instaluję zależności Pythona dla pluginów (pip)..."
if [ -f "$QLDS_DIR/minqlx-plugins/requirements.txt" ]; then
  sudo -H env PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install \
       -r "$QLDS_DIR/minqlx-plugins/requirements.txt" \
    || warn "pip zgłosił błędy — sprawdź wyżej. Część ostrzeżeń jest nieszkodliwa."
else
  warn "Brak requirements.txt w pluginach — pomijam pip."
fi

# Dodatkowe zależności wymagane przez pluginy spoza MinoMino.
# UWAGA: przy starcie minqlx jeden plugin z brakującą zależnością przerywa
# ładowanie WSZYSTKICH kolejnych pluginów z listy — dlatego instalujemy je z góry.
#   schedule -> wymagane przez autorestart (tjone270)
#   requests -> wymagane przez autospec (dsverdlo) — import na sztywno na górze pliku
EXTRA_PIP="schedule requests"
log "Instaluję dodatkowe zależności pluginów: ${EXTRA_PIP}..."
sudo -H env PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install $EXTRA_PIP \
  || warn "Nie udało się zainstalować: ${EXTRA_PIP} — pluginy ich wymagające nie wczytają się."
ok "Zależności pip zainstalowane."

# ── 7. server.cfg ────────────────────────────────────────────────────────────
CFG="$QLDS_DIR/baseq3/server.cfg"
mkdir -p "$QLDS_DIR/baseq3"

# Pełna lista pluginów. Wstrzykiwana do server.cfg, a przy aktualizacji
# synchronizowana również w już istniejącym server.cfg (patrz niżej).
QLX_PLUGINS_LIST="plugin_manager, essentials, motd, permission, ban, silence, clan, names, log, workshop, weaponspawnfixer, aliases, autorestart, botmanager, branding, custom_votes, dictionary, disabled_commands, ips, onjoin, permaban, permissionlist, q3resolver, quiet, ratinglimiter, sv_fps, thirtysecwarn, votemanager, votestats, commands, serverhelp, permoverride"

# Lista pluginów dla serwerów trybów (FFA/TDM/FT). Wzięta z dołączonych cfg-ów,
# ale OCZYSZCZONA: usunięte 'irc' (na życzenie) oraz 'patch' i 'specvote' (bespoke
# pluginy obcego serwera — nie istnieją w żadnym repo, blokowałyby ładowanie).
GT_PLUGINS_LIST="plugin_manager, essentials, motd, permission, ban, warmup_weapons, maps, clan, names, silence, log, balance, branding, workshop, weaponspawnfixer, queue, autospec, checkplayers, votestats, ips, aliases, botmanager, onjoin, serverhelp, permoverride"

if [ -f "$CFG" ]; then
  warn "server.cfg już istnieje — nie nadpisuję go w całości. Wzór: server.cfg.example."
  CFG_OUT="$QLDS_DIR/baseq3/server.cfg.example"
else
  CFG_OUT="$CFG"
fi
cat > "$CFG_OUT" <<'CFGEOF'
// ===========================================================================
//  server.cfg — konfiguracja serwera Quake Live + minqlx
//  Cvary minqlx mają prefiks qlx_. Pełna lista komend:
//  https://github.com/MinoMino/minqlx/wiki/Command-List
// ===========================================================================

// --- Podstawy QL ---
set sv_hostname            "^2My minqlx Server"
set g_motd                 "Powered by minqlx"
set sv_maxclients          "16"
set teamsize               "4"
set g_inactivity           "0"
set sv_allowDownload       "1"
set g_allowVote            "1"

// --- minqlx: rdzeń ---
// qlx_owner ustawiany jest w start.sh (z wartości QLX_OWNER). Możesz też tu:
// set qlx_owner            "76561198799965164"

set qlx_commandPrefix      "!"

// Lista wczytywanych pluginów (kolejność ma znaczenie).
// Zawiera domyślne pluginy MinoMino + WSZYSTKIE pluginy tjone270 (włączone).
// Jeśli kiedykolwiek nazwa pliku tjone270 pokryje się z pluginem MinoMino,
// instalator kopiuje wersję tjone270 jako ostatnią (ona wygrywa = podmiana).
set qlx_plugins            "__QLX_PLUGINS__"

// Pluginy tjone270 wczytywane powyżej (kolejność na liście = kolejność ładowania):
//   aliases          - aliasy komend
//   autorestart      - automatyczny restart serwera
//   botmanager       - automatyczne dodawanie/usuwanie botów (bot_autoManage)
//   branding         - personalizacja serwera (qlx_serverBrandName itd.)
//   custom_votes     - własne typy callvote
//   dictionary       - słownik/tłumaczenia komend
//   disabled_commands- wyłącza wskazane komendy (sprawdź ustawienia w pliku!)
//   ips              - !ip <id> — historia adresów IP gracza (z Redis)
//   onjoin           - !onjoin <wiadomość> — wiadomość powitalna gracza
//   permaban         - bany trwałe (pokrywa się funkcją z 'ban')
//   permissionlist   - !permissionlist — lista graczy z uprawnieniami > 0
//   q3resolver       - głosowanie nazwami map z Quake 3 (np. /cv map q3dm12)
//   quiet            - blokada czatu w trakcie meczu (qlx_permitChatDuringWarmup)
//   ratinglimiter    - limit dołączania wg ratingu/ELO
//   sv_fps           - !svfps <int> — zmiana sv_fps na żywo (qlx_svfps, dom. 40)
//   thirtysecwarn    - dźwięk VO przy zbliżającym się limicie czasu rundy
//   votemanager      - zarządzanie głosowaniami / force-vote (permlevel 3)
//   votestats        - !votes — odanonimizowanie i statystyki głosowań
//
// (plugin 'commlink' / most IRC został celowo USUNIĘTY z instalacji —
//  zbędny i niezgodny z Pythonem 3.11+.)
// (plugin 'changemap' został celowo USUNIĘTY — automatycznie resetował mapę na
//  pustym serwerze, m.in. po reconnect. Jeśli go potrzebujesz, sklonuj z repo
//  tjone270 i ustaw cvary qlx_defaultMapToChangeTo / qlx_defaultMapFactoryToChangeTo.)
//
// --- Plugin 'commands' (BarelyMiSSeD) — WŁĄCZONY domyślnie, wersja ZAŁATANA ---
//   commands    - !plugins / !lc — lista załadowanych pluginów i komend.
//                 Instalator wgrywa poprawioną wersję (oryginał wywalał serwer
//                 przy !lc z powodu przepełnienia bufora komend). Nie chcesz tej
//                 komendy? Usuń 'commands' z qlx_plugins powyżej.
//
// --- Pluginy DODATKOWE (BarelyMiSSeD) — opcjonalne, NIE włączone ---
// Aby włączyć, DOPISZ nazwę pliku (bez .py) do qlx_plugins powyżej.
// Dostępne (po skopiowaniu przez instalator):
//   specqueue   - kolejka graczy / wyrównywanie drużyn
//   serverBDM   - rating BDM + auto-balans (UWAGA: nadpisuje !balance/!teams)
//   protect     - ochrona graczy, !forcets, vote mute/afk
//   kills       - statystyki specjalnych fragów (gauntlet, air rocket itd.)
//   listmaps    - !listmaps — lista map na serwerze
//   maplimiter  - ograniczanie map do głosowania
//   votelimiter - limit i whitelist głosowań
//   voteban     - ban gracza od głosowania
//   handicap    - auto-handicap wg ELO
//   inviteonly  - serwer tylko dla zaproszonych
//   clanmembers - zarządzanie tagami klanowymi
//   specall     - !specall — wszyscy na spec
//   voicechat   - przełączanie global/team voice
//   bots        - utrzymuje boty (wymaga specqueue)
//   battleroyale- tryb last-man-standing (NIEzgodny z innymi kolejkami)
//   wipeout     - tryb Wipeout na bazie Clan Arena

// --- Pluginy ZEWNĘTRZNE (pobierane przez instalator z repo innych autorów) ---
// Dostępne, ale NIE włączone tutaj — używają ich konfiguracje trybów FFA/TDM/FT:
//   queue            - kolejka graczy do gry (mattiZed/Melodeiro)
//   autospec         - auto-spec przy nierównych drużynach (dsverdlo; wymaga requests)
//   checkplayers     - !checkplayers: gracze z perm/ban/silence/leaver (x0rnn)
//   weaponspawnfixer - wymusza g_weaponRespawn na new_game/game_start (roasticle)
//                      obejście buga silnika QL, który potrafi zignorować cvar
// (UWAGA: 'balance' (MinoMino) + 'autospec' + 'queue' to trzy nakładające się
//  systemy zarządzania drużynami/kolejką — włączaj świadomie, mogą sobie wchodzić
//  w drogę. 'patch' i 'specvote' z obcych cfg celowo POMINIĘTE — bespoke, obce.)

// --- minqlx: baza danych (Redis) ---
set qlx_database           "Redis"
set qlx_redisAddress       "127.0.0.1"
set qlx_redisDatabase      "0"
set qlx_redisUnixSocket    "0"
// set qlx_redisPassword   ""

// --- Steam Workshop (plugin 'workshop' z MinoMino) ---
// Lista ID-ków przedmiotów Workshop ładowanych do serwera (mapy, modele itd.).
// Ludzką wersję tej listy trzymasz w pliku $QLDS_DIR/workshop.txt — instalator
// generuje OBA, ale ŹRÓDŁEM PRAWDY DLA SERWERA jest CVAR poniżej (plugin czyta
// cvar, nie plik). Po edycji workshop.txt zsynchronizuj ten cvar ręcznie albo
// uruchom instalator ponownie.
set qlx_workshopReferences "__QLX_WORKSHOP__"

// --- minqlx: logi ---
set qlx_logs               "5"
set qlx_logsSize           "5000000"

// --- Pula map (przykład) ---
// set sv_mapPoolFile      "mappool.txt"

// Pierwsza mapa po starcie. WAŻNE: podaj też factory (gametyp)!
// Samo "map campgrounds" bez factory powoduje, że QLDS wypisuje tylko składnię
// "map (map) (factory)" i serwer NIE wstaje. Dostępne factory:
//   ffa duel ca ctf tdm ft dom ad oneflag har race rr infected quadhog actf ictf iffa ift vca
map campgrounds ffa
CFGEOF
# Wstrzykujemy aktualną listę pluginów oraz listę workshop w wygenerowany plik:
sed -i "s|__QLX_PLUGINS__|${QLX_PLUGINS_LIST}|" "$CFG_OUT"
sed -i "s|__QLX_WORKSHOP__|${WORKSHOP_IDS_CSV}|" "$CFG_OUT"
ok "Zapisano konfigurację: $CFG_OUT"

# Jeśli aktywny server.cfg już istniał (zapisaliśmy tylko .example), to mimo to
# ZSYNCHRONIZUJ w nim linie qlx_plugins i qlx_workshopReferences — inaczej nowe
# pluginy/workshop się nie załadują. Reszta Twoich ustawień (mapa, hostname itd.)
# pozostaje nietknięta. Backup obok.
if [ "$CFG_OUT" != "$CFG" ] && [ -f "$CFG" ]; then
  cp -a "$CFG" "${CFG}.bak.$(date +%Y%m%d%H%M%S)"
  if grep -qE '^[[:space:]]*set[[:space:]]+qlx_plugins' "$CFG"; then
    sed -i -E "s|^[[:space:]]*set[[:space:]]+qlx_plugins.*|set qlx_plugins \"${QLX_PLUGINS_LIST}\"|" "$CFG"
    ok "Zsynchronizowano qlx_plugins w istniejącym server.cfg (kopia: ${CFG}.bak.*)."
  else
    printf '\nset qlx_plugins "%s"\n' "$QLX_PLUGINS_LIST" >> "$CFG"
    ok "Dodano qlx_plugins do istniejącego server.cfg (kopia: ${CFG}.bak.*)."
  fi
  if grep -qE '^[[:space:]]*set[[:space:]]+qlx_workshopReferences' "$CFG"; then
    sed -i -E "s|^[[:space:]]*set[[:space:]]+qlx_workshopReferences.*|set qlx_workshopReferences \"${WORKSHOP_IDS_CSV}\"|" "$CFG"
    ok "Zsynchronizowano qlx_workshopReferences w istniejącym server.cfg."
  else
    printf 'set qlx_workshopReferences "%s"\n' "$WORKSHOP_IDS_CSV" >> "$CFG"
    ok "Dodano qlx_workshopReferences do istniejącego server.cfg."
  fi
fi

# ── 7a. workshop.txt (Steam Workshop ID-ki) ──────────────────────────────────
# Plik z listą ID-ków Workshop, jeden na linię. ŹRÓDŁEM PRAWDY dla pluginu jest
# CVAR qlx_workshopReferences (powyżej, w cfgach) — plik to ludzka, łatwa do
# edycji wersja listy. Przy ponownym uruchomieniu instalatora cvar i plik są
# regenerowane z tablicy WORKSHOP_IDS na początku tego skryptu.
WORKSHOP_FILE="$QLDS_DIR/workshop.txt"
if [ -f "$WORKSHOP_FILE" ]; then
  warn "workshop.txt już istnieje — nie nadpisuję. Wzór zapisuję jako workshop.txt.example."
  if [ -n "$CONFIGS_DIR" ] && [ -f "$CONFIGS_DIR/workshop.txt" ]; then
    cp -f "$CONFIGS_DIR/workshop.txt" "${WORKSHOP_FILE}.example"
  else
    printf '%s\n' "$WORKSHOP_IDS_TXT" > "${WORKSHOP_FILE}.example"
  fi
else
  if [ -n "$CONFIGS_DIR" ] && [ -f "$CONFIGS_DIR/workshop.txt" ]; then
    cp -f "$CONFIGS_DIR/workshop.txt" "$WORKSHOP_FILE"
    ok "Lista workshop skopiowana z lokalnego configs and mappool/: $WORKSHOP_FILE"
  else
    printf '%s\n' "$WORKSHOP_IDS_TXT" > "$WORKSHOP_FILE"
  fi
fi
ok "Lista workshop: $WORKSHOP_FILE (${#WORKSHOP_IDS[@]} ID-ków)"

# ── 7b. Pobranie map z Warsztatu Steam przez SteamCMD ────────────────────────
# WAŻNE: serwer dedykowany (headless) NIE pobiera Workshopu sam — silnik loguje
# "Skipping workshop, ISteamUGC is NULL" i pomija cały Warsztat. Dlatego KAŻDE ID
# z WORKSHOP_IDS ściągamy ręcznie przez steamcmd do $QLDS_DIR (z +force_install_dir,
# inaczej wylądowałoby w ~/Steam zamiast w katalogu serwera). Mapy Warsztatu QL są
# pod appid 282440 (gra), NIE 349090 (serwer dedykowany).
: "${WORKSHOP_APPID:=282440}"
if [ "${SKIP_WORKSHOP_DOWNLOAD:-0}" != "1" ]; then
  log "Pobieram mapy z Warsztatu (${#WORKSHOP_IDS[@]} pozycji, appid $WORKSHOP_APPID) — może chwilę potrwać..."
  _ws_ok=0; _ws_fail=0
  for _wid in "${WORKSHOP_IDS[@]}"; do
    if "$STEAMCMD_DIR/steamcmd.sh" +force_install_dir "$QLDS_DIR" +login anonymous \
         +workshop_download_item "$WORKSHOP_APPID" "$_wid" +quit >/dev/null 2>&1; then
      _ws_ok=$((_ws_ok+1))
    else
      _ws_fail=$((_ws_fail+1))
      warn "  Workshop $_wid — nie udało się pobrać (mógł zostać usunięty z Warsztatu)."
    fi
  done
  ok "Warsztat: pobrano $_ws_ok, nieudanych $_ws_fail. Zawartość: $QLDS_DIR/steamapps/workshop/content/$WORKSHOP_APPID/"
else
  warn "Pominięto pobieranie Warsztatu (SKIP_WORKSHOP_DOWNLOAD=1) — mapy Workshop trzeba dociągnąć ręcznie."
fi

# ── 8. Skrypt startowy ───────────────────────────────────────────────────────
START="$QLDS_DIR/start.sh"
cat > "$START" <<EOF
#!/usr/bin/env bash
# Skrypt startowy serwera QL + minqlx (wygenerowany przez instalator)
cd "${QLDS_DIR}" || exit 1
exec ./run_server_x64_minqlx.sh \\
  +set net_strict 1 \\
  +set net_port "${NET_PORT}" \\
  +set fs_homepath "${QLDS_DIR}" \\
  +set zmq_stats_enable 1 \\
  +set zmq_stats_password "${STATS_PASSWORD}" \\
  +set zmq_rcon_enable 1 \\
  +set zmq_rcon_password "${RCON_PASSWORD}" \\
  +set sv_hostname "${SV_HOSTNAME}" \\
  +set qlx_owner "${QLX_OWNER}" \\
  +exec server.cfg
EOF
chmod +x "$START"
ok "Skrypt startowy: $START"

# ── 9. qlds-ctl — zarządzanie serwerami (screen + auto-restart + autostart) ──
# Każda instancja działa w nazwanej sesji screen (qlds-<nazwa>), w której pętla
# nadzorująca podnosi serwer po KAŻDYM zakończeniu procesu (crash, quit).
# TRWAŁE wyłączenie robi tylko 'qlds-ctl stop <nazwa>' (flaga state/<nazwa>.stopped
# — serwer nie wstanie też po reboocie). Autostart po reboocie: wpis @reboot
# w crontabie woła 'qlds-ctl boot' (uruchamia wyłącznie WŁĄCZONE instancje).

# 9a. Instalacja qlds-ctl — źródło jak dla commands.py: lokalny plik obok
# skryptu (klon repo) albo pobranie z GitHub raw (instalacja przez curl | bash).
SRC_QLDSCTL=""
[ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/qlds-ctl" ] && SRC_QLDSCTL="$SCRIPT_DIR/qlds-ctl"
DST_QLDSCTL="$QLDS_DIR/qlds-ctl"
if [ -n "$SRC_QLDSCTL" ]; then
  log "Wgrywam narzędzie qlds-ctl z lokalnego $SRC_QLDSCTL..."
  cp -f "$SRC_QLDSCTL" "$DST_QLDSCTL"
  ok "qlds-ctl wgrany z $SRC_QLDSCTL."
else
  log "Pobieram narzędzie qlds-ctl z $QLDS_CTL_URL..."
  if curl -fsSL "$QLDS_CTL_URL" -o "$DST_QLDSCTL" && [ -s "$DST_QLDSCTL" ]; then
    if grep -q '_supervise' "$DST_QLDSCTL"; then
      ok "qlds-ctl pobrany z GitHub."
    else
      warn "Pobrany qlds-ctl wygląda na uszkodzony (brak '_supervise') — usuwam."
      rm -f "$DST_QLDSCTL"
    fi
  else
    warn "Nie udało się pobrać qlds-ctl z $QLDS_CTL_URL — serwery trzeba będzie uruchamiać ręcznie (bash start-<nazwa>.sh)."
    rm -f "$DST_QLDSCTL" 2>/dev/null || true
  fi
fi
if [ -f "$DST_QLDSCTL" ]; then chmod +x "$DST_QLDSCTL"; fi

# 9b. Katalog stanu qlds-ctl. Przy PIERWSZEJ instalacji wyłączamy generyczny
# serwer 'base' (start.sh), jeśli stawiamy serwery trybów — base dzieli port
# ${NET_PORT} z tdm (odpowiednik dawnej reguły: „qlserver.service zainstalowana,
# ale NIE włączona"). Ponowne uruchomienia NIE nadpisują decyzji użytkownika.
if [ ! -d "$QLDS_DIR/state" ]; then
  mkdir -p "$QLDS_DIR/state"
  if [ "$INSTALL_GAMETYPE_SERVERS" = "1" ]; then
    touch "$QLDS_DIR/state/base.stopped"
    ok "Instancja 'base' (start.sh) domyślnie wyłączona — dzieli port ${NET_PORT} z tdm. Włączysz ją: qlds-ctl start base"
  fi
fi

# 9c. Sprzątanie po POPRZEDNIEJ wersji instalatora: usługi systemd
# qlserver*.service (Restart=on-failure) wskrzeszały serwery po padzie i były
# przyczyną „serwer wstaje sam, mimo że go wyłączyłem". Idempotentne — na
# czystym hoście nic nie robi.
_legacy_removed=0
for _u in /etc/systemd/system/qlserver.service /etc/systemd/system/qlserver-*.service; do
  [ -e "$_u" ] || continue
  warn "Stara usługa systemd z poprzedniej wersji instalatora: $(basename "$_u") — wyłączam i usuwam."
  sudo systemctl disable --now "$(basename "$_u")" 2>/dev/null || true
  sudo rm -f "$_u"
  _legacy_removed=1
done
if [ "$_legacy_removed" = "1" ]; then
  sudo systemctl daemon-reload 2>/dev/null || true
  sudo systemctl reset-failed 2>/dev/null || true
  ok "Usunięto stare usługi qlserver*.service — od teraz serwerami steruje wyłącznie qlds-ctl."
  warn "Stare usługi zostały ZATRZYMANE — po zakończeniu instalacji włącz serwery: ${QLDS_DIR}/qlds-ctl start all"
fi

# 9d. Autostart po reboocie: @reboot w crontabie użytkownika woła 'qlds-ctl boot',
# które uruchamia wyłącznie instancje WŁĄCZONE (bez flagi state/<nazwa>.stopped).
# Idempotentnie — wpis rozpoznawany po markerze '# qlds-ctl-boot'. Uwaga: pod
# 'set -euo pipefail' grep na pustym crontabie wymaga '|| true'.
if [ -x "$DST_QLDSCTL" ] && command -v crontab >/dev/null 2>&1; then
  _cron_line="@reboot ${QLDS_DIR}/qlds-ctl boot >> ${QLDS_DIR}/state/boot.log 2>&1 # qlds-ctl-boot"
  { crontab -l 2>/dev/null | grep -vF '# qlds-ctl-boot' || true; echo "$_cron_line"; } | crontab -
  ok "Wpis @reboot w crontabie ($(whoami)): po restarcie hosta wstaną tylko WŁĄCZONE serwery."
else
  warn "Pominąłem wpis @reboot (brak qlds-ctl lub crontab) — po reboocie serwery trzeba uruchomić ręcznie."
fi

# ── 10. Narzędzie do dodawania kolejnych serwerów QL ─────────────────────────
# Kolejne serwery używają TEJ SAMEJ instalacji QLDS/minqlx, ale mają:
#   • własny port UDP,
#   • własny plik konfiguracji baseq3/<nazwa>.cfg (pierwszy ma server.cfg),
#   • własny skrypt start-<nazwa>.sh — qlds-ctl wykrywa go automatycznie,
#     więc nową instancję od razu obsługuje start/stop/status/console.
# Owner (qlx_owner) oraz hasła rcon/stats dziedziczone są z pierwszego start.sh.
ADD_SCRIPT="$QLDS_DIR/add_server.sh"
log "Tworzę narzędzie dodawania serwerów: $ADD_SCRIPT"
{
  echo '#!/usr/bin/env bash'
  echo '# add_server.sh — dodaje kolejny serwer QL (instancję): tworzy config i skrypt startowy.'
  echo '# Użycie:  ./add_server.sh [nazwa] [port]   (bez argumentów pyta interaktywnie)'
  echo '# Nową instancję uruchamiasz przez:  qlds-ctl start <nazwa>   (wykrywana automatycznie).'
  echo 'set -euo pipefail'
  echo "QLDS_DIR=\"$QLDS_DIR\""
  echo "WHO=\"$(whoami)\""
  cat <<'ADDBODY'
c_ok="\033[1;32m"; c_warn="\033[1;33m"; c_err="\033[1;31m"; c_i="\033[1;36m"; c_e="\033[0m"
log(){ echo -e "${c_i}[*]${c_e} $*"; }; ok(){ echo -e "${c_ok}[OK]${c_e} $*"; }
warn(){ echo -e "${c_warn}[!]${c_e} $*"; }; die(){ echo -e "${c_err}[X]${c_e} $*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Nie uruchamiaj jako root."

# 1) Nazwa instancji (plik konfiguracji i nazwa skryptu startowego)
NAME="${1:-}"
if [ -z "$NAME" ]; then read -rp "Nazwa nowego serwera (np. duel, ffa2): " NAME; fi
SAFE="$(echo "$NAME" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9_-')"
[ -n "$SAFE" ] || die "Nieprawidłowa nazwa (dozwolone: a-z 0-9 _ -)."
[ "$SAFE" != "server" ] || die "Nazwa 'server' jest zarezerwowana dla pierwszego serwera."
[ "$SAFE" != "base" ] || die "Nazwa 'base' jest zarezerwowana w qlds-ctl dla generycznego start.sh."
[ "$SAFE" != "all" ] || die "Nazwa 'all' jest zarezerwowana w qlds-ctl (operacje na wszystkich instancjach)."

CFG="$QLDS_DIR/baseq3/${SAFE}.cfg"
START="$QLDS_DIR/start-${SAFE}.sh"
HOMEPATH="$QLDS_DIR/instances/${SAFE}"
[ ! -f "$CFG" ] || die "Konfiguracja ${SAFE}.cfg już istnieje — wybierz inną nazwę."

# 2) Port UDP (rcon = port+1000, stats = port — muszą być wolne)
PORT="${2:-}"
if [ -z "$PORT" ]; then read -rp "Port UDP nowego serwera (np. 27970): " PORT; fi
[[ "$PORT" =~ ^[0-9]{3,5}$ ]] || die "Port musi byc liczba (3-5 cyfr)."
for f in "$QLDS_DIR"/start.sh "$QLDS_DIR"/start-*.sh; do
  [ -f "$f" ] || continue
  e="$(grep -oE 'net_port "[0-9]+"' "$f" | head -1 | tr -cd '0-9')"
  [ -n "$e" ] || continue
  if [ "$PORT" = "$e" ] || [ "$PORT" = "$((e+1000))" ] || [ "$((PORT+1000))" = "$e" ]; then
    die "Port $PORT koliduje z instancja na porcie $e (rcon = port+1000). Wybierz inny, odlegly o >=10."
  fi
done

# 3) Owner i hasła — dziedziczone z pierwszego start.sh
extract(){ grep -oE "\+set $1 \"[^\"]*\"" "$QLDS_DIR/start.sh" 2>/dev/null | head -1 | sed -E 's/.*"([^"]*)"/\1/'; }
OWNER="$(extract qlx_owner)"; OWNER="${OWNER:-76561198799965164}"
STATS_PW="$(extract zmq_stats_password)"; STATS_PW="${STATS_PW:-zmien_to_haslo_stats}"
RCON_PW="$(extract zmq_rcon_password)"; RCON_PW="${RCON_PW:-zmien_to_haslo_rcon}"

# 4) Konfiguracja — kopiujemy server.cfg jako bazę i zmieniamy sv_hostname
mkdir -p "$HOMEPATH"
if [ -f "$QLDS_DIR/baseq3/server.cfg" ]; then
  cp "$QLDS_DIR/baseq3/server.cfg" "$CFG"
  sed -i -E "s|^([[:space:]]*set[[:space:]]+sv_hostname[[:space:]]+).*|\1\"^3${SAFE}\"|I" "$CFG"
else
  printf 'set sv_hostname "^3%s"\nmap campgrounds ffa\n' "$SAFE" > "$CFG"
fi

# 5) Skrypt startowy instancji
cat > "$START" <<START_EOF
#!/usr/bin/env bash
# Serwer QL '${SAFE}' (minqlx) — wygenerowany przez add_server.sh
cd "$QLDS_DIR" || exit 1
exec ./run_server_x64_minqlx.sh \\
  +set net_strict 1 \\
  +set net_port "$PORT" \\
  +set fs_homepath "$HOMEPATH" \\
  +set zmq_stats_enable 1 \\
  +set zmq_stats_password "$STATS_PW" \\
  +set zmq_rcon_enable 1 \\
  +set zmq_rcon_password "$RCON_PW" \\
  +set sv_hostname "^3$SAFE" \\
  +set qlx_owner "$OWNER" \\
  +exec ${SAFE}.cfg
START_EOF
chmod +x "$START"

# 6) Nowa instancja jest automatycznie widoczna w qlds-ctl (po nazwie skryptu).
ok "Dodano serwer '${SAFE}' (skrypt startowy: ${START})."
echo "  config:    $CFG"
echo "  start:     $START"
echo "  port:      UDP $PORT (rcon TCP $((PORT+1000)))"
echo "  uruchom:   $QLDS_DIR/qlds-ctl start ${SAFE}"
echo "  konsola:   $QLDS_DIR/qlds-ctl console ${SAFE}   (odlacz: Ctrl+A, D)"
echo "  wylacz:    $QLDS_DIR/qlds-ctl stop ${SAFE}   (trwale — nie wstanie po reboocie)"
echo "  firewall:  otworz port UDP $PORT"
echo "  panel:     aby zarzadzac nim w panelu, dodaj wpis do qlpanel/servers.json"
ADDBODY
} > "$ADD_SCRIPT"
chmod +x "$ADD_SCRIPT"
ok "Gotowe: $ADD_SCRIPT — uruchom kiedykolwiek, by dodać kolejny serwer (tworzy config i skrypt startowy)."

# Opcjonalnie: dodaj kolejne serwery już teraz (tylko w trybie interaktywnym).
if [ -t 0 ]; then
  while true; do
    read -rp $'\nDodać teraz kolejny serwer QL? [t/N]: ' _yn || break
    case "${_yn:-}" in
      [tTyY]*) bash "$ADD_SCRIPT" || warn "Nie udało się dodać serwera (patrz wyżej)." ;;
      *) break ;;
    esac
  done
fi

# ── 11. Serwery trybów FFA / TDM / FT (+ dołączone factory) ──────────────────
# Wgrywa plik z własnymi factory (gametypes.factories) oraz trzy gotowe,
# OCZYSZCZONE konfiguracje trybów i skrypty startowe start-<gt>.sh dla każdej
# z nich (instancjami steruje qlds-ctl: start/stop/restart/status/console).
# Porty: tdm=27960, ffa=27961, ft=27962.
if [ "$INSTALL_GAMETYPE_SERVERS" = "1" ]; then
  log "Instaluję serwery trybów FFA/TDM/FT + factory..."

  # 11a. Plik z definicjami factory -> baseq3/scripts/ (czyta go każda instancja).
  mkdir -p "$QLDS_DIR/baseq3/scripts"
  # Źródło definicji factory (jak commands.py/qlds-ctl): lokalny plik obok skryptu
  # (klon repo) albo pobranie z GitHub raw (instalacja przez 'curl | bash').
  DST_FACTORIES="$QLDS_DIR/baseq3/scripts/gametypes.factories"
  SRC_FACTORIES=""
  [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/gametypes-factories" ] && SRC_FACTORIES="$SCRIPT_DIR/gametypes-factories"
  if [ -n "$SRC_FACTORIES" ]; then
    log "Wgrywam factory z lokalnego $SRC_FACTORIES..."
    cp -f "$SRC_FACTORIES" "$DST_FACTORIES"
    ok "Factory wgrane z $SRC_FACTORIES."
  else
    log "Pobieram factory z $GAMETYPES_FACTORIES_URL..."
    if curl -fsSL "$GAMETYPES_FACTORIES_URL" -o "$DST_FACTORIES" && [ -s "$DST_FACTORIES" ]; then
      if grep -q '"basegt"' "$DST_FACTORIES"; then
        ok "Factory pobrane z GitHub: $DST_FACTORIES"
      else
        die "Pobrany plik factory wygląda na uszkodzony (brak \"basegt\") — przerywam."
      fi
    else
      die "Nie udało się pobrać factory z $GAMETYPES_FACTORIES_URL (a nie ma lokalnego pliku gametypes-factories)."
    fi
  fi

  # 11b. Generator pojedynczej konfiguracji trybu.
  #   $1 nazwa  $2 sufiks_hostname  $3 sv_tags  $4 mappool  $5 serverstartup
  #   $6 brand  $7 etykieta_motd
  write_gt_cfg() {
    local gt="$1" suf="$2" tags="$3" pool="$4" startup="$5" brand="$6" motd="$7"
    cat > "$QLDS_DIR/baseq3/${gt}.cfg" <<GTCFG
// ===========================================================================
//  ${gt}.cfg — serwer trybu ${suf} (minqlx). Wygenerowane przez instalator.
//  Lista pluginów oczyszczona: bez irc / patch / specvote.
// ===========================================================================
set sv_hostname            "[TSK] THE SHADOWS KILLERS #${suf}"
set sv_tags                "${tags}"
set g_accessFile           "access.txt"
set sv_maxClients          "22"
set com_hunkMegs           "90"
set sv_floodprotect        "10"
set g_floodprot_maxcount   "10"
set g_floodprot_decay      "1000"
set g_voteFlags            "14190"
set g_allowVote            "1"
set g_voteDelay            "5000"
set g_allowVoteMidGame     "0"
set g_allowSpecVote        "0"
set g_inactivity           "120"
set g_alltalk              "0"
set sv_serverType          "2"
set sv_master              "1"
set sv_fps                 "40"
set sv_idleExit            "600"

// minqlx
set qlx_owner              "${QLX_OWNER}"
set qlx_plugins            "${GT_PLUGINS_LIST}"
set qlx_workshopReferences "${WORKSHOP_IDS_CSV}"
set qlx_database           "Redis"
set qlx_redisAddress       "127.0.0.1"
set qlx_redisDatabase      "0"
set qlx_redisUnixSocket    "0"
set qlx_logs               "5"
set qlx_logsSize           "5000000"

// balance / leaver
set qlx_balanceAuto        "1"
set qlx_balanceUseLocal    "0"
set qlx_balanceMinimumSuggestionDiff "30"
set qlx_leaverBan          "1"
set qlx_leaverBanThreshold "0.75"

// branding
set qlx_motdHeader         "^7==^2 ^1[TSK] ^7==^2 ${motd} ^7==^3 THE SHADOWS KILLERS ^7==^4 GL HF ^7==^2"
set qlx_serverBrandName    "^1[TSK]^7 ${brand}"
set qlx_serverBrandTopField    "^7Running ^2minqlx^7 and ^2qlstats.net^7"
set qlx_serverBrandBottomField "^7Have ^1fun^7, play well, don't ^3whine^7"
set qlx_votepass           "1"

// pula map. UWAGA: qlx_enforceMappool=0 — pula nie jest wymuszana, więc brak
// niestandardowego pliku puli nie blokuje głosowań ani startu. Chcesz wymuszać?
// Ustaw na 1 i utwórz odpowiedni plik puli w baseq3/.
set sv_mapPoolFile         "${pool}"
set qlx_enforceMappool     "0"

set fraglimit              "0"
set timelimit              "0"
set teamsize               "8"
set roundlimit             "10"

// Pierwsza mapa + factory (factory MUSI istnieć, inaczej serwer nie wstanie).
set serverstartup          "${startup}"
GTCFG
    ok "  konfiguracja: baseq3/${gt}.cfg  (startup: ${startup})"
  }

  # 11c. Generator skryptu startowego dla instancji trybu.
  #   Instancją sterujesz przez qlds-ctl:  qlds-ctl start <gt> / stop <gt> ...
  #   $1 nazwa(gt)  $2 port_udp
  write_gt_service() {
    local gt="$1" port="$2"
    local start="$QLDS_DIR/start-${gt}.sh"
    local home="$QLDS_DIR/instances/${gt}"
    mkdir -p "$home"
    cat > "$start" <<STARTEOF
#!/usr/bin/env bash
# Serwer QL trybu '${gt}' (minqlx) — wygenerowany przez instalator.
cd "${QLDS_DIR}" || exit 1
exec ./run_server_x64_minqlx.sh \\
  +set net_strict 1 \\
  +set net_port "${port}" \\
  +set fs_homepath "${home}" \\
  +set zmq_stats_enable 1 \\
  +set zmq_stats_password "${STATS_PASSWORD}" \\
  +set zmq_rcon_enable 1 \\
  +set zmq_rcon_password "${RCON_PASSWORD}" \\
  +set qlx_owner "${QLX_OWNER}" \\
  +exec ${gt}.cfg
STARTEOF
    chmod +x "$start"
    ok "  skrypt startowy: start-${gt}.sh  (port UDP ${port}) — uruchom: qlds-ctl start ${gt}"
  }

  # 11d. Konfiguracje trybów — z lokalnego katalogu configs and mappool/ lub generowane.
  install_gt_cfg() {
    local gt="$1"
    if [ -n "$CONFIGS_DIR" ] && [ -f "$CONFIGS_DIR/${gt}.cfg" ]; then
      cp -f "$CONFIGS_DIR/${gt}.cfg" "$QLDS_DIR/baseq3/${gt}.cfg"
      # Zsynchronizuj qlx_workshopReferences z aktualną listą WORKSHOP_IDS.
      if grep -qE '^[[:space:]]*set[[:space:]]+qlx_workshopReferences' "$QLDS_DIR/baseq3/${gt}.cfg"; then
        sed -i -E "s|^[[:space:]]*set[[:space:]]+qlx_workshopReferences.*|set qlx_workshopReferences \"${WORKSHOP_IDS_CSV}\"|" \
          "$QLDS_DIR/baseq3/${gt}.cfg"
      else
        printf '\nset qlx_workshopReferences "%s"\n' "$WORKSHOP_IDS_CSV" >> "$QLDS_DIR/baseq3/${gt}.cfg"
      fi
      ok "  konfiguracja: baseq3/${gt}.cfg (skopiowana z lokalnego configs and mappool/)"
    else
      case "$gt" in
        tdm) write_gt_cfg "tdm" "TDM" "TDM, minqlx, qlstats.net, ELO, TSK, [TSK]," \
               "mappool_tdm.txt" "map campgrounds mg_tdm_fullclassic" "TEAM DEATHMATCH" "TDM" ;;
        ffa) write_gt_cfg "ffa" "FFA" "FFA, minqlx, qlstats.net, ELO, tsk, [TSK]," \
               "mappool_ffa.txt" "map longestyard ffa" "FREE FOR ALL" "FFA" ;;
        ft)  write_gt_cfg "ft"  "FT"  "FT, FREEZE TAG, minqlx, qlstats.net, ELO, tsk, [TSK]," \
               "mappool_tdm.txt" "map almostlost mg_ft_fullclassic" "FREEZE TAG" "FT" ;;
      esac
    fi
  }

  install_gt_cfg "tdm"
  install_gt_cfg "ffa"
  install_gt_cfg "ft"

  # 11e. Pliki puli map i access.txt z lokalnego katalogu configs and mappool/.
  if [ -n "$CONFIGS_DIR" ]; then
    log "Kopiuję pliki puli map z lokalnego configs and mappool/..."
    _map_count=0
    for _f in "$CONFIGS_DIR"/*.txt; do
      [ -f "$_f" ] || continue
      _fname="$(basename "$_f")"
      [ "$_fname" = "workshop.txt" ] && continue  # workshop.txt trafia do $QLDS_DIR/, nie baseq3/
      cp -f "$_f" "$QLDS_DIR/baseq3/$_fname"
      _map_count=$((_map_count+1))
    done
    if [ "$_map_count" -gt 0 ]; then
      ok "Skopiowano $_map_count plików puli map do baseq3/."
    else
      warn "Brak plików *.txt w katalogu configs and mappool/ — nie skopiowano żadnego."
    fi
  fi

  write_gt_service "tdm" "27960"
  write_gt_service "ffa" "27961"
  write_gt_service "ft"  "27962"

  ok "Serwery trybów gotowe. Uruchom wszystkie włączone jedną komendą:"
  ok "  ${QLDS_DIR}/qlds-ctl start all"
  ok "  (generyczny 'base' jest domyślnie wyłączony — dzieli port ${NET_PORT} z tdm)"
  warn "Otwórz w firewallu porty UDP: 27960 (tdm), 27961 (ffa), 27962 (ft)."
fi

# ── Podsumowanie ─────────────────────────────────────────────────────────────
echo
echo -e "${c_ok}=============================================================${c_end}"
echo -e "${c_ok} INSTALACJA ZAKOŃCZONA${c_end}"
echo -e "${c_ok}=============================================================${c_end}"
cat <<EOF

Serwer:      ${QLDS_DIR}
Config:      ${QLDS_DIR}/baseq3/server.cfg
Sterowanie:  ${QLDS_DIR}/qlds-ctl
Pluginy:     ${QLDS_DIR}/minqlx-plugins
Workshop:    ${QLDS_DIR}/workshop.txt (${#WORKSHOP_IDS[@]} ID-ków, cvar qlx_workshopReferences w cfgach)

ZANIM WYSTARTUJESZ — sprawdź:
  • qlx_owner (SteamID64) w start.sh        -> obecnie: ${QLX_OWNER}
  • hasła rcon/stats w start.sh             -> ZMIEŃ na własne
  • lista pluginów (qlx_plugins) w server.cfg
  • otwórz w firewallu port UDP ${NET_PORT}

STEROWANIE SERWERAMI (qlds-ctl — każdy serwer w osobnej sesji screen):
  ${QLDS_DIR}/qlds-ctl start all       # włącz wszystkie WŁĄCZONE serwery
  ${QLDS_DIR}/qlds-ctl start tdm       # włącz jeden (kasuje flagę stop)
  ${QLDS_DIR}/qlds-ctl stop ffa        # wyłącz TRWALE (nie wstanie po padzie ani reboocie)
  ${QLDS_DIR}/qlds-ctl restart ft      # szybki restart (bez zmiany flagi)
  ${QLDS_DIR}/qlds-ctl status          # co włączone / co faktycznie działa
  ${QLDS_DIR}/qlds-ctl console tdm     # konsola serwera (odłącz: Ctrl+A, D)

  • Po padzie (crash/quit) serwer wstaje SAM — pętla nadzorująca w screenie.
  • Po reboocie hosta wstają automatycznie (cron @reboot) tylko serwery,
    których nie zatrzymałeś — stan „wyłączony" jest trwały (state/<nazwa>.stopped).
  • Generyczny 'base' (start.sh, port ${NET_PORT}) jest domyślnie wyłączony,
    bo dzieli port z tdm. Zdarzenia pętli: ${QLDS_DIR}/state/<nazwa>.log
  • Stare usługi systemd qlserver*.service (auto-wskrzeszanie z poprzedniej
    wersji instalatora) zostały wyłączone i usunięte, jeśli istniały.

TEST: wejdź na serwer i wpisz na czacie:  !myperm
  -> jeśli pokaże poziom uprawnień > 0, jesteś rozpoznany jako właściciel.

KOLEJNE SERWERY: uruchom  ${QLDS_DIR}/add_server.sh  (lub  add_server.sh <nazwa> <port>).
  Każdy kolejny serwer ma własny port, własny plik baseq3/<nazwa>.cfg oraz
  skrypt start-<nazwa>.sh — qlds-ctl wykrywa go automatycznie:
      ${QLDS_DIR}/qlds-ctl start <nazwa>
  Pamiętaj otworzyć w firewallu port UDP każdego z nich.

AKTUALIZACJA: uruchom ten skrypt ponownie (zaktualizuje QLDS, minqlx i pluginy).
EOF
