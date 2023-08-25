#ifndef __UTILS_HPP__

#define __UTILS_HPP__

#include <chrono>

using namespace std;

#define NOW() chrono::system_clock::now().time_since_epoch().count()

#endif
