#include "nif_utils.hpp"
#include <erl_nif.h>
#include <string>

namespace erlang {

ERL_NIF_TERM badarg(ErlNifEnv *env) { return enif_make_badarg(env); }

ERL_NIF_TERM atom(ErlNifEnv *env, char const *value) {
  ERL_NIF_TERM a;

  return enif_make_existing_atom(env, value, &a, ERL_NIF_LATIN1)
             ? a
             : enif_make_atom(env, value);
}

ERL_NIF_TERM nil(ErlNifEnv *env) { return atom(env, "nil"); }

ERL_NIF_TERM ok(ErlNifEnv *env) { return atom(env, "ok"); }

ERL_NIF_TERM ok(ErlNifEnv *env, ERL_NIF_TERM term) {
  return enif_make_tuple2(env, atom(env, "ok"), term);
}

ERL_NIF_TERM error(ErlNifEnv *env, ERL_NIF_TERM term) {
  return enif_make_tuple2(env, atom(env, "error"), term);
}

ERL_NIF_TERM error(ErlNifEnv *env, char const *message) {
  ERL_NIF_TERM error_atom = atom(env, "error");
  ERL_NIF_TERM reason;
  unsigned char *ptr;
  size_t len = strlen(message);
  if ((ptr = enif_make_new_binary(env, len, &reason)) != nullptr) {
    strcpy((char *)ptr, message);
    return enif_make_tuple2(env, error_atom, reason);
  } else {
    ERL_NIF_TERM msg_term = enif_make_string(env, message, ERL_NIF_LATIN1);
    return enif_make_tuple2(env, error_atom, msg_term);
  }
}

ERL_NIF_TERM binary(ErlNifEnv *env, std::string str) {
  return binary(env, str.c_str());
}

ERL_NIF_TERM binary(ErlNifEnv *env, char const *c_string) {
  ERL_NIF_TERM term;
  unsigned char *ptr;
  size_t len = strlen(c_string);
  if ((ptr = enif_make_new_binary(env, len, &term)) != nullptr) {
    strcpy((char *)ptr, c_string);
    return term;
  } else {
    fprintf(stderr,
            "internal error: cannot allocate memory for binary string\r\n");
    return atom(env, "error");
  }
}

ERL_NIF_TERM map(ErlNifEnv *env) { return enif_make_new_map(env); }

char const *binary(ErlNifEnv *env, ERL_NIF_TERM term) {
  ErlNifBinary binary;

  if (enif_inspect_binary(env, term, &binary)) {
    return static_cast<char const *>((void *)binary.data);
  }

  return nullptr;
}

std::map<char const *, char const *> map(ErlNifEnv *env, ERL_NIF_TERM term) {
  ErlNifMapIterator iter;
  ERL_NIF_TERM key, value;
  std::map<char const *, char const *> m;

  enif_map_iterator_create(env, term, &iter, ERL_NIF_MAP_ITERATOR_FIRST);

  while (enif_map_iterator_get_pair(env, &iter, &key, &value)) {
    auto k = erlang::binary(env, key);
    auto v = erlang::binary(env, value);

    m.insert({k, v});

    enif_map_iterator_next(env, &iter);
  }

  enif_map_iterator_destroy(env, &iter);

  return m;
}
} // namespace erlang
