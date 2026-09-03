#!/bin/bash
# USE WITH SUDO
# build-armv7.sh - Build Node.js for ARMv7 locally
# Equivalent of the GitHub Actions build workflow
#
# Usage:
#   sudo ./build-armv7.sh [branch]
#
# Examples:
#   sudo ./build-armv7.sh          # uses default branch v26.x
#   sudo ./build-armv7.sh v24.x    # builds v24.x
#
# Requirements:
#   - Ubuntu/Debian host (x86_64)
#   - sudo access (for apt-get)
#   - curl, wget, git

set -e

# ── Config ────────────────────────────────────────────────────
NODE_BRANCH="${1:-v26.x}"
TOOLCHAIN_URL="https://github.com/tttapa/toolchains/releases/download/1.3.1/x-tools-armv7-neon-linux-gnueabihf-gcc13.tar.xz"
TOOLCHAIN_DIR="/opt/tttapa-toolchains"
TOOLCHAIN_BIN="$TOOLCHAIN_DIR/armv7-neon-linux-gnueabihf/bin"
WORK_DIR="$(pwd)"
NODE_SRC="$WORK_DIR/node"
RELEASE_DIR="$WORK_DIR/node-release"

start=$(date +%s)

echo "=================================================="
echo " Building Node.js ARMv7 from branch: $NODE_BRANCH"
echo "=================================================="

# ── Step 1: Install build dependencies ────────────────────────
echo -e "\n=== Step 1: Install build dependencies ==="
sudo apt update
sudo apt install -y \
    curl \
    ccache \
    gcc-multilib \
    g++-multilib \
    python3 \
    pkg-config \
    libc6-dev \
    make \
    git

# ── Step 2: Install Rust ───────────────────────────────────────
echo -e "\n=== Step 2: Install Rust ==="
if ! command -v rustup &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "Rust already installed: $(rustc --version)"
fi
source "$HOME/.cargo/env"

# ── Step 3: Install tttapa ARMv7 toolchain ────────────────────
echo -e "\n=== Step 3: Install tttapa ARMv7 toolchain ==="
if [ ! -f "$TOOLCHAIN_BIN/armv7-neon-linux-gnueabihf-g++" ]; then
    wget "$TOOLCHAIN_URL" -O /tmp/tttapa-toolchain.tar.xz
    mkdir -p "$TOOLCHAIN_DIR"
    tar -xf /tmp/tttapa-toolchain.tar.xz \
        --strip-components=1 \
        -C "$TOOLCHAIN_DIR" \
        x-tools/armv7-neon-linux-gnueabihf
    rm /tmp/tttapa-toolchain.tar.xz
else
    echo "Toolchain already installed at $TOOLCHAIN_BIN"
fi
export PATH="$TOOLCHAIN_BIN:$PATH"
"$TOOLCHAIN_BIN/armv7-neon-linux-gnueabihf-g++" --version

# ── Step 4: Configure cross-compilation environment ───────────
echo -e "\n=== Step 4: Configure cross-compilation environment ==="
rustup target add i686-unknown-linux-gnu
rustup target add armv7-unknown-linux-gnueabihf

CROSS_GCC="$TOOLCHAIN_BIN/armv7-neon-linux-gnueabihf-gcc"
CROSS_GXX="$TOOLCHAIN_BIN/armv7-neon-linux-gnueabihf-g++"

export CC="ccache $CROSS_GCC"
export CXX="ccache $CROSS_GXX"
export CC_host="ccache gcc -m32 -msse2"
export CXX_host="ccache g++ -m32 -msse2"
export CC_target="ccache $CROSS_GCC"
export CXX_target="ccache $CROSS_GXX"
export CARGO_TARGET_I686_UNKNOWN_LINUX_GNU_LINKER="gcc"
export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER="$CROSS_GCC"

# ── Step 5: Clone Node.js and checkout release commit ─────────
echo -e "\n=== Step 5: Clone Node.js ($NODE_BRANCH) ==="
if [ ! -d "$NODE_SRC/.git" ]; then
    git clone --branch "$NODE_BRANCH" --single-branch \
        https://github.com/nodejs/node.git "$NODE_SRC"
else
    echo "Node source already cloned at $NODE_SRC"
fi

cd "$NODE_SRC"

COMMIT_ID=$(git log --format="%H %s" | \
    grep -E "[0-9]{4}-[0-9]{2}-[0-9]{2}, Version [0-9]+\.[0-9]+\.[0-9]+" | \
    head -1 | awk '{print $1}')

if [ -z "$COMMIT_ID" ]; then
    echo "ERROR: Could not find any release commit on $NODE_BRANCH"
    echo "=== Recent commits ==="
    git log --oneline -20
    exit 1
fi

COMMIT_MSG=$(git log -1 --format="%s" "$COMMIT_ID")
echo "Found release commit: $COMMIT_MSG"

NODE_VERSION=$(echo "$COMMIT_MSG" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "Node.js version: $NODE_VERSION"

git checkout "$COMMIT_ID"

# ── Step 6a: Patch string-hasher (v25.x+ only) ───────────────────────────────
echo -e "\n=== Step 6: Patch string-hasher (v25.x+ only) ==="
FILE="$NODE_SRC/deps/v8/src/strings/string-hasher.cc"

if [ -f "$NODE_SRC/.sse2-patched" ]; then
    echo "Already patched (found .sse2-patched), skipping"
elif ! grep -q "#ifdef __SSE2__" "$FILE"; then
	echo "WARN: #ifdef __SSE2__ not found in $FILE — not patching"
else
    if ! grep -q "#ifdef __SSE2__" "$FILE"; then
        echo "ERROR: #ifdef __SSE2__ not found in $FILE — file structure may have changed"
        exit 1
    fi

    if ! grep -q "_mm_cvtsi128_si64" "$FILE"; then
        echo "ERROR: No _mm_cvtsi128_si64 found in $FILE — patch may not be needed"
        exit 1
    fi

    COUNT=$(grep -c "#ifdef __SSE2__" "$FILE")
    sed -i 's/#ifdef __SSE2__/#if defined(__SSE2__) \&\& defined(__x86_64__)/g' "$FILE"
    touch "$NODE_SRC/.sse2-patched"
    echo "Patched $COUNT occurrence(s) in $FILE"
fi

# ── Step 6b: Patch V8 int64-lowering Tuple template disambiguation (v24.x only) ───────────────────────────────
echo -e "\n=== Step 6b: Patch V8 int64-lowering Tuple template disambiguation (v24.x only) ==="

FILE="$NODE_SRC/deps/v8/src/compiler/turboshaft/int64-lowering-reducer.h"
if [ -f "$FILE" ] && grep -q "__ Tuple<" "$FILE"; then
	sed -i 's/__ Tuple</__ template Tuple</g' "$FILE"
	echo "Patched Tuple template disambiguation in $FILE"
else
	echo "No unfixed '__ Tuple<' occurrences in $FILE, skipping (v26.x already upstream-fixed)"
fi

# ── Step 7: Configure Node.js ─────────────────────────────────
echo -e "\n=== Step 7: Configure Node.js ==="
cd "$NODE_SRC"
./configure --dest-cpu arm --partly-static

# ── Step 8: Patch node_crates mk files (v26.x+ only) ────────────────────────
echo -e "\n=== Step 8: Patch node_crates mk files (v26.x+ only) ==="
if [ -f "$NODE_SRC/.node-crates-patched" ]; then
    echo "Already patched (found .node-crates-patched), skipping"
else
    node_crates_host_file="${NODE_DIR}/out/deps/crates/node_crates.host.mk"
	if [[ -f "$node_crates_host_file" ]]; then
		sed -i 's|mkdir -p $(obj)/gen//release; cargo rustc --release --frozen --target-dir "$(obj)/gen"|mkdir -p $(obj)/gen/i686-unknown-linux-gnu/release; cargo rustc --release --frozen --target i686-unknown-linux-gnu --target-dir "$(obj)/gen"|g' "$node_crates_host_file"
		sed -i 's|$(obj)/gen//release/libnode_crates.a|$(obj)/gen/i686-unknown-linux-gnu/release/libnode_crates.a|g' "$node_crates_host_file"
	fi
	node_crates_target_file="${NODE_DIR}/out/deps/crates/node_crates.target.mk"
	if [[ -f "$node_crates_target_file" ]]; then
		sed -i 's|mkdir -p $(obj)/gen//release; cargo rustc --release --frozen --target-dir "$(obj)/gen"|mkdir -p $(obj)/gen/armv7-unknown-linux-gnueabihf/release; cargo rustc --release --frozen --target armv7-unknown-linux-gnueabihf --target-dir "$(obj)/gen"|g' "$node_crates_target_file"
		sed -i 's|$(obj)/gen//release/libnode_crates.a|$(obj)/gen/armv7-unknown-linux-gnueabihf/release/libnode_crates.a|g' "$node_crates_target_file"
	fi
	mksnapshot_file="${NODE_DIR}/out/tools/v8_gypfiles/mksnapshot.host.mk"
	if [[ -f "$mksnapshot_file" ]]; then
		sed -i 's|$(obj)/gen//release/libnode_crates.a|$(obj)/gen/i686-unknown-linux-gnu/release/libnode_crates.a|g' "$mksnapshot_file"
	fi

	for f in \
	"${NODE_DIR}/out/node.target.mk" \
	"${NODE_DIR}/out/embedtest.target.mk" \
	"${NODE_DIR}/out/cctest.target.mk" \
	"${NODE_DIR}/out/node_mksnapshot.target.mk"
	do
		if [[ -f "$f" ]]; then
	  		sed -i 's|$(obj)/gen//release/libnode_crates.a|$(obj)/gen/armv7-unknown-linux-gnueabihf/release/libnode_crates.a|g' \
				"$f"
		fi
	done

	if [[ -f "$node_crates_host_file" ]] && [[ -f "$node_crates_target_file" ]]; then
		touch "$NODE_SRC/.node-crates-patched"
		echo "=== Patch verification ==="
		grep "cargo rustc" "$NODE_SRC/out/deps/crates/node_crates.host.mk"
		grep "cargo rustc" "$NODE_SRC/out/deps/crates/node_crates.target.mk"
	fi
fi

# ── Step 9: Build ─────────────────────────────────────────────
echo -e "\n=== Step 9: Build ==="
cd "$NODE_SRC"
make -j$(($(nproc)+1))

# ── Step 10: Package ──────────────────────────────────────────
echo -e "\n=== Step 10: Package ==="
MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
RELEASE_NAME="node-v${NODE_VERSION}-linux-armv7l"

make -C "$NODE_SRC" install DESTDIR="$RELEASE_DIR"

mv "$RELEASE_DIR/usr/local" "$RELEASE_DIR/v${NODE_VERSION}"

cp "$NODE_SRC/README.md"    "$RELEASE_DIR/v${NODE_VERSION}/"
cp "$NODE_SRC/LICENSE"      "$RELEASE_DIR/v${NODE_VERSION}/"
cp "$NODE_SRC/CHANGELOG.md" "$RELEASE_DIR/v${NODE_VERSION}/" 2>/dev/null || \
    cp "$NODE_SRC/doc/changelogs/CHANGELOG_V${MAJOR}.md" \
       "$RELEASE_DIR/v${NODE_VERSION}/CHANGELOG.md" 2>/dev/null || \
    echo "CHANGELOG not found, skipping"

cd "$RELEASE_DIR"
tar -czf "$WORK_DIR/$RELEASE_NAME.tar.gz" "v${NODE_VERSION}/"

echo ""
echo "=================================================="
echo " Done! Output: $WORK_DIR/$RELEASE_NAME.tar.gz"
echo "=================================================="

end=$(date +%s)
elapsed=$((end - start))
printf "Execution time: %02d:%02d:%02d\n" "$((elapsed / 3600))" "$(((elapsed % 3600) / 60))" "$((elapsed % 60))"