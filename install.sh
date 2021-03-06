#!/bin/bash

# Set up the environment. Respect $VERSION if it's set.

set -e
JOSH_INSTALL_ROOT="/usr/lib/josh"
JOSH_HOSTS_ROOT="/var/lib/josh"
JOSH_LOG_ROOT="/var/log/josh"
JOSH_CONFIG_ROOT="/etc/josh"
JOSHD_BIN="$JOSH_INSTALL_ROOT/bin/joshd"
JOSH_CONFIG_CURRENT_USER=`whoami`
echo "*** Installing josh..."


# Create the josh directory structure if it doesn't already exist.
sudo mkdir -p "$JOSH_INSTALL_ROOT"
sudo mkdir -p "$JOSH_HOSTS_ROOT"
sudo mkdir -p "$JOSH_CONFIG_ROOT"
sudo mkdir -p "$JOSH_LOG_ROOT"
sudo chmod a+w "$JOSH_LOG_ROOT"
sudo chmod a+w "$JOSH_HOSTS_ROOT"

# If josh is already installed, remove it first.
sudo rm -rf "$JOSH_INSTALL_ROOT"

# build josh and copy it over to $JOSH_INSTALL_ROOT
. ./build.sh
sudo cp -R "$TMP_ROOT" "$JOSH_INSTALL_ROOT"

# Create the ~/.josh symlink if it doesn't exist.
[[ -e "$HOME/.josh" ]] || ln -s "$JOSH_HOSTS_ROOT" "$HOME/.josh"

# install NSS service
sudo cp ext/libnss_josh.so.2 /lib
sudo sed -i -r -e '/\bjosh\b/ !s/^hosts:(.+)\bdns\b/hosts:\1josh dns/' /etc/nsswitch.conf

# install upstart service
cat sysconfigs/upstart.conf | m4 -D__JOSHD_BIN__=$JOSHD_BIN | sudo tee /etc/init/josh.conf > /dev/null 

# install configuration, only if not already present
JOSH_CONFIG_FILE_PATH="$JOSH_CONFIG_ROOT/config.json"
[[ -e $JOSH_CONFIG_FILE_PATH ]] || {
  cat sysconfigs/config.json | m4 -D__1__=$JOSH_CONFIG_CURRENT_USER -D__2__=$JOSH_LOG_ROOT -D__3__=$JOSH_HOSTS_ROOT | sudo tee $JOSH_CONFIG_FILE_PATH > /dev/null
}

echo "*** Starting the josh server..."
sudo service josh restart

# Show a message about where to go for help.

function print_troubleshooting_instructions() {
    echo
    echo "For troubleshooting instructions, please see the josh wiki:"
    echo "https://github.com/webstream-io/josh/wiki/Troubleshooting"
    echo
    echo "To uninstall josh, run \`./uninstall.sh\`"
}


# Check to see if the server is running properly.

# If this version of josh supports the --print-config option,
# source the configuration and use it to run a self-test.

# disabled for now
# CONFIG=$(node "$JOSHD_BIN" --print-config 2>/dev/null || true)

if [[ -n "$CONFIG" ]]; then
    eval "$CONFIG"
    echo "*** Performing self-test..."

    # Check to see if the server is running at all.
    function check_status() {
        sleep 1
        curl -sH host:pow "localhost:$JOSH_HTTP_PORT/status.json" | grep -c "$VERSION" >/dev/null
    }

    # Attempt to connect to Pow via each configured domain. If a
    # domain is inaccessible, try to force a reload of OS X's
    # network configuration.
    function check_domains() {
        for domain in ${JOSH_DOMAINS//,/$IFS}; do
            echo | nc "${domain}." "$JOSH_DST_PORT" 2>/dev/null || return 1
        done
    }

    # Use networksetup(8) to create a temporary network location,
    # switch to it, switch back to the original location, then
    # delete the temporary location. This forces reloading of the
    # system network configuration.
    function reload_network_configuration() {
        echo "*** Reloading system network configuration..."
        local location=$(networksetup -getcurrentlocation)
        networksetup -createlocation "pow$$" >/dev/null 2>&1
        networksetup -switchtolocation "pow$$" >/dev/null 2>&1
        networksetup -switchtolocation "$location" >/dev/null 2>&1
        networksetup -deletelocation "pow$$" >/dev/null 2>&1
    }

    # Try twice to connect to Pow. Bail if it doesn't work.
    check_status || check_status || {
        echo "!!! Couldn't find a running Pow server on port $JOSH_HTTP_PORT"
        print_troubleshooting_instructions
        exit 1
    }

    # Try resolving and connecting to each configured domain. If
    # it doesn't work, reload the network configuration and try
    # again. Bail if it fails the second time.
    check_domains || {
        { reload_network_configuration && check_domains; } || {
            echo "!!! Couldn't resolve configured domains ($JOSH_DOMAINS)"
            print_troubleshooting_instructions
            exit 1
        }
    }
fi


# All done!

echo "*** Installed"
echo "You may need to restart your browser for it to start recognising .dev domains."
# print_troubleshooting_instructions
