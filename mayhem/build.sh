#!/usr/bin/env bash
#
# mayhem/build.sh — build Subsurface's fuzz harnesses (sanitized), their standalone reproducers, and the
# project's CLI test suite binary (normal flags). Runs in the commit image as `mayhem` in /mayhem, offline.
#
# Layout (all under gitignored build*/ dirs, so a `git clean -ffdX` rebuild starts clean):
#   build-fuzz/libdc-src      autoreconf'd copy of the libdivecomputer submodule (the submodule itself stays pristine)
#   build-fuzz/install        sanitized libdivecomputer.a
#   build-fuzz/cli            sanitized Subsurface core library (CLI target, Qt5, headless)
#   build-tests/install       unsanitized libdivecomputer.a
#   build-tests               normal-flags subsurface-cli, which mayhem/test.sh drives
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
# SanCov for the fuzzed code itself (the engine only instruments the TU it is linked into); kept even when SANITIZER_FLAGS is empty.
# -fno-sanitize=function: parse-xml.cpp calls every tag handler through a cast function pointer (match()), which would
# abort every input with a benign -fsanitize=function report; all other UBSan checks stay halting.
FUZZ_COV_FLAGS="-fsanitize=fuzzer-no-link -fno-sanitize=function"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
FUZZ="$SRC/build-fuzz"
TESTS="$SRC/build-tests"
rm -rf "$FUZZ" "$TESTS"
mkdir -p "$FUZZ" "$TESTS"

# libdivecomputer needs its autotools files generated; do that in a copy so the submodule stays clean.
cp -r "$SRC/libdivecomputer" "$FUZZ/libdc-src"
rm -rf "$FUZZ/libdc-src/.git"
(cd "$FUZZ/libdc-src" && autoreconf --install >"$FUZZ/autoreconf.log" 2>&1) || { tail -30 "$FUZZ/autoreconf.log"; exit 1; }

build_libdc() { # <objdir> <prefix> <cflags...>
	local obj="$1" prefix="$2"; shift 2
	mkdir -p "$obj"
	(cd "$obj" \
	 && "$FUZZ/libdc-src/configure" CC="$CC" CFLAGS="$*" --prefix="$prefix" --disable-examples --disable-shared \
	      --enable-static --without-libusb --without-hidapi --without-bluez >"$obj/configure.log" 2>&1 \
	 && make -j"$MAYHEM_JOBS" >"$obj/make.log" 2>&1 && make install >/dev/null 2>&1) \
	|| { tail -30 "$obj"/configure.log "$obj"/make.log 2>/dev/null; exit 1; }
}

# 1) Sanitized project: libdivecomputer + Subsurface core library, with DWARF 3 symbols.
build_libdc "$FUZZ/libdc-obj" "$FUZZ/install" $SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV_FLAGS -O1
cmake -S "$SRC" -B "$FUZZ/cli" -G Ninja -DSUBSURFACE_TARGET_EXECUTABLE=CLI -DCMAKE_BUILD_TYPE= \
	-DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
	-DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV_FLAGS -O1" -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV_FLAGS -O1" \
	-DCMAKE_EXE_LINKER_FLAGS="$SANITIZER_FLAGS $FUZZ_COV_FLAGS" -DLIBGIT2_DYNAMIC=ON \
	-DLIBDIVECOMPUTER_INCLUDE_DIR="$FUZZ/install/include" \
	-DLIBDIVECOMPUTER_LIBRARIES="$FUZZ/install/lib/libdivecomputer.a" >"$FUZZ/cmake.log" 2>&1 \
	|| { tail -30 "$FUZZ/cmake.log"; exit 1; }
cmake --build "$FUZZ/cli" -j"$MAYHEM_JOBS" --target subsurface_corelib >"$FUZZ/build.log" 2>&1 \
	|| { grep -E "error|FAILED" "$FUZZ/build.log" | head -20; exit 1; }

# 2) Harnesses: each linked once against the fuzzing engine and once against the standalone driver.
QT_CFLAGS=$(pkg-config --cflags Qt5Core Qt5Gui)
RCC="$(pkg-config --variable=host_bins Qt5Core)/rcc"
"$RCC" --name subsurface "$SRC/subsurface.qrc" -o "$FUZZ/qrc_subsurface.cpp"
HCXXFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV_FLAGS -O1 -fPIC -std=gnu++20 -DSUBSURFACE_CLI -DSUBSURFACE_SOURCE=\"$SRC\" \
	-I$SRC -I$FUZZ/cli -I$FUZZ/install/include -I/usr/include/libxml2 $QT_CFLAGS"
# shellcheck disable=SC2086
$CXX $HCXXFLAGS -c "$FUZZ/qrc_subsurface.cpp" -o "$FUZZ/qrc_subsurface.o"
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$FUZZ/lsan_off.o"
# shellcheck disable=SC2086
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$FUZZ/standalone_main.o"

LIBS="-Wl,--start-group $FUZZ/cli/core/libsubsurface_corelib.a $FUZZ/install/lib/libdivecomputer.a -Wl,--end-group \
	-lQt5Concurrent -lQt5Network -lQt5Widgets -lQt5Gui -lQt5Core -lgit2 -lssh2 -lcurl -lssl -lcrypto -lxslt -lxml2 -lzip -lsqlite3 -lz -lpthread"

TARGETS="fuzz_xml fuzz_fit fuzz_divesoft fuzz_ostctools fuzz_asd \
fuzz_suunto_json fuzz_csv fuzz_datatrak fuzz_libdc_parser"
for t in $TARGETS; do
	# shellcheck disable=SC2086
	$CXX $HCXXFLAGS -c "$SRC/mayhem/$t.cpp" -o "$FUZZ/$t.o"
	# shellcheck disable=SC2086
	$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FUZZ/$t.o" "$FUZZ/lsan_off.o" "$FUZZ/qrc_subsurface.o" $LIBS -o "$SRC/$t"
	# shellcheck disable=SC2086
	$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV_FLAGS "$FUZZ/$t.o" "$FUZZ/standalone_main.o" "$FUZZ/lsan_off.o" "$FUZZ/qrc_subsurface.o" $LIBS -o "$SRC/$t-standalone"
done

# fuzz_cochran is a file-input target with its own main() (see mayhem/fuzz_cochran.cpp): no libFuzzer, no -standalone twin.
# shellcheck disable=SC2086
$CXX $HCXXFLAGS -c "$SRC/mayhem/fuzz_cochran.cpp" -o "$FUZZ/fuzz_cochran.o"
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $FUZZ_COV_FLAGS "$FUZZ/fuzz_cochran.o" "$FUZZ/lsan_off.o" "$FUZZ/qrc_subsurface.o" $LIBS -o "$SRC/fuzz_cochran"

# 3) Test suite binary with the project's NORMAL flags and an unsanitized libdivecomputer.
build_libdc "$TESTS/libdc-obj" "$TESTS/install" -O2 $COVERAGE_FLAGS
cmake -S "$SRC" -B "$TESTS/cli" -G Ninja -DSUBSURFACE_TARGET_EXECUTABLE=CLI -DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
	-DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" -DCMAKE_EXE_LINKER_FLAGS="$COVERAGE_FLAGS" \
	-DLIBGIT2_DYNAMIC=ON -DLIBDIVECOMPUTER_INCLUDE_DIR="$TESTS/install/include" \
	-DLIBDIVECOMPUTER_LIBRARIES="$TESTS/install/lib/libdivecomputer.a" >"$TESTS/cmake.log" 2>&1 \
	|| { tail -30 "$TESTS/cmake.log"; exit 1; }
cmake --build "$TESTS/cli" -j"$MAYHEM_JOBS" --target subsurface-cli >"$TESTS/build.log" 2>&1 \
	|| { grep -E "error|FAILED|undefined" "$TESTS/build.log" | head -20; exit 1; }
