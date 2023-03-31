#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>

#define LD 0
#define ST 1
#define LR 2
#define SC 3
#define FENCE 4

typedef struct {
	uint8_t op;
	uint32_t addr;
	uint32_t data;
	uint32_t rid;
} MemReq;

typedef struct {
	uint8_t valid;
	uint64_t birth;
	MemReq req;
} LSQEntry;

typedef struct {
	LSQEntry *entry;
	int size;
	uint64_t time;
} LSQ;

#define TRUE 1
#define FALSE 0

uint64_t lsq_create(uint32_t size) {
	LSQ *p = malloc(sizeof(LSQ));
	if(p == NULL) {
		fprintf(stderr, "ERROR: fail to malloc LSQ\n");
		return 0;
	}
	p->size = (int)size;
	p->time = 1; // time start as 1
	p->entry = malloc(size * sizeof(LSQEntry));
	if(p->entry == NULL) {
		fprintf(stderr, "ERROR: fail to malloc LSQ entries\n");
		return 0;
	}
	for(int i = 0; i < size; i++) {
		p->entry[i].valid = FALSE;
	}
	return (uint64_t)p;
}

uint8_t lsq_insert(uint64_t ptr, uint8_t op, uint32_t addr, uint32_t data, uint32_t rid) {
	LSQ *lsq = (LSQ*)ptr;

	// find an entry to insert
	for(int i = 0; i < lsq->size; i++) {
		if(lsq->entry[i].valid == FALSE) {
			LSQEntry *en = &(lsq->entry[i]);
			en->valid = TRUE;
			en->birth = lsq->time;
			lsq->time++; // increase time (make birth unique & ever increasing)
			MemReq *r = &(en->req);
			r->op = op;
			r->addr = addr;
			r->data = data;
			r->rid = rid;
			return TRUE;
		}
	}
	return FALSE;
}


// return value encoding
// bit[32:0]: Maybe#(Bit#(32)): bypass value
// bit[63:56]: error code: 0 -- correct, 1 -- no match req, 2 -- violate TSO
#define BYPASS  (0x01ULL << 32)
#define CORRECT  0x00ULL
#define NOMATCH (0x01ULL << 56)
#define VIOLATE (0x02ULL << 56)

uint64_t lsq_remove(uint64_t ptr, uint8_t op, uint32_t addr, uint32_t data, uint32_t rid) {
	LSQ *lsq = (LSQ*)ptr;

	// try to find the matching req: assuming rid is unique for each mem req
	int pos;
	for(pos = 0; pos < lsq->size; pos++) {
		if(lsq->entry[pos].valid) {
			MemReq *r = &(lsq->entry[pos].req);
			if(r->op == op && r->rid == rid) {
				if(op == FENCE) {
					break;
				}
				else if((op == LD || op == LR) && r->addr == addr) {
					break;
				}
				else if((op == ST || op == SC) && r->addr == addr && r->data == data) {
					break;
				}
			}
		}
	}

	// check req found or not
	if(pos >= lsq->size) {
		return NOMATCH;
	}

	// remove req entry
	lsq->entry[pos].valid = FALSE;

	// get birth for the req
	uint64_t req_birth = lsq->entry[pos].birth;

	// check ordering w.r.t TSO
	if(op == LD) {
		// LD: can overtake store & bypass
		uint8_t bypass = FALSE;
		uint32_t bypass_val = 0;
		uint64_t bypass_birth = 0;
		for(int i = 0; i < lsq->size; i++) {
			LSQEntry *en = &(lsq->entry[i]);
			// only check entry older than req	
			if(en->valid && en->birth < req_birth) {
				MemReq *r = &(en->req);
				if(r->op == ST) {
					// search for yougnest bypassing
					if(r->addr == addr && en->birth > bypass_birth) {
						bypass = TRUE;
						bypass_val = r->data;
						bypass_birth = en->birth;
					}
				}
				else {
					// violate TSO: cannot overtake non-store
					return VIOLATE;
				}
			}
		}
		// correct for TSO: set return on bypassing
		if(bypass) {
			return CORRECT | BYPASS | ((uint64_t)bypass_val);
		}
		else {
			return CORRECT;
		}
	}
	else {
		// non-LD: must be oldest
		for(int i = 0; i < lsq->size; i++) {
			LSQEntry *en = &(lsq->entry[i]);
			// violate TSO if there is entry older than req	
			if(en->valid && en->birth < req_birth) {
				return VIOLATE;
			}
		}
		return CORRECT;
	}
}
