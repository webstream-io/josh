#!/bin/sh
#                       W
#                      R RW        W.
#                    RW::::RW    DR::R
#         :RRRRRWWWWRt:::::::RRR::::::E        jR
#          R.::::::::::::::::::::::::::Ri  jiR:::R
#           R:::::::.RERRRRWWRERR,::::::Efi:::::::R             GjRRR Rj
#            R::::::.R             R:::::::::::::;G    RRj    WWR    RjRRRRj
#            Rt::::WR      RRWR     R::::::::::::::::fWR::R;  WRW    RW    R
#        WWWWRR:::EWR     E::W     WRRW:::EWRRR::::::::: RRED WR    RRW   RR
#        'R:::::::RRR            RR     DWW   R::::::::RW   LRRR    WR    R
#          RL:::::WRR       GRWRR        RR   R::WRiGRWW    RRR    RRR   R
#            Ri:::WWD    RWRRRWW   WWR   LR   R W    RR    RRRR    RR    R
#   RRRWWWWRE;,:::WW     R:::RW   RR:W   RR   ERE    RR    RRR    RRR    R
#    RR:::::::::::RR    tR:::WR   Wf:R   RW    R     R     RRR    RR    R
#      WR::::::::tRR    WR::RW   ER.R   RRR       R       RRRR    RR    R
#         WE:::::RR     R:::RR   :RW   E RR      RW;     GRRR    RR    R
#         R.::::,WR     R:::GRW       E::RR     WiWW     RRWR   LRRWWRR
#       WR::::::RRRRWRG::::::RREWDWRj::::RW  ,WR::WR    iRWWWWWRWW    R
#     LR:::::::::::::::::::::::::::::::::EWRR::::::RRRDi:::W    RR   R
#    R:::::::::::::::::::::::::::::::::::::::::::::::::::tRW   RRRWWWW
#  RRRRRRRRRRR::::::::::::::::::::::::::::::::::::,:::DE RRWRWW,
#            R::::::::::::: RW::::::::R::::::::::RRWRRR
#            R::::::::::WR.  ;R::::;R  RWi:::::ER
#            R::::::.RR       Ri:iR       RR:,R
#            E::: RE           RW           Y
#            ERRR
#            G       Zero-configuration Rack server for Mac OS X
#                    http://pow.cx/
#
#     This is the uninstallation script for Pow.
#     See the full annotated source: http://pow.cx/docs/
#
#     Uninstall Pow by running this command:
#     curl get.pow.cx/uninstall.sh | sh


# Set up the environment.

      set -e
      JOSH_INSTALL_ROOT="/usr/lib/josh"
      JOSH_HOSTS_ROOT="/var/lib/josh"
      JOSH_LOG_ROOT="/var/log/josh"
      JOSH_CONFIG_ROOT="/etc/josh"
      JOSHD_BIN="$JOSH_INSTALL_ROOT/bin/joshd"
      JOSH_CONFIG_CURRENT_USER=`whoami`
#      POW_ROOT="$HOME/Library/Application Support/Pow"
#      POW_CURRENT_PATH="$POW_ROOT/Current"
#      POW_VERSIONS_PATH="$POW_ROOT/Versions"
#      POWD_PLIST_PATH="$HOME/Library/LaunchAgents/cx.pow.powd.plist"
#      FIREWALL_PLIST_PATH="/Library/LaunchDaemons/cx.pow.firewall.plist"
#      POW_CONFIG_PATH="$HOME/.powconfig"

# Fail fast if Pow isn't present.

      if [ ! -d "$JOSH_INSTALL_ROOT" ] && [ ! -d "$JOSH_HOSTS_ROOT" ] && [ ! -d "$JOSH_CONFIG_ROOT" ] && [ ! -f "$JOSHD_BIN" ]; then
        echo "error: can't find Josh" >&2
        exit 1
      fi

# Find the tty so we can prompt for confirmation even if we're being piped from curl.

      TTY="/dev/$( ps -p$$ -o tty | tail -1 | awk '{print$1}' )"

# Make sure we really want to uninstall.

      read -p "Sorry to see you go. Uninstall Josh [y/n]? " ANSWER < $TTY

      if [ $ANSWER != "y" ]; then
        exit 1
      fi
      echo "Removing NSS service"

      sudo rm -f /lib/libnss_josh.so.2 
      sudo sed -i -r -e 's/ josh//g' /etc/nsswitch.conf
      sudo rm -fr "$JOSH_INSTALL_ROOT"
      sudo rm -f "$JOSHD_BIN"
      sudo rm -f /etc/init/josh.conf

      if [ $@ != "--purge" ]; then
        echo "Following directories are not removed. Re-run with --purge to remove them"
        echo "-------------------------------------"
        echo $JOSH_HOSTS_ROOT
        echo $JOSH_CONFIG_ROOT
        echo "-------------------------------------"
      else
        echo "Removed the config Directories"
        sudo rm -fr "$JOSH_HOSTS_ROOT"
        sudo rm -fr "$JOSH_CONFIG_ROOT"
      fi

      
