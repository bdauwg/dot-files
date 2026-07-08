#!/bin/sh
# Lid opened or closed: re-run the display logic inside every live i3 session.
#
# acpid runs as root with no DISPLAY, so we lift DISPLAY/XAUTHORITY straight out
# of the running i3 process rather than hardcoding :0 and guessing a cookie path.
set -u

# Give the panel a moment to come back before we try to drive it.
sleep 1

for pid in $(pgrep -x i3 2>/dev/null); do
    [ -r "/proc/$pid/environ" ] || continue
    user=$(stat -c %U "/proc/$pid" 2>/dev/null) || continue
    disp=$(tr '\0' '\n' < "/proc/$pid/environ" | sed -n 's/^DISPLAY=//p'    | head -1)
    xath=$(tr '\0' '\n' < "/proc/$pid/environ" | sed -n 's/^XAUTHORITY=//p' | head -1)
    home=$(getent passwd "$user" | cut -d: -f6)
    [ -n "$disp" ] && [ -n "$home" ] || continue

    runuser -u "$user" -- env DISPLAY="$disp" XAUTHORITY="${xath:-$home/.Xauthority}" \
        "$home/.local/bin/display-apply" >/dev/null 2>&1
done
exit 0
