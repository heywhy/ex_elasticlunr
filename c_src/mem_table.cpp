#include "mem_table.hpp"

size_t MemTable::size() { return _size; }

void MemTable::set(char const *key, char const *value, size_t timestamp) {
  auto result = entries.find(key);

  if (result != entries.end()) {
    size_t val_size = strlen(value);
    MemTableEntry *entry = &result->second;
    size_t entry_size = strlen(entry->value);

    if (val_size < entry_size) {
      _size -= entry_size - val_size;
    } else {
      _size += val_size - entry_size;
    }

    entry->value = (char *)value;
    entry->deleted = false;
    entry->timestamp = timestamp;
  } else {
    _size += strlen(key) + strlen(value) + 16 + 1;

    MemTableEntry entry = {key, (char *)value, false, timestamp};

    entries.emplace(key, entry);
  }
}

void MemTable::remove(char const *key, size_t timestamp) {
  auto result = entries.find(key);

  if (result != entries.end()) {
    MemTableEntry *entry = &result->second;
    _size -= strlen(entry->value);

    entry->deleted = true;
    entry->value = nullptr;
    entry->timestamp = timestamp;
  } else {
    _size += strlen(key) + 16 + 1;

    MemTableEntry e = {key, nullptr, true, timestamp};

    entries.emplace(key, e);
  }
}

MemTableEntry *MemTable::get(char const *key) {
  auto result = entries.find(key);

  return result != entries.end() ? &result->second : nullptr;
}
