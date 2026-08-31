# Node.js for armv7

Since node v24+ is not officially supported anymore on armv7, I decided to try to make it myself.

Various patches are required depending on whether the major version is v24 or v26.

- For **v26.x.x**, building requires two patches:
    - `deps/v8/src/strings/string-hasher.cc` — fixes an x86_64-only SSE2 intrinsic that breaks 32-bit host compilation
    - `out/deps/crates/node_crates.*.mk` — fixes incorrect shared output paths for host/target Rust crates in cross-compile builds

- For **v24.x** 
    - `deps/v8/src/compiler/turboshaft/int64-lowering-reducer.h` — adds the missing `template` disambiguator to `__ Tuple<Word32, Word32>(...)` in `LowerClz`/`LowerCtz` (something which v26.x already includes upstream).
    - above patches are not needed

## Download
Go to [releases](https://github.com/4meters/node-for-armv7/releases)

Binaries are built with `--partly-static`, because many systems still use gcc/g++12 libs.

### Install with nvm

If you just want to use node on armv7, you can download the latest release, then use [nvm](https://www.nvmnode.com/):

```bash
VERSION="v26.x.x" # replace this with your version
tar -xzf node-$VERSION-linux-armv7l.tar.gz -C "$NVM_DIR/versions/node/"
nvm use $VERSION
```

## How to build

If you prefer to build node yourself, you can do so using the `./build-for-armv7.sh` on an Ubuntu or Debian x86_64 machine. Just run:


```bash
chmod +x ./build-for-armv7.sh

# Build latest release on default branch (v26.x)
sudo ./build-for-armv7.sh

# Build a specific branch
sudo ./build-for-armv7.sh v24.x
```

This will install the required packages automatically.

The output file is a `node-$VERSION-linux-armv7l.tar.gz` archive in the current directory, which can similarly be unpacked and used with nvm.

## Additional info

See [nodejs/node issue #61794](https://github.com/nodejs/node/issues/61794#issuecomment-5302695402)
