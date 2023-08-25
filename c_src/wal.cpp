#include "wal.hpp"
#include "utils.hpp"

WALIterator::WALIterator(fs::path const &file)
    : reader(file, ios_base::binary) {}

WALIterator::~WALIterator() { reader.close(); }

WALEntry WALIterator::next() {
  char deleted;
  char key_size_buffer[8];
  char value_size_buffer[8];
  char timestamp_buffer[16];

  if (reader.peek() == -1)
    return {nullptr, nullptr, true, 0};

  reader.read(key_size_buffer, 8);
  reader.read(&deleted, 1);

  size_t const key_size = *reinterpret_cast<size_t *>(key_size_buffer);
  char *value = nullptr, *key = new char[key_size];

  if ((bool)deleted) {
    reader.read(key, key_size);
  } else {
    reader.read(value_size_buffer, 8);
    reader.read(key, key_size);

    size_t const value_size = *reinterpret_cast<size_t *>(value_size_buffer);

    value = new char[value_size];
    reader.read(value, value_size);
  }

  reader.read(timestamp_buffer, 16);
  size_t *timestamp = reinterpret_cast<size_t *>(timestamp_buffer);

  return {key, value, (bool)deleted, *timestamp};
}

WAL::WAL(fs::path const path)
    : path(path), file(path, ios_base::binary | ios_base::app) {}

WAL::~WAL() {
  file.flush();
  file.close();
}

WAL WAL::create(fs::path dir) {
  string filename = to_string(NOW()).append(".wal");

  return WAL(dir.append(filename));
}

WAL WAL::from_path(fs::path const &path) { return WAL(path); }

void WAL::set(char const *key, char const *value, size_t timestamp) {
  size_t key_size = strlen(key);
  size_t value_size = strlen(value);

  file.write(reinterpret_cast<char *>(&key_size), 8);
  file.put(false);
  file.write(reinterpret_cast<char *>(&value_size), 8);
  file.write(key, key_size);
  file.write(value, value_size);
  file.write(reinterpret_cast<char *>(&timestamp), 16);
}

void WAL::remove(char const *key, size_t timestamp) {
  size_t key_size = sizeof(key);

  file.write(reinterpret_cast<char *>(&key_size), 8);
  file.put(true);
  file.write(key, key_size);
  file.write(reinterpret_cast<char *>(&timestamp), 16);
}

void WAL::flush() { file.flush(); }

WALIterator WAL::iterator() { return WALIterator(path); }
