# Node.js for armv7

Since node v24+ is not officially supported anymore on armv7, I decided to try to make it myself.

Building requires two patches:
- `deps/v8/src/strings/string-hasher.cc` — fixes an x86_64-only SSE2 intrinsic that breaks 32-bit host compilation
- `out/deps/crates/node_crates.*.mk` — fixes incorrect shared output paths for host/target Rust crates in cross-compile builds

## Download
Go to [releases](https://github.com/4meters/node-for-armv7/releases)

Binaries are built with `--partly-static`, because many systems still use gcc/g++12 libs.

### Install with nvm

```bash
# Replace v26.7.0 with the version you downloaded
tar -xzf node-v26.7.0-linux-armv7l.tar.gz -C "$NVM_DIR/versions/node/"
nvm use v26.7.0
```

## How to build
Run:


```bash
chmod +x ./build-for-armv7.sh

# Build latest release on default branch (v26.x)
sudo ./build-for-armv7.sh

# Build a specific branch
sudo ./build-for-armv7.sh v24.x
```


It's fully automated script, required packages are installed automatically.

Output file is `node-vX.Y.Z-linux-armv7l.tar.gz` archive in the current directory

## Additional info
See [nodejs/node issue #61794](https://github.com/nodejs/node/issues/61794#issuecomment-5302695402)