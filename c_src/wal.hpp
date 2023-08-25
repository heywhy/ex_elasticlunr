#ifndef __WAL_HPP__
#define __WAL_HPP__

#include <filesystem>
#include <fstream>

using namespace std;
namespace fs = std::filesystem;

struct WALEntry {
  char *key;
  char *value;
  bool deleted;
  size_t timestamp;
};

struct WALIterator {
  ifstream reader;

  WALIterator(fs::path const &file);
  ~WALIterator();
  WALEntry next();
};

struct WAL {
  ofstream file;
  fs::path const path;

  WAL(fs::path const path);
  ~WAL();

  static WAL create(fs::path dir);
  static WAL from_path(fs::path const &path);

  void set(char const *key, char const *value, size_t timestamp);
  void remove(char const *key, size_t timestamp);
  void flush();
  WALIterator iterator();
};
#endif
