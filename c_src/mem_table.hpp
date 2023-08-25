#ifndef __MEM_TABLE_HPP__
#define __MEM_TABLE_HPP__

#include <map>
#include <string_view>

using namespace std;

struct MemTableEntry {
  char const *key;
  char *value;
  bool deleted;
  size_t timestamp;
};

class MemTable {
  size_t _size = 0;
  map<string_view, MemTableEntry> entries;

public:
  size_t size();
  void set(char const *key, char const *value, size_t timestamp);
  void remove(char const *key, size_t timestamp);
  MemTableEntry *get(char const *key);
};
#endif
