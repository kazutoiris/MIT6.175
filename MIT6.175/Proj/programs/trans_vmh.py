#!/usr/bin/env python

import sys

if len(sys.argv) != 3:
	print 'Usage: ./trans_vmh [input vmh] [output vmh]'
	raise

in_file = sys.argv[1]
out_file = sys.argv[2]

with open(in_file, 'r') as fin:
	lines = fin.readlines();

# orig vmh is 8B per line, we transfer it to 64B per line
if ((len(lines) - 1) % 8) != 0:
	print 'ERROR: size not 64B aligned'

with open(out_file, 'w') as fout:
	fout.write(lines[0]);
	for i in xrange(1, len(lines), 8):
		val = ''
		for j in reversed(xrange(0, 8)):
			val += lines[i + j].rstrip('\n');
		fout.write(val + '\n')

