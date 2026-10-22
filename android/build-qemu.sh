#!/usr/bin/env bash
# Cross-compiles qemu-system-arm for Android arm64 and relinks it as libmain.so (SDL_main entry).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
NDK="${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-}}"
API="${API:-29}"
PREFIX="${PREFIX:-$HERE/prefix}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
TRIPLE=aarch64-linux-android

export PATH="$TOOLCHAIN/bin:$PATH"
export CC="${TRIPLE}${API}-clang" CXX="${TRIPLE}${API}-clang++"
export AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm STRIP=llvm-strip OBJCOPY=llvm-objcopy
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
unset PKG_CONFIG_PATH

# glib etc. are static: make every pkg-config query pull in Libs.private too
cat > "$HERE/pkg-config-static" <<'EOT'
#!/bin/sh
exec pkg-config --static "$@"
EOT
chmod +x "$HERE/pkg-config-static"
export PKG_CONFIG="$HERE/pkg-config-static"

B="$ROOT/build-android"
rm -rf "$B"; mkdir -p "$B"; cd "$B"

"$ROOT/configure" --cross-prefix= --cpu=aarch64 \
  --target-list=arm-softmmu --enable-sdl --disable-pie --disable-werror \
  --disable-docs --disable-tools --disable-guest-agent --disable-capstone --disable-slirp \
  --disable-gtk --disable-opengl --disable-curses --disable-gio --disable-sdl-image \
  --disable-kvm --disable-xen --disable-seccomp --disable-cap-ng --disable-attr \
  --disable-linux-aio --disable-linux-io-uring --disable-libusb --disable-usb-redir \
  --disable-vhost-user --disable-vhost-net --disable-vhost-kernel --disable-fuse \
  --disable-libnfs --disable-gnutls --disable-nettle --disable-gcrypt --disable-bpf \
  --extra-cflags="-fPIC -ftls-model=global-dynamic -I$PREFIX/include" \
  --extra-ldflags="-L$PREFIX/lib -lcrypto -Wl,-z,max-page-size=16384"

ninja -j"$(nproc)" arm-softmmu/qemu-system-arm

# Relink the same objects as a shared library that SDLActivity can dlopen().
python3 - <<'PY'
import subprocess, sys
cmds = subprocess.check_output(['ninja','-t','commands','arm-softmmu/qemu-system-arm']).decode().splitlines()
link = [c for c in cmds if ' -o arm-softmmu/qemu-system-arm ' in c][-1]
link = link.replace(' -no-pie','').replace(' -pie','')
link = link.replace(' -o arm-softmmu/qemu-system-arm ', ' -shared -Wl,-soname,libmain.so -o libmain.so ')
print(link[:400], '...')
sys.exit(subprocess.call(link, shell=True))
PY

mkdir -p "$HERE/out"
cp libmain.so "$HERE/out/libmain.so"
llvm-strip --strip-unneeded "$HERE/out/libmain.so"
cp "$PREFIX/lib/libSDL2.so" "$HERE/out/libSDL2.so"
ls -la "$HERE/out"
readelf -d "$HERE/out/libmain.so" | grep NEEDED || true
llvm-nm -D "$HERE/out/libmain.so" | grep -E " T (SDL_main|main)$" || true
