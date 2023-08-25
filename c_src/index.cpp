#include "index.hpp"
#include "utils.hpp"

Index::Index(fs::path const &dir) : dir(dir) { load_from_dir(); };

void Index::load_from_dir() {
  if (!fs::is_directory(dir)) {
    fs::create_directories(dir);
  }

  vector<fs::path> wal_files;
  fs::directory_iterator it(dir);

  ranges::for_each(it, [this, &wal_files](fs::directory_entry const &e) {
    if (e.path().extension() == ".wal" && e.path() != this->wal.path) {
      wal_files.emplace_back(e);
    }
  });

  // sort the files because c++ doesn't guarantee any order
  ranges::sort(wal_files);

  for (fs::path const &wal_file : wal_files) {
    WAL wal = WAL::from_path(wal_file);

    WALIterator iterator = wal.iterator();
    WALEntry entry = iterator.next();

    while (entry.key != nullptr && entry.timestamp != 0) {
      if (entry.deleted) {
        mem_table.remove(entry.key, entry.timestamp);
        this->wal.remove(entry.key, entry.timestamp);
      } else {
        mem_table.set(entry.key, entry.value, entry.timestamp);
        this->wal.set(entry.key, entry.value, entry.timestamp);
      }

      entry = iterator.next();
    }
  }

  wal.flush();

  ranges::for_each(wal_files,
                   [](auto const &path) { filesystem::remove(path); });
}

IndexEntry *Index::get(char const *key) {
  MemTableEntry *table_entry;
  if ((table_entry = mem_table.get(key))) {
    return new IndexEntry(table_entry->key, table_entry->value,
                          table_entry->timestamp);
  }
  return nullptr;
}

void Index::set(char const *key, char const *value) {
  auto timestamp = NOW();

  wal.set(key, value, timestamp);
  mem_table.set(key, value, timestamp);

  wal.flush();
}

void Index::remove(char const *key) {
  auto timestamp = NOW();

  wal.remove(key, timestamp);
  mem_table.remove(key, timestamp);

  wal.flush();
}
