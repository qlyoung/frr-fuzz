#!/bin/bash
#
# FRR AFL fuzzing job manager
#

#export ASAN_OPTIONS=detect_leaks=0

DEFAULT_CORES=2
DEFAULT_IDIR="/usr/lib/frr"

if [ "$#" -lt "1" ]; then
	printf "Usage: $0 <protocol> [cores] [installdir]\n\n"
	printf "    <protocol> = one of [pimd, bgpd]\n"
	printf "    [cores] = number of cores to saturate ($DEFAULT_CORES)\n"
	printf "    [installdir] = FRR installation directory ($DEFAULT_IDIR)\n"
	exit
fi

# Arguments
PROTO=$1
CORES=$DEFAULT_CORES
IDIR=$DEFAULT_IDIR
RDIR="out/$PROTO"

if [ "$#" -gt "1" ]; then
	CORES=$2
	echo "Selected cores: $CORES"
fi

if [ "$#" -gt "2" ]; then
	IDIR=$3
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

	CMD="AFL_NO_AFFINITY=1 taskset -c $ID bash limit_memory.sh -u root afl-fuzz -m none -i samples/$PROTO -o $RDIR $MS -- $IDIR/$PROTO"
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
tmux send-keys -t $BANNER "watch -n 1 monitor.sh -s $RDIR" C-m
tmux select-layout -t $BANNER tiled
tmux select-layout -t $BANNER tiled

tmux -2 attach-session -d
