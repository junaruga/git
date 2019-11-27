#!/bin/sh

set -ex

cat >testprg.c <<EOS
#include <stdio.h>

int main(int argc, char *argv[])
{
	getc(stdin);

	return 0;
}
EOS

cat testprg.c
${CC:-cc} -Wall -o testprg testprg.c

./testprg </dev/null

echo a >input
./testprg <input

echo b |./testprg

rm -f fifo
mkfifo fifo

./testprg <fifo &
echo c >fifo

sleep 1  # wait for the background process

exec 8<>fifo
echo d >fifo
./testprg <&8

# This will segfault on arm64 and ppc64le, but not elsewhere:
echo e >fifo
rm fifo
./testprg <&8
