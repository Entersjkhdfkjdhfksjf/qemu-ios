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

for RUN in 1 2; do
  echo "== boot $RUN ($MODE) for ${SECONDS_TO_RUN}s" | tee -a "$OUT/summary.txt"
  SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy timeout --signal=KILL "$SECONDS_TO_RUN" "$QEMU" \
    -M "iPod-Touch,bootrom=$BOOTROM,nand=$NAND,nor=$NOR" -cpu max -m 2G \
    -display sdl -monitor none -serial "file:$OUT/serial$RUN.log" \
    > "$OUT/stdout$RUN.log" 2> "$OUT/stderr$RUN.log"
  echo "qemu exit code: $?" | tee -a "$OUT/summary.txt"
  {
    echo "--- boot $RUN: sizes"; wc -c "$OUT"/*$RUN.log
    echo "--- boot $RUN: panic/userland markers"
    grep -a -n -i -E "kernel abort|Debugger message|Waiting for remote|pid [0-9]+: (launchd|SpringBoard)|SpringBoard" "$OUT/serial$RUN.log" | cut -c1-140 | head -12
  } >> "$OUT/summary.txt"
done
