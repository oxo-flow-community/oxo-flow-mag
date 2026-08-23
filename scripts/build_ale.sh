#!/usr/bin/env bash
# Build the ALE C binaries into the `ale` conda env.
#
# The upstream bioconda pin (ale=20180904) is uninstallable — its pymix
# dependency chain requires matplotlib <1.5 which no channel carries.
# The rules only invoke ALE's own C binaries (`ALE --metagenome`), so
# this script compiles the pinned upstream source tag into the env
# created from envs/ale.yaml. One-time, idempotent.
#
# Usage: conda env create -f envs/ale.yaml  (or let oxo-flow create it)
#        bash scripts/build_ale.sh
set -euo pipefail

ALE_TAG="20180904"
ALE_SHA="123457834c173f10710a0b4c2fcefd8c6fa62af11f6ad311f199c242c49e8f68"  # upstream release tarball
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CONDA_BIN="${CONDA_PREFIX:-$HOME/miniforge3/envs/ale}"

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
cd "$build_dir"

curl -fsSL -o ale.tar.gz "https://github.com/sc932/ALE/archive/${ALE_TAG}.tar.gz" ||
    curl -fsSL -o ale.tar.gz "https://ghfast.top/https://github.com/sc932/ALE/archive/${ALE_TAG}.tar.gz"
echo "${ALE_SHA}  ale.tar.gz" | sha256sum -c -
tar -xzf ale.tar.gz --strip-components=1

# Modern GCC (>=14) hard-errors on this 2018-era code: implicit declarations
# (strcmp/close/tdestroy/bam_aux_drop_other) and K&R-style pointer usage.
# Force-include the standard headers the source forgot and downgrade only
# those specific warnings (see the oxo-flow failure catalog, "ale build").
sed -i "s/^CFLAGS := -g -O3$/CFLAGS := -g -O3 -D_GNU_SOURCE -Wno-incompatible-pointer-types -Wno-int-conversion -Wno-implicit-function-declaration -include string.h -include stdlib.h -include unistd.h -include search.h/" src/makefile

make

install -m 0755 src/ALE "$CONDA_BIN/bin/ALE"
install -m 0755 src/synthReadGen "$CONDA_BIN/bin/synthReadGen"
for f in src/*.py; do
    sed 's:/usr/bin/python:/usr/bin/env python:' "$f" > "$CONDA_BIN/bin/$(basename "$f")"
    chmod a+x "$CONDA_BIN/bin/$(basename "$f")"
done

echo "ALE built into $CONDA_BIN/bin: $(command -v "$CONDA_BIN/bin/ALE")"
