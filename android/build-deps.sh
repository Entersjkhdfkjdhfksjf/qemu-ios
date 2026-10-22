#!/usr/bin/env bash
# Cross-builds everything QEMU needs for Android arm64 into $PREFIX (static libs, except SDL2).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NDK="${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-}}"
[ -d "$NDK" ] || { echo "NDK not found"; exit 1; }
API="${API:-29}"
PREFIX="${PREFIX:-$HERE/prefix}"
WORK="${WORK:-$HERE/work}"
JOBS="$(nproc)"

ZLIB_VER=1.3.1
FFI_VER=3.4.6
PCRE2_VER=10.42
GLIB_VER=2.78.6
PIXMAN_VER=0.43.4
OPENSSL_VER=3.0.15
SDL_VER=2.30.9

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
TRIPLE=aarch64-linux-android
export PATH="$TOOLCHAIN/bin:$PATH"
export CC="${TRIPLE}${API}-clang"
export CXX="${TRIPLE}${API}-clang++"
export AR=llvm-ar RANLIB=llvm-ranlib NM=llvm-nm STRIP=llvm-strip
export CFLAGS="-fPIC -O2"
export CXXFLAGS="-fPIC -O2"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig"
unset PKG_CONFIG_PATH

mkdir -p "$PREFIX" "$WORK/dl" "$WORK/src"

fetch() { # url -> extracted into $WORK/src
  local url="$1" f="$WORK/dl/$(basename "$1")"
  [ -f "$f" ] || curl -fL --retry 5 --retry-delay 3 -o "$f" "$url"
  tar -xf "$f" -C "$WORK/src"
}
done_() { [ -f "$PREFIX/.done-$1" ]; }
mark()  { touch "$PREFIX/.done-$1"; }

CROSS="$HERE/cross-android-arm64.ini"
cat > "$CROSS" <<EOT
[binaries]
c = '$TOOLCHAIN/bin/${TRIPLE}${API}-clang'
cpp = '$TOOLCHAIN/bin/${TRIPLE}${API}-clang++'
ar = '$TOOLCHAIN/bin/llvm-ar'
ranlib = '$TOOLCHAIN/bin/llvm-ranlib'
strip = '$TOOLCHAIN/bin/llvm-strip'
nm = '$TOOLCHAIN/bin/llvm-nm'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['-fPIC', '-I$PREFIX/include']
cpp_args = ['-fPIC', '-I$PREFIX/include']
c_link_args = ['-L$PREFIX/lib']
cpp_link_args = ['-L$PREFIX/lib']

[properties]
needs_exe_wrapper = true
pkg_config_libdir = ['$PREFIX/lib/pkgconfig', '$PREFIX/share/pkgconfig']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOT

if ! done_zlib; then
  fetch "https://github.com/madler/zlib/releases/download/v$ZLIB_VER/zlib-$ZLIB_VER.tar.gz"
  ( cd "$WORK/src/zlib-$ZLIB_VER" && ./configure --prefix="$PREFIX" --static && make -j"$JOBS" && make install )
  mark zlib
fi

if ! done_ffi; then
  fetch "https://github.com/libffi/libffi/releases/download/v$FFI_VER/libffi-$FFI_VER.tar.gz"
  ( cd "$WORK/src/libffi-$FFI_VER" && ./configure --host=$TRIPLE --prefix="$PREFIX" --libdir="$PREFIX/lib" \
      --disable-shared --enable-static --with-pic --disable-docs --disable-multi-os-directory \
    && make -j"$JOBS" && make install )
  mark ffi
fi

if ! done_pcre2; then
  fetch "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$PCRE2_VER/pcre2-$PCRE2_VER.tar.gz"
  ( cd "$WORK/src/pcre2-$PCRE2_VER" && ./configure --host=$TRIPLE --prefix="$PREFIX" --libdir="$PREFIX/lib" \
      --disable-shared --enable-static --with-pic --disable-jit \
    && make -j"$JOBS" && make install )
  mark pcre2
fi

if ! done_glib; then
  fetch "https://download.gnome.org/sources/glib/${GLIB_VER%.*}/glib-$GLIB_VER.tar.xz"
  ( cd "$WORK/src/glib-$GLIB_VER" && rm -rf _b && meson setup _b --cross-file "$CROSS" \
      --prefix "$PREFIX" --libdir lib --buildtype release --default-library static \
      -Dtests=false -Dnls=disabled -Dintrospection=disabled -Dman-pages=disabled \
      -Ddocumentation=false -Dlibmount=disabled -Dselinux=disabled -Dxattr=false \
      -Dsysprof=disabled -Dlibelf=disabled \
    && ninja -C _b -j"$JOBS" && ninja -C _b install )
  mark glib
fi

if ! done_pixman; then
  fetch "https://cairographics.org/releases/pixman-$PIXMAN_VER.tar.gz"
  ( cd "$WORK/src/pixman-$PIXMAN_VER" && rm -rf _b && meson setup _b --cross-file "$CROSS" \
      --prefix "$PREFIX" --libdir lib --buildtype release --default-library static \
      -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled -Dopenmp=disabled \
    && ninja -C _b -j"$JOBS" && ninja -C _b install )
  mark pixman
fi

if ! done_openssl; then
  fetch "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/openssl-$OPENSSL_VER.tar.gz"
  ( cd "$WORK/src/openssl-$OPENSSL_VER" && export ANDROID_NDK_ROOT="$NDK" \
    && env -u CC -u CXX -u AR -u RANLIB -u NM -u STRIP -u CFLAGS -u CXXFLAGS \
       ./Configure android-arm64 -D__ANDROID_API__=$API no-shared no-tests no-apps no-docs \
         --prefix="$PREFIX" --openssldir="$PREFIX/ssl" --libdir=lib -fPIC \
    && env -u CC -u CXX -u AR -u RANLIB -u NM -u STRIP -u CFLAGS -u CXXFLAGS make -j"$JOBS" build_libs \
    && env -u CC -u CXX -u AR -u RANLIB -u NM -u STRIP -u CFLAGS -u CXXFLAGS make install_dev )
  mark openssl
fi

if ! done_sdl; then
  fetch "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VER/SDL2-$SDL_VER.tar.gz"
  ( cd "$WORK/src/SDL2-$SDL_VER" \
    && env -u CC -u CXX -u AR -u RANLIB -u NM -u STRIP -u CFLAGS -u CXXFLAGS \
       cmake -S . -B _b -G Ninja -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
         -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API \
         -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
         -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF \
         -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" \
    && cmake --build _b -j"$JOBS" && cmake --install _b )
  # Java side of SDL (must match the native version) for the Gradle project
  mkdir -p "$PREFIX/sdl-java" && cp -r "$WORK/src/SDL2-$SDL_VER/android-project/app/src/main/java/org" "$PREFIX/sdl-java/"
  mark sdl
fi

echo "== dependencies ready in $PREFIX =="
ls "$PREFIX/lib" | head -50
