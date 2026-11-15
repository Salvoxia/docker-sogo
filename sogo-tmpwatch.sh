#!/bin/sh
# Removes old temporary files (e.g. email drafts) from SOGo's spool directory
# Based on SOGo's Scripts/tmpwatch, which SOGo's packages run daily. Removes files of the
# container's UID instead of user sogo, as the container can run with any UID.

# SOGOSPOOL must match the value of the configuration parameter SOGoMailSpoolPath
SOGOSPOOL=/var/spool/sogo

find "$SOGOSPOOL" -type f -user "$(id -u)" -atime +23 -delete > /dev/null
find "$SOGOSPOOL" -mindepth 1 -type d -user "$(id -u)" -empty -delete > /dev/null
