#!/bin/bash
#
# ttcp-test
# (c) Anders Milton, Patrik Axelsson 2024
#
# Performs network speed tests to/from an Amiga on the network using ttcp.
#
# Version history:
# v0.1 Initial release
# v0.2 Changed it so that the transfer speeds are always measured from the
#      receiving end.
# v0.3 Waiting for the forked ttcp server to finish before getting the
#      transfer speed
#

echo -e "ttcp-test v0.3" >&2
echo -e "(c) Anders Milton, Patrik Axelsson 2024\n" >&2
[ $# -ne 1 ] && { echo "Usage: $0 <HOST>" >&2; exit 1; }
HOST=${1}

LTTCP_BIN=`which ttcp`
LOCAL_IP=`ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`
RTTCP_BIN="C:ttcp"
RTTCP_CHK="if exists ${RTTCP_BIN}; echo 1; else echo 2; endif"
RTTCPR_CMD="${RTTCP_BIN} -n512 -s -r >ram:ttcp-test.temp **>NIL:"
RTTCPT_CMD="${RTTCP_BIN} -n512 -s -t ${LOCAL_IP} >NIL: **>NIL:"
LTTCPR_CMD="${LTTCP_BIN} -n512 -s -r"
LTTCPT_CMD="${LTTCP_BIN} -n512 -s -t ${HOST}"

echo -n "IP address of local (this) machine... " >&2
if [ `echo ${LOCAL_IP} | grep -Eo '([0-9]*\.){3}[0-9]*' | wc -l` -eq 1 ]; then
    echo $LOCAL_IP >&2
else
    echo "Could not determine local IP" >&2
    exit 1
fi

echo -n "Is remote host (${HOST}) reachable... " >&2;
if [ `rsh ${HOST} echo 1` -eq 1 ]; then
    echo "yes" >&2
else
    echo "Could not execute remote command. Is rsh installed on the remote system?" >&2
    exit 1
fi

echo -n "Is ttcp installed on remote host... " >&2
if [ `rsh ${HOST} ${RTTCP_CHK}` -eq 1 ]; then
    echo "yes" >&2
else
    echo "${RTTCP_BIN} could not be found on remote system." >&2
    exit 1
fi

# Transmitting
TSPEEDS=""
echo -e "\nTransmitting:" >&2
for i in {1..5}; do
    echo -n "#$i Starting remote ttcp server... " >&2
    rsh ${HOST} ${RTTCPR_CMD} > /dev/null &
    PID=$!
    sleep 0.5
    echo -n "Transmitting... " >&2
    ${LTTCPT_CMD} &>/dev/null
    while ps $PID | grep -o $PID >/dev/null; do
        echo -ne "\b. " >&2
        sleep 0.1
    done
    KBPS=`rsh ${HOST} type ram:ttcp-test.temp | grep -Eo "[0-9]+\.[0-9][0-9] KB/sec" | cut -d' ' -f1`
    rsh ${HOST} delete ram:ttcp-test.temp &>/dev/null
    echo "done ($KBPS KB/s)" >&2
    TSPEEDS="$TSPEEDS $KBPS"
done

# Receiving
RSPEEDS=""
echo -e "\nReceiving:" >&2

echo -n "Building remote script... " >&2
for i in {1..5}; do
    rsh ${HOST} "echo \"wait 1\" >>ram:ttcp-test.temp"
    rsh ${HOST} "echo \"${RTTCPT_CMD}\" >>ram:ttcp-test.temp"
done
rsh ${HOST} "protect ram:ttcp-test.temp +se"
echo "done" >&2

echo -n "Starting remote ttcp client script... " >&2
rsh ${HOST} ram:ttcp-test.temp &
echo "done" >&2
for i in {1..5}; do
    echo -n "#$i Starting local ttcp server... " >&2
    echo -n "Receiving... " >&2
    KBPS=`${LTTCPR_CMD} 2>&1 |
    while read -r line; do
        echo "$line" | grep -Eo "[0-9]+\.[0-9][0-9] KB/sec" | cut -d' ' -f1
    done`
    echo "done ($KBPS KB/s)" >&2
    RSPEEDS="$RSPEEDS $KBPS"
done
echo -n "Deleting remote client script... " >&2
rsh ${HOST} delete ram:ttcp-test.temp &>/dev/null && echo "done" >&2 || echo "Could not delete script" >&2

echo "" >&2
TSPEEDS=`echo $TSPEEDS | tr ' ' ','`
RSPEEDS=`echo $RSPEEDS | tr ' ' ','`
TSPEEDS_SORTED=`echo $TSPEEDS | tr ',' '\n' | sort | tr '\n' ','`
RSPEEDS_SORTED=`echo $RSPEEDS | tr ',' '\n' | sort | tr '\n' ','`
echo -e " ,PASS 1,PASS 2,PASS 3,PASS 4,PASS 5,|,MIN,MAX,MEDIAN\n\
TRANSMIT,`echo $TSPEEDS`,|,`echo $TSPEEDS_SORTED | cut -d',' -f1`,`echo $TSPEEDS_SORTED | cut -d',' -f5`,`echo $TSPEEDS_SORTED | cut -d',' -f3`\n\
RECEIVE,`echo $RSPEEDS`,|,`echo $RSPEEDS_SORTED | cut -d',' -f1`,`echo $RSPEEDS_SORTED | cut -d',' -f5`,`echo $RSPEEDS_SORTED | cut -d',' -f3`" | column -t -s','
