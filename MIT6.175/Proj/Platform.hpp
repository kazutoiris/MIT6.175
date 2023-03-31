#include <stdlib.h>
#include <semaphore.h>
#include "ConnectalMemoryInitialization.h"

class Platform {
public:
  Platform(ConnectalMemoryInitializationProxy* ptr,sem_t* sem);
  virtual ~Platform() {}
  bool load_elf(const char* elf_filename);
  virtual void write_chunk(uint64_t taddr, size_t len, const void* src);
private:
  ConnectalMemoryInitializationProxy* memoryRequestAccess;
  sem_t* responseSem;
  template <typename Elf_Ehdr, typename Elf_Phdr>
        bool load_elf_specific(char* buf, size_t buf_sz);
};

