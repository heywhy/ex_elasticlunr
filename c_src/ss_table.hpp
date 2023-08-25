#ifndef __SS_TABLE_HPP__

#define __SS_TABLE_HPP__

#include <iostream>
#include <map>

using namespace std;

template <typename T = char const *> struct ss_table {
  map<string_view, T> table;

  void remove(char const *key) {
    auto i = table.find(key);

    if (i != table.end()) {
      table.erase(i);
    }
  }

  void set(char const *key, T &value) { table.insert({key, value}); }
};

#endif
