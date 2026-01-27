#!/bin/bash -e

# https://raspberrypi.stackexchange.com/a/142906

# Check whether a Raspberry Pi is currently experiencing insufficient
# power or overheating or if it has had such problems in the past.

# From vcgencmd(1)
   # get_throttled

   #      Returns the throttled state of the system. This is a bit
   #      pattern - a bit being set indicates the following meanings:

   #      Bit   Meaning
   #      ────  ────────────────────────────────────
   #       0    Under-voltage detected
   #       1    Arm frequency capped
   #       2    Currently throttled
   #       3    Soft temperature limit active
   #      16    Under-voltage has occurred
   #      17    Arm frequency capping has occurred
   #      18    Throttling has occurred
   #      19    Soft temperature limit has occurred

   #      A value of zero indicates that none of the above conditions
   #      is true.


A=( [ 0]="Under-voltage detected"
    [ 1]="Arm frequency capped"
    [ 2]="Currently throttled"
    [ 3]="Soft temperature limit active"
    [16]="Under-voltage has occurred"
    [17]="Arm frequency capping has occurred"
    [18]="Throttling has occurred"
    [19]="Soft temperature limit has occurred" )

for ((i=0; i<32; i++)); do
    if [[ ! ${A[i]} ]]; then
    A[i]="set, but meaning is unknown. See vcgencmd(1)."
    fi
done

# vcgencmd get_throttled returns a string like "throttled=0x50000"
eval $(vcgencmd get_throttled)

# If user supplied a number (e.g., 0x50005), use it instead.
if [[ "$1" ]]; then throttled="$1"; fi

if (( throttled == 0 )); then
    echo "No problems with voltage or temperature since boot."
elif (( (throttled & 0xFF) == 0 )); then
    echo "Problems have occurred but are not happening now."
fi

for ((i=0; i<32; i++)); do
    if (( throttled & 2**i )); then
    echo "bit $i: ${A[$i]}"
    fi
done

# Exit with a non-zero value if problems are occurring now.
exit $(( throttled & 0xFF ))
