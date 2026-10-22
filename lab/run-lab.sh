#!/usr/bin/env bash
# Headless boot of the iPod touch 2G machine; collects logs in lab/out/.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/lab/config.env"
OUT="$ROOT/lab/out"; WORK="$ROOT/lab/work"
mkdir -p "$OUT" "$WORK"
QEMU="$ROOT/build-lab/qemu-system-arm"

case "$MODE" in
  baseline)
    REL=https://github.com/devos50/qemu-ios/releases/download/n72ap_v1
    for f in bootrom_240_4 nor_n72ap.bin nand_n72ap.zip; do
      [ -f "$WORK/$f" ] || curl -fL --retry 5 -o "$WORK/$f" "$REL/$f"
    done
    (cd "$WORK" && rm -rf nand && unzip -q -o nand_n72ap.zip)
    BOOTROM="$WORK/bootrom_240_4"; NOR="$WORK/nor_n72ap.bin"; NAND="$WORK/nand"
    ;;
  *) echo "unknown MODE $MODE"; exit 2;;
esac

echo "== running $MODE for ${SECONDS_TO_RUN}s" | tee "$OUT/summary.txt"
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout --signal=KILL "$SECONDS_TO_RUN" "$QEMU" \
  -M "iPod-Touch,bootrom=$BOOTROM,nand=$NAND,nor=$NOR" -cpu max -m 2G \
  -display sdl -monitor none -serial "file:$OUT/serial.log" \
  -d unimp -D "$OUT/unimp.log" > "$OUT/stdout.log" 2> "$OUT/stderr.log"
echo "qemu exit code: $?" | tee -a "$OUT/summary.txt"
{
  echo "--- sizes"; wc -c "$OUT"/*.log
  echo "--- serial.log (last 60 lines)"; tail -n 60 "$OUT/serial.log" 2>/dev/null
  echo "--- most frequent unimplemented accesses"
  sed -E 's/0x[0-9a-fA-F]+/N/g' "$OUT/unimp.log" 2>/dev/null | sort | uniq -c | sort -rn | head -25
} >> "$OUT/summary.txt"
