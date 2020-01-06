#!/bin/bash
/usr/sbin/grafana-server --homepath=/usr/share/grafana --config=/etc/grafana/grafana.ini > /dev/null 2>&1 & 
influxd run > /dev/null 2>&1 & 
sleep 1 
influx -execute "CREATE DATABASE fuzzing" 
cd /opt/frr-fuzz && ./fuzz.sh $@
