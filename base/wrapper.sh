#!/bin/bash
# Wraps a command to be executed.
# Output is a pretty-printed summary
# Collected command output is recorded in log file

# Create log directory if it doesn't exist
if [[ -n "${LOGDIR}" && ! -d "${LOGDIR}" ]]; then
    mkdir -p "${LOGDIR}"
fi

LOGFILE="${LOGFILE:-./wrapper.log}"

function timer()
{
    if [[ $# -eq 0 ]]; then
        echo $(date '+%s')
    else
        local  stime=$1
        etime=$(date '+%s')

        if [[ -z "$stime" ]]; then stime=$etime; fi

        dt=$((etime - stime))
        ds=$((dt % 60))
        dm=$(((dt / 60) % 60))
        dh=$((dt / 3600))
        printf '%d:%02d:%02d' $dh $dm $ds
    fi
}

function printError() {
  echo
  echo "### tail $LOGFILE"
  tail -n 25 $LOGFILE | fold -s -w 160 | sed "s/^/### /g"
  echo
  echo "Full results in $LOGFILE"  
  echo
}

t=$(timer)
echo -n "+ "
echo -n "$*"
bash -xc "$*" >> $LOGFILE 2>&1
result=$?
elapsed=$(timer $t)
echo "== Result: $result" >> $LOGFILE 2>&1
echo "== Elapsed: $elapsed" >> $LOGFILE 2>&1
echo >> $LOGFILE 2>&1
if [[ $result -eq 0 ]]; then
  echo " ✓ ${elapsed}"
else
  echo " x fail ${elapsed}"
  printError 1>&2
fi

exit ${result}
