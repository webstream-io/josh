#!/bin/bash -e

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

command -v npm >/dev/null 2>&1 || {
  echo "Please install npm first." >&2
  exit 1
}

VERSION=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("package.json","utf8")).version); ""')
TMP_ROOT="/tmp/pow-build.$$"

npm install
command -v cake >/dev/null 2>&1 || PATH=`npm root`/.bin:$PATH
cake build

mkdir -p "$TMP_ROOT/node_modules"
cp -R package.json bin lib libexec adapters "$TMP_ROOT"
cp Cakefile "$TMP_ROOT"
cd "$TMP_ROOT"
BUNDLE_ONLY=1 npm install --production &>/dev/null
cd -
