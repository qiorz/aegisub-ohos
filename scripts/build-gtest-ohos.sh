#!/usr/bin/env bash
# 构建 GoogleTest / GoogleMock 静态库（OHOS aarch64）。
# Debian bookworm 只有 1.12.1；Aegisub 的测试要求已相应放宽到 >=1.12.0。
set -euo pipefail

WS=/root/opt/dsh/workspace-aegisub
source "$WS/scripts/env.sh"

SRC="$WS/build/deps/src/googletest-release-1.12.1"
PREFIX="$WS/build/deps/prefix"
TMP="$WS/build/deps/obj/gtest"

[ -d "$SRC" ] || { echo "缺少 $SRC，先运行 scripts/fetch-deps-ohos.sh"; exit 1; }
mkdir -p "$TMP" "$PREFIX/include" "$PREFIX/lib/pkgconfig"

cd "$SRC"
CXXFLAGS="--target=aarch64-linux-ohos --sysroot=$OHOS_SYSROOT -std=c++17 -O2 -fPIC"
$OHOS_CXX $CXXFLAGS -Igoogletest/include -Igoogletest \
    -c googletest/src/gtest-all.cc -o "$TMP/gtest-all.o"
$OHOS_CXX $CXXFLAGS -Igoogletest/include -Igoogletest \
    -c googletest/src/gtest_main.cc -o "$TMP/gtest_main.o"
$OHOS_CXX $CXXFLAGS -Igooglemock/include -Igooglemock -Igoogletest/include -Igoogletest \
    -c googlemock/src/gmock-all.cc -o "$TMP/gmock-all.o"
$OHOS_CXX $CXXFLAGS -Igooglemock/include -Igooglemock -Igoogletest/include -Igoogletest \
    -c googlemock/src/gmock_main.cc -o "$TMP/gmock_main.o"

$OHOS_AR rcs "$PREFIX/lib/libgtest.a" "$TMP/gtest-all.o"
$OHOS_AR rcs "$PREFIX/lib/libgtest_main.a" "$TMP/gtest_main.o"
$OHOS_AR rcs "$PREFIX/lib/libgmock.a" "$TMP/gmock-all.o"
$OHOS_AR rcs "$PREFIX/lib/libgmock_main.a" "$TMP/gmock_main.o"

rm -rf "$PREFIX/include/gtest" "$PREFIX/include/gmock"
cp -a googletest/include/gtest "$PREFIX/include/"
cp -a googlemock/include/gmock "$PREFIX/include/"

for pair in "gtest:gtest" "gtest_main:gtest_main" "gmock:gmock" "gmock_main:gmock_main"; do
    name=${pair%%:*}; lib=${pair##*:}
    cat > "$PREFIX/lib/pkgconfig/$name.pc" <<EOF
prefix=$PREFIX
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: $name
Description: GoogleTest (OHOS static build)
Version: 1.12.1
Libs: -L\${libdir} -l$lib
Cflags: -I\${includedir}
EOF
done

ls -lh "$PREFIX/lib"/libg*.a
