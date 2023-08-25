#include "index.hpp"
#include "nif_utils.hpp"
#include <erl_nif.h>
#include <iostream>
#include <map>
#include <string>

using namespace std;

static ErlNifResourceType *INDEX_RESOURCE_TYPE;

static ERL_NIF_TERM init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Index **resource = erlang::alloc<Index *>(INDEX_RESOURCE_TYPE);

  char const *storage_dir = erlang::binary(env, argv[0]);

  *resource = new Index(storage_dir);

  ERL_NIF_TERM term = erlang::resource(env, resource);

  erlang::release(resource);

  return term;
}

static ERL_NIF_TERM put(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Index *store;
  char const *key = erlang::binary(env, argv[1]);

  auto **resource =
      erlang::resource<Index *>(env, argv[0], INDEX_RESOURCE_TYPE);

  if ((store = *resource)) {
    if (enif_is_binary(env, argv[2])) {
      char const *value = erlang::binary(env, argv[2]);

      store->set(key, value);
    } else if (enif_is_number(env, argv[2])) {
      int a;

      enif_get_int(env, argv[2], &a);

      char const *value = reinterpret_cast<char *>(&a);

      store->set(key, value);
    }

    return erlang::atom(env, "ok");
  }

  return erlang::badarg(env);
}

static ERL_NIF_TERM remove(ErlNifEnv *env, int argc,
                           const ERL_NIF_TERM argv[]) {
  Index *store;
  char const *key = erlang::binary(env, argv[1]);

  auto **resource =
      erlang::resource<Index *>(env, argv[0], INDEX_RESOURCE_TYPE);

  if ((store = *resource)) {
    store->remove(key);

    return erlang::atom(env, "ok");
  }

  return erlang::badarg(env);
}

static ERL_NIF_TERM get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  Index *store;
  IndexEntry *entry;
  Index **resource =
      erlang::resource<Index *>(env, argv[0], INDEX_RESOURCE_TYPE);
  char const *key = erlang::binary(env, argv[1]);

  if ((store = *resource) && (entry = store->get(key))) {
    cout << "get:value -> " << *entry->value << endl;

    return erlang::ok(env, erlang::binary(env, entry->value));
  }

  return erlang::atom(env, "nil");
}

static ERL_NIF_TERM slim(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ERL_NIF_TERM t = erlang::map(env);
  ERL_NIF_TERM m = erlang::map(env);
  ERL_NIF_TERM k = erlang::binary(env, "ka");
  ERL_NIF_TERM v = erlang::binary(env, "v");

  auto mm = erlang::map(env, argv[0]);
  // if (argv[0])
  //   cout << "hello world" << endl;

  cout << "map size -> " << mm.size() << std::endl;
  cout << "kk -> " << mm["reference"] << std::endl;

  // mm.

  if (enif_make_map_put(env, t, k, v, &t)) {
    return t;
  }

  return erlang::nil(env);
}

static ErlNifFunc nif_funcs[] = {
    {"get", 2, get}, {"set", 3, put}, {"init", 1, init}, {"slim", 1, slim}};

static void dtor(ErlNifEnv *env, void *ptr) {
  Index **resource = reinterpret_cast<Index **>(ptr);

  delete *resource;
}

static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
  INDEX_RESOURCE_TYPE = enif_open_resource_type(env, NULL, "doc_store", dtor,
                                                ERL_NIF_RT_CREATE, NULL);
  return 0;
}

ERL_NIF_INIT(Elixir.Box, nif_funcs, load, NULL, NULL, NULL);
