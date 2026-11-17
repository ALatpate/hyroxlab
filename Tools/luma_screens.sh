#!/bin/bash
# Luma screenshot harness. Boots a simulator, installs a simulator build, launches it once per line
# of a list file, and writes one JPEG per line into <outdir>.
#
#   Tools/luma_screens.sh <path/to/App.app> <outdir> <listfile> [extra launch args…]
#
# Each list line is  name|screen|scrollY|data|waitSeconds  (later fields optional). The app reads
# -lumaScreen / -lumaScroll / -lumaData from the argument domain (LumaLaunch.fromArguments()).
# waitSeconds is only used for a line with no screen name; a named screen is photographed when the
# app says it is ready.
set -uo pipefail
APP="$1"; OUT="$2"; LIST="$3"; shift 3
EXTRA=("$@")
mkdir -p "$OUT"
BID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = json.load(sys.stdin)["devices"]
# The owner carries a 6.1-inch phone (390x844 pt), so prefer simulators with that canvas.
want = ["iPhone 16e", "iPhone 17e", "iPhone 14", "iPhone 13", "iPhone 16", "iPhone 17", "iPhone 15"]
found = {}
for rt, items in devs.items():
    if "iOS" not in rt: continue
    for d in items:
        found.setdefault(d["name"], []).append((rt, d["udid"]))
for name in want:
    if name in found:
        print(sorted(found[name])[-1][1]); sys.exit(0)
for name, lst in sorted(found.items()):
    if name.startswith("iPhone"):
        print(sorted(lst)[-1][1]); sys.exit(0)
')
if [ -z "$UDID" ]; then echo "::error::no iPhone simulator available"; xcrun simctl list devices available; exit 1; fi
echo "simulator: $(xcrun simctl list devices | grep "$UDID" | head -1 | sed 's/ (.*//' | xargs)  bundle: $BID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 --dataNetwork wifi 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant all "$BID" 2>/dev/null || true

# Warm-up launch: first launch pays dyld + asset costs and (in the full app) seeds demo data.
xcrun simctl launch "$UDID" "$BID" ${EXTRA[@]+"${EXTRA[@]}"} -lumaScreen today >/dev/null 2>&1 || true
sleep 12
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true

# The app says when a screen is ready to photograph: once its data is loaded and the screen it was
# launched on has had time to draw, it writes a file into its temporary directory (LumaRootView, only
# when launched on a named screen). Waiting for that file takes as long as the machine needs and no
# longer, where a fixed wait is too short on a slow simulator and wasted on a fast one.
DATA=$(xcrun simctl get_app_container "$UDID" "$BID" data 2>/dev/null || true)
READY="$DATA/tmp/luma-ready"

n=0
late=0
missed=0
while IFS='|' read -r name screen scroll data wait || [ -n "${name:-}" ]; do
  case "${name:-}" in ''|\#*) continue;; esac
  xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
  [ -n "$DATA" ] && rm -f "$READY"
  xcrun simctl launch "$UDID" "$BID" ${EXTRA[@]+"${EXTRA[@]}"} -lumaScreen "$screen" -lumaScroll "${scroll:-0}" -lumaData "${data:-demo}" >/dev/null 2>&1 \
    || { echo "launch failed: $name"; continue; }
  # Three screens in a row that never said so, and the signal is taken to be broken: the rest get a
  # fixed wait, so a run costs minutes more and not the job's whole time limit.
  if [ -n "$DATA" ] && [ -n "${screen:-}" ] && [ "$missed" -lt 3 ]; then
    for _ in $(seq 1 180); do [ -f "$READY" ] && break; sleep 0.5; done
    if [ -f "$READY" ]; then sleep 2; missed=0; else late=$((late+1)); missed=$((missed+1)); echo "not ready in time: $name"; fi
  elif [ -n "${screen:-}" ]; then
    late=$((late+1)); sleep 10
  else
    sleep "${wait:-4}"
  fi
  if xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1; then
    sips -s format jpeg -s formatOptions 80 -Z 1100 "$OUT/$name.png" --out "$OUT/$name.jpg" >/dev/null 2>&1 && rm -f "$OUT/$name.png"
    n=$((n+1))
  else
    echo "screenshot failed: $name"
  fi
done < "$LIST"
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
echo "captured $n screens"
[ "$late" -gt 0 ] && echo "$late of them were taken without the app saying it was ready"
# A crash shows up as a home-screen capture; surface the newest crash report so the log explains it.
for f in $(ls -t ~/Library/Logs/DiagnosticReports/*.ips 2>/dev/null | head -2); do
  echo "--- crash report: $f"; python3 - "$f" <<'PY' || head -40 "$f"
import json, sys
raw = open(sys.argv[1]).read()
head, _, body = raw.partition("\n")
try:
    h = json.loads(head); b = json.loads(body)
    print(h.get("app_name"), h.get("bug_type"), b.get("exception", {}))
    print("termination:", b.get("termination", {}))
    t = [x for x in b.get("threads", []) if x.get("triggered")]
    imgs = b.get("usedImages", [])
    for fr in (t[0]["frames"][:22] if t else []):
        print("  ", imgs[fr["imageIndex"]].get("name", "?") if fr.get("imageIndex") is not None and fr["imageIndex"] < len(imgs) else "?", fr.get("symbol", ""), fr.get("sourceFile", ""), fr.get("sourceLine", ""))
    for k in ("asi", "lastExceptionBacktrace"):
        if k in b: print(k, str(b[k])[:900])
except Exception as e:
    print("unparsed", e); print(raw[:1500])
PY
done
exit 0
