#!/usr/bin/env bash
# Start the Magister backend (serve) and the GTK frontend; stop the backend on exit.
#
#   ./run.sh                      asks for username (and password when needed)
#   MAGISTER_USER=622318 ./run.sh
#
# Settings (environment variables, all optional):
#   MAGISTER_BIN       path to the backend   (default ~/Documents/publish/Magister2)
#   MAGISTER_SCHOOL    school name           (default "RSG Pantarijn")
#   MAGISTER_USER      username / leerlingnummer
#   MAGISTER_PASSWORD  password (otherwise asked, only when no recent saved session)
#   MAGISTER_PORT      port                  (default 5075)
#   MAGISTER_ARGS_SEP  optional separator before <school> (default none; use "--" only with "dotnet run")
set -u
cd "$(dirname "$0")"

BIN="${MAGISTER_BIN:-$HOME/Documents/C-sharp/Magister2/bin/Debug/net10.0/Magister2}"
SCHOOL="${MAGISTER_SCHOOL:-RSG Pantarijn}"
USER_NAME="${MAGISTER_USER:-}"
PORT="${MAGISTER_PORT:-5075}"
SEP="${MAGISTER_ARGS_SEP:-}"
GUI="${MAGISTER_GUI:-./magister-gtk}"
SESSION="${MAGISTER_SESSION_FILE:-$HOME/.config/magister/session.json}"
LOG="${TMPDIR:-/tmp}/magister-serve.log"

[ -x "$BIN" ] || { echo "backend not found or not executable: $BIN (set MAGISTER_BIN)"; exit 1; }
command -v curl >/dev/null || { echo "curl is required"; exit 1; }

# build the GUI if needed
if [ ! -x "$GUI" ]; then
    echo "building the GUI..."
    bash ./build.sh || exit 1
fi

if [ -z "$USER_NAME" ]; then
    read -r -p "Magister username: " USER_NAME
fi

# The backend logs in again by itself when its session expires (~50 min), and it can only
# do that with the password, because it has no terminal. So ask for it unless a session
# younger than ~45 min exists, in which case Enter skips it (you may be asked again later).
FRESH=0
find "$SESSION" -mmin -45 2>/dev/null | grep -q . && FRESH=1
if [ -z "${MAGISTER_PASSWORD:-}" ]; then
    while :; do
        if [ "$FRESH" = 1 ]; then
            read -r -s -p "Magister password (Enter = use saved session): " MAGISTER_PASSWORD
        else
            read -r -s -p "Magister password: " MAGISTER_PASSWORD
        fi
        echo
        [ -n "$MAGISTER_PASSWORD" ] || [ "$FRESH" = 1 ] && break
    done
fi
[ -n "${MAGISTER_PASSWORD:-}" ] || unset MAGISTER_PASSWORD   # an empty value would count as the password
export MAGISTER_PASSWORD

# random key shared by backend and GUI (never written to disk)
if [ -z "${MAGISTER_API_KEY:-}" ]; then
    MAGISTER_API_KEY="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
export MAGISTER_API_KEY
export MAGISTER_URL="http://127.0.0.1:$PORT"

ARGS=()
[ -n "$SEP" ] && ARGS+=("$SEP")
ARGS+=("$SCHOOL" "$USER_NAME" serve "$PORT")

echo "starting backend (log: $LOG)..."
"$BIN" "${ARGS[@]}" </dev/null >"$LOG" 2>&1 &
BACKEND=$!

cleanup() {
    kill "$BACKEND" 2>/dev/null
    wait "$BACKEND" 2>/dev/null
}
trap cleanup EXIT INT TERM

# wait until the backend answers (login can take a few seconds)
for _ in $(seq 1 60); do
    if ! kill -0 "$BACKEND" 2>/dev/null; then
        echo "backend stopped early:"
        tail -n 15 "$LOG"
        exit 1
    fi
    if curl -fs "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
        echo "backend ready on port $PORT"
        "$GUI"
        exit $?
    fi
    sleep 1
done

echo "backend did not become ready within 60s:"
tail -n 15 "$LOG"
exit 1