#!/bin/sh
# Looks for names in a folder and every folder below it, for the file picker.
#
#     search.sh FOLDER PATTERN HIDDEN SERIAL
#
# Prints SERIAL and a newline, then one record per name found: its type (d or
# f), its size, its time, and its path, tab between, each ended by a NUL. A
# name may hold a newline, and split on lines it could pass for a record of
# its own pointing anywhere. HIDDEN is 1 to go into hidden folders. Bounded to
# six seconds and a thousand names.
#
# The picker stops a search that a newer one replaces by signalling this
# process. Signalled as a shell running a pipeline, the shell went and the
# find under it walked on to its time limit, one more walk of the disk for
# every key typed. So once the serial is out this becomes timeout itself,
# which hands a signal on to everything under it.

if [ "$1" != --walk ]; then
    printf '%s\n' "$4"
    exec timeout 6 sh "$0" --walk "$1" "$2" "$3"
fi

folder=$2
pattern=$3
hidden=$4
if [ "$hidden" = 1 ]; then
    find "$folder" -mindepth 1 -iname "$pattern" -printf '%Y\t%s\t%T@\t%p\0'
else
    find "$folder" -mindepth 1 -name '.*' -prune -o -iname "$pattern" -printf '%Y\t%s\t%T@\t%p\0'
fi 2>/dev/null | head -z -n 1000
