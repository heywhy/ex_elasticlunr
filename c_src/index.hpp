#ifndef __INDEX_HPP__
#define __INDEX_HPP__

#include "mem_table.hpp"
#include "wal.hpp"
#include <filesystem>

namespace fs = filesystem;

struct IndexEntry {
  char const *key;
  char const *value;
  size_t timestamp;

  IndexEntry(char const *key, char const *value, size_t timestamp)
      : key(key), value(value), timestamp(timestamp) {}
};

class Index {
protected:
  fs::path const dir;
  MemTable mem_table;
  WAL wal = WAL::create(dir);

  void load_from_dir();

public:
  Index(fs::path const &dir);

  IndexEntry *get(char const *key);
  void set(char const *key, char const *value);
  void remove(char const *key);
};
#endif
