#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>

uint64_t c_createMem(uint32_t addr_width) {
	uint64_t size = 0x01ULL << addr_width;
	uint32_t *p = (uint32_t*)malloc(size); // should be word-aligned
	FILE *fp = NULL;
	char buff[200];
	char hex_str[10];
	uint32_t word_idx = 0;
	int i, j;

	if(p == NULL) {
		fprintf(stderr, "ERROR: fail to malloc %lldB\n", (long long)size);
		return 0;
	}
	fp = fopen("mem.vmh", "rt");
	if(fp == NULL) {
		fprintf(stderr, "ERROR: fail to open mem.vmh\n");
		return 0;
	}
	// read @0
	if(fgets(buff, 200, fp) == NULL) {
		fprintf(stderr, "ERROR: mem.vmh contents error at first line\n");
		fclose(fp);
		return 0;
	}
	// read in each line: 16 words, each word 8 chars
	while(fgets(buff, 200, fp) != NULL) {
		for(i = 15; i >= 0; i--) {
			// copy string to another hex_str
			for(j = 0; j < 8; j++) {
				hex_str[j] = buff[i * 8 + j];
			}
			hex_str[8] = '\0';
			// read from it
			sscanf(hex_str, "%x", &(p[word_idx]));
			word_idx++;
		}
	}
	// close file
	fclose(fp);
	printf("C create mem: load %d words from mem.vmh\n", word_idx);
	// set uninitialized words to 0xAAAAAAAA (default of BSV regfile)
	for(; word_idx < (size >> 2); word_idx++) {
		p[word_idx] = 0xAAAAAAAA;
	}
	return (uint64_t)p;
}

uint32_t c_readMem(uint64_t ptr, uint32_t wordAddr) {
	uint32_t *mem = (uint32_t*)ptr;
	return mem[wordAddr];
}

void c_writeMem(uint64_t ptr, uint32_t wordAddr, uint32_t data) {
	uint32_t *mem = (uint32_t*)ptr;
	mem[wordAddr] = data;
}
