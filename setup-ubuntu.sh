#!/bin/bash

if [ "$EUID" -ne 0 ]; then
	echo "Please run as root"
	exit
fi

printf "[+] Installing git, tmux, build-essential\n"
apt install git tmux build-essential

# update submodules
git submodule update --init --recursive

# install LLVM
which clang
if [ $? -eq 0 ]; then
	printf "[!] Existing LLVM / clang installation found; skipping LLVM install\n"
else
	printf "[+] Installing LLVM / clang\n"
	bash -c "$(wget -O - https://apt.llvm.org/llvm.sh)"
	ln -s /usr/bin/clang-9 /usr/bin/clang
	ln -s /usr/bin/clang++-9 /usr/bin/clang++
	ln -s /usr/bin/llvm-symbolizer-9 /usr/bin/llvm-symbolizer
	ln -s /usr/bin/llvm-config-9 /usr/bin/llvm-config
fi

# install AFL
which afl-fuzz
if [ $? -eq 0 ]; then
	printf "[!] Existing AFL installation found; skipping AFL install\n"
else
	printf "[+] Building and installing AFL\n"
	cd AFL
	make install
	cd llvm_mode
	make install
	cd ../../
fi

printf "[+] All done, see README.md for further instructions\n"
