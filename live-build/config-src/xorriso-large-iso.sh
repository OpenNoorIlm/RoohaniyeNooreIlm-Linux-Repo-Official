#!/bin/bash
args=("$@")
new_args=()
n=${#args[@]}
i=0
while [ $i -lt $n ]; do
    new_args+=("${args[$i]}")
    if [ "${args[$i]}" = "-as" ] && [ "$((i+1))" -lt "$n" ] && [ "${args[$((i+1))]}" = "mkisofs" ]; then
        new_args+=("mkisofs" "-iso-level" "3")
        i=$((i+1))
    fi
    i=$((i+1))
done
exec /usr/bin/xorriso "${new_args[@]}"
