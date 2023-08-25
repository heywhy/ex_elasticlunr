#ifndef __NIF_UTILS_HPP__
#define __NIF_UTILS_HPP__

#include <erl_nif.h>
#include <map>
#include <string>

using namespace std;

namespace erlang {

ERL_NIF_TERM badarg(ErlNifEnv *env);
ERL_NIF_TERM atom(ErlNifEnv *env, char const *msg);
ERL_NIF_TERM nil(ErlNifEnv *env);
ERL_NIF_TERM ok(ErlNifEnv *env);
ERL_NIF_TERM ok(ErlNifEnv *env, ERL_NIF_TERM term);
ERL_NIF_TERM error(ErlNifEnv *env, char const *msg);
ERL_NIF_TERM error(ErlNifEnv *env, ERL_NIF_TERM term);
ERL_NIF_TERM binary(ErlNifEnv *env, string str);
ERL_NIF_TERM binary(ErlNifEnv *env, char const *c_string);
ERL_NIF_TERM map(ErlNifEnv *env);
char const *binary(ErlNifEnv *env, ERL_NIF_TERM term);
std::map<char const *, char const *> map(ErlNifEnv *env, ERL_NIF_TERM term);

template <typename T>
T *resource(ErlNifEnv *env, ERL_NIF_TERM term, ErlNifResourceType *type) {
  T *object;
  if (enif_get_resource(env, term, type, (void **)&object)) {
    return object;
  }
  return nullptr;
}

template <typename T> ERL_NIF_TERM resource(ErlNifEnv *env, T *a) {
  return enif_make_resource(env, (void *)a);
}

template <typename T> T *alloc(ErlNifResourceType *type) {
  return (T *)enif_alloc_resource(type, sizeof(T));
}

template <typename T> void release(T *object) {
  enif_release_resource((void *)object);
}
} // namespace erlang

#endif
