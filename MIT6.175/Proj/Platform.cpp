#include <stdlib.h>
#include <semaphore.h>
#include "ConnectalMemoryInitialization.h"
#include "Platform.hpp"

#include <fstream>
#include <iostream>

#include <elf.h>


template <typename Elf_Ehdr, typename Elf_Phdr>
bool Platform::load_elf_specific(char* buf, size_t buf_sz) {
    // 64-bit ELF
    Elf_Ehdr *ehdr = (Elf_Ehdr*) buf;
    Elf_Phdr *phdr = (Elf_Phdr*) (buf + ehdr->e_phoff);
    if (buf_sz < ehdr->e_phoff + ehdr->e_phnum * sizeof(Elf_Phdr)) {
        std::cerr << "ERROR: load_elf: file too small for expected number of program header tables" << std::endl;
        return false;
    }
    // loop through program header tables
    for (int i = 0 ; i < ehdr->e_phnum ; i++) {
        if ((phdr[i].p_type == PT_LOAD) && (phdr[i].p_memsz > 0)) {
            if (phdr[i].p_memsz < phdr[i].p_filesz) {
                std::cerr << "ERROR: load_elf: file size is larger than memory size" << std::endl;
                return false;
            }
            if (phdr[i].p_filesz > 0) {
                if (phdr[i].p_offset + phdr[i].p_filesz > buf_sz) {
                    std::cerr << "ERROR: load_elf: file section overflow" << std::endl;
                    return false;
                }
                // start of file section: buf + phdr[i].p_offset
                // end of file section: buf + phdr[i].p_offset + phdr[i].p_filesz
                // start of memory: phdr[i].p_paddr
                this->write_chunk( phdr[i].p_paddr, phdr[i].p_filesz, buf + phdr[i].p_offset );
            }
            if (phdr[i].p_memsz > phdr[i].p_filesz) {
                // copy 0's to fill up remaining memory
                size_t zeros_sz = phdr[i].p_memsz - phdr[i].p_filesz;
                char* zeros = new char[zeros_sz];
                memset( (void *) zeros, 0, zeros_sz );
                this->write_chunk( phdr[i].p_paddr + phdr[i].p_filesz, phdr[i].p_memsz - phdr[i].p_filesz, zeros );
                delete[] zeros;
            }
        }
    }
    return true;
}

bool Platform::load_elf(const char* elf_filename) {
    std::ifstream elffile;
    elffile.open(elf_filename, std::ios::in | std::ios::binary);

    if (!elffile.is_open()) {
        std::cerr << "ERROR: load_elf: failed opening file \"" << elf_filename << "\"" << std::endl;
        return false;
    }

    elffile.seekg(0, elffile.end);
    size_t buf_sz = elffile.tellg();
    elffile.seekg(0, elffile.beg);

    // Read the entire file. If it doesn't fit in host memory, it won't fit in the risc-v processor
    char* buf = new char[buf_sz];
    elffile.read(buf, buf_sz);

    if (!elffile) {
        std::cerr << "ERROR: load_elf: failed reading elf header" << std::endl;
        return false;
    }

    if (buf_sz < sizeof(Elf32_Ehdr)) {
        std::cerr << "ERROR: load_elf: file too small to be a valid elf file" << std::endl;
        return false;
    }

    // make sure the header matches elf32 or elf64
    Elf32_Ehdr *ehdr = (Elf32_Ehdr *) buf;
    unsigned char* e_ident = ehdr->e_ident;
    if (e_ident[EI_MAG0] != ELFMAG0
            || e_ident[EI_MAG1] != ELFMAG1
            || e_ident[EI_MAG2] != ELFMAG2
            || e_ident[EI_MAG3] != ELFMAG3) {
        std::cerr << "ERROR: load_elf: file is not an elf file" << std::endl;
        return false;
    }

    if (e_ident[EI_CLASS] == ELFCLASS32) {
        // 32-bit ELF
        return this->load_elf_specific<Elf32_Ehdr, Elf32_Phdr>(buf, buf_sz);
    } else if (e_ident[EI_CLASS] == ELFCLASS64) {
        // 64-bit ELF
        return this->load_elf_specific<Elf64_Ehdr, Elf64_Phdr>(buf, buf_sz);
    } else {
        std::cerr << "ERROR: load_elf: file is neither 32-bit nor 64-bit" << std::endl;
        return false;
    }
}


Platform::Platform(ConnectalMemoryInitializationProxy* ptr, sem_t* sem)
{
  memoryRequestAccess = ptr;
  responseSem = sem;
}

void Platform::write_chunk(uint64_t taddr, size_t len, const void* src) {
  size_t xlen_bytes = 4;
  uint64_t data = 0;
  while (len > xlen_bytes) {
        // multiple writes required
        memcpy(&data, src, xlen_bytes);
	memoryRequestAccess->request(taddr, data);
	sem_wait(responseSem);
        taddr += xlen_bytes;
        src = (void*) (((char*) src) + xlen_bytes);
        len -= xlen_bytes;
  }
  if (len < xlen_bytes) {
    fprintf(stderr, "[ERROR] Platform::write_chunk_extIfc is writing a number of bytes that is not a multiple of XLEN\n");
  }
  memcpy(&data, src, len);
  memoryRequestAccess->request(taddr, data);
  sem_wait(responseSem);
}
