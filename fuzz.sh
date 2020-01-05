#!/bin/bash
#
# FRR AFL fuzzing job manager
#

#export ASAN_OPTIONS=detect_leaks=0

if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root"
	exit 1
fi

CORES=2
IDIR="/usr/lib/frr"
RDIR=""
SDIR=""
IFDB=""

printhelp() {
	printf "$0 [options] <protocol>\n\n"
	printf "Required parameters:\n\n"
	printf "  <protocol>\t\ttarget protocol daemon\n"
	printf "\nOptions:\n\n"
	printf "  -h\t\tShow this help\n"
	printf "  -r\t\tresume previous session (false)\n"
	printf "  -c <cores>\t\tnumber of cores to saturate ($CORES)\n"
	printf "  -t <dir>\t\tFRR installation directory ($IDIR)\n"
	printf "  -i <name>\t\tPush stats into InfluxDB database <name>\n"
	printf "  -o <dir>\t\tSet output directory (out/<daemon>)\n"
	exit
}

while getopts "hrc:t:i:o:" opt; do
	case "$opt" in
		h)
			printhelp
			;;
		r)
			SDIR="-"
			printf "[+] Resuming existing session\n"
			;;
		c)
			CORES=$OPTARG
			printf "[+] Using %d cores\n" $CORES
			;;
		t)
			IDIR=$OPTARG
			printf "[+] Using install path '%s'\n" $IDIR
			;;
		i)
			IFDB=$OPTARG
			printf "[+] Will push stats into InfluxDB '%s'\n" $IFDB
			;;
		o)
			RDIR=$OPTARG
			printf "[+] Using output directory %s\n" $RDIR
			;;
	esac
done
shift $((OPTIND-1))

if [ "$#" -lt "1" ]; then
	printhelp
	exit 1
fi

PROTO=$1

if [[ -z $RDIR ]]; then
	RDIR="out/$PROTO"
fi

if [[ -z $SDIR ]]; then
	SDIR=" samples/$PROTO"
fi

BANNER="frr-fuzz-$PROTO"

# Setup AFL system settings
swapoff -a
echo core >/proc/sys/kernel/core_pattern
bash -c 'cd /sys/devices/system/cpu; echo performance | tee cpu*/cpufreq/scaling_governor'

# Create new tmux session to organize our fuzzing tasks
tmux new-session -s $BANNER -d

function afl_slave () {
	ID=$1
	MS="-S $BANNER-slave$i"
	SPLIT="-v"

	# ID 0 is the master
	if [ "$ID" -eq "0" ]; then
		MS="-M $BANNER-master"
	fi

	# Aternate splits to work around terminal sizing glitch
	if [ "`expr $ID % 2`" -eq "1" ]; then
		SPLIT="-h"
	fi

	CMD="AFL_NO_AFFINITY=1 taskset -c $ID bash limit_memory.sh -u root afl-fuzz -m none -i$SDIR -o $RDIR $MS -- $IDIR/$PROTO"
	echo $CMD
	if [ "$ID" -ne "0" ]; then
		tmux split-window -t $BANNER $SPLIT
	fi
	tmux select-layout -t $BANNER tiled
	tmux send-keys -t $BANNER "bash -c '$CMD'" C-m
	#tmux select-layout -t $BANNER tiled
}

# Create protocol-specific results directory
mkdir -p out/$PROTO

# Start jobs
JOBS=$(($CORES - 1))
for i in `seq 0 $JOBS`; do
	afl_slave $i
done

tmux split-window -t $BANNER -h

MON_IFDB_ARG=""
if [[ ! -z $IFDB ]]; then
	MON_IFDB_ARG="-i $IFDB"
fi

tmux send-keys -t $BANNER "watch -n 1 ./monitor.sh $MON_IFDB_ARG -s $RDIR" C-m
tmux select-layout -t $BANNER tiled
tmux select-layout -t $BANNER tiled

tmux -2 attach-session -d
