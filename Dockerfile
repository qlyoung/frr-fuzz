# Sets up a Docker image with Grafana, InfluxDB, fuzzable FRR and AFL
# Grafana will monitor AFL's fuzzing progress and is accessible on port 3000

FROM ubuntu:18.04 as base

# Basic setup & tools
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
      curl \
      wget \
      gpg \
      apt-transport-https \
      git \
      build-essential \
      lsb-release \
      software-properties-common

# grafana & influx
RUN wget -q -O - https://packages.grafana.com/gpg.key | apt-key add - && \
    add-apt-repository "deb https://packages.grafana.com/oss/deb stable main" && \
    add-apt-repository "deb https://packages.grafana.com/oss/deb beta main" && \
    apt-get update && \
    apt-get install -y grafana influxdb influxdb-client

# frr-fuzz clone & dependencies setup
RUN cd /opt && \
    git clone https://github.com/qlyoung/frr-fuzz.git && \
    cd ./frr-fuzz && \
    git submodule update --init --recursive && \
    ./setup-ubuntu.sh

# FRR build deps
RUN apt-get install -y \
      git autoconf automake libtool make libreadline-dev texinfo \
      pkg-config libpam0g-dev libjson-c-dev bison flex python3-pytest \
      libc-ares-dev python3-dev libsystemd-dev python-ipaddress python3-sphinx \
      install-info build-essential libsystemd-dev libsnmp-dev perl libcap-dev \
      cmake libpcre3-dev autoconf automake

# libyang build & install
RUN git clone https://github.com/CESNET/libyang.git && \
    cd libyang && \
    mkdir build; cd build && \
    cmake -DENABLE_LYD_PRIV=ON -DCMAKE_INSTALL_PREFIX:PATH=/usr -D CMAKE_BUILD_TYPE:String="Release" .. && \
    make; make install

# FRR users and groups
RUN groupadd -r -g 92 frr && \
    groupadd -r -g 85 frrvty && \
    adduser --system --ingroup frr --home /var/run/frr/ --gecos "FRR suite" --shell /sbin/nologin frr && \
    usermod -a -G frrvty frr

# FRR build and install
RUN cd /opt/frr-fuzz && ./install-frr.sh -boiqaf

# create entrypoint
RUN echo '\n\
/usr/sbin/grafana-server --homepath=/usr/share/grafana --config=/etc/grafana/grafana.ini cfg:default.log.mode="console" > /dev/null & \n\
influxd run > /dev/null & \n\
sleep 1 \n\
influx -execute "CREATE DATABASE fuzzing" \n\
cd /opt/frr-fuzz && ./fuzz.sh $@' > /opt/run.sh
RUN chmod +x /opt/run.sh

# set entrypoint
ENTRYPOINT /opt/run.sh
CMD ["-i fuzzing zebra"]
