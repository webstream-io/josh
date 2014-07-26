#!/bin/sh -e
# `./build.sh` generates dist/$VERSION.tar.gz
# `./build.sh --install` installs into ~/Library/Application Support/Pow/Current

command -v node >/dev/null 2>&1 || {
  command -v nodejs >/dev/null 2>&1 && {
    cat <<EOF
Node.js is installed but node binary is not found. Run following command to resolve this issue.

  sudo update-alternatives --install /usr/bin/node node /usr/bin/nodejs 10

EOF
    exit 1
  } || {
    echo "Please install Node.js first. https://github.com/joyent/node/wiki/Installing-Node.js-via-package-manager" >&2; exit 1
  }
}

VERSION=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("package.json","utf8")).version); ""')
ROOT="/tmp/pow-build.$$"
DIST="$(pwd)/dist"

cake build

mkdir -p "$ROOT/$VERSION/node_modules"
cp -R package.json bin lib libexec "$ROOT/$VERSION"
cp Cakefile "$ROOT/$VERSION"
cd "$ROOT/$VERSION"
BUNDLE_ONLY=1 npm install --production &>/dev/null
cp `which node` bin

if [ "$1" == "--install" ]; then
  POW_ROOT="$HOME/Library/Application Support/Pow"
  rm -fr "$POW_ROOT/Versions/9999.0.0"
  mkdir -p "$POW_ROOT/Versions"
  cp -R "$ROOT/$VERSION" "$POW_ROOT/Versions/9999.0.0"
  rm -f "$POW_ROOT/Current"
  cd "$POW_ROOT"
  ln -s Versions/9999.0.0 Current
  echo "$POW_ROOT/Versions/9999.0.0"
else
  cd "$ROOT"
  tar czf "$VERSION.tar.gz" "$VERSION"
  mkdir -p "$DIST"
  cd "$DIST"
  mv "$ROOT/$VERSION.tar.gz" "$DIST"
  echo "$DIST/$VERSION.tar.gz"
fi

rm -fr "$ROOT"
