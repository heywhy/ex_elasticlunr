#include <atomic>
#include <erl_nif.h>

using std::atomic_int64_t;

struct atomic_int {
  atomic_int64_t value;

  atomic_int(ErlNifSInt64 value) : value(value) {}
};

static ErlNifResourceType *ATOMICS_RESOURCE_TYPE;

ERL_NIF_TERM make_atom(ErlNifEnv *env, const char *value);

ERL_NIF_TERM init(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifSInt64 value;
  atomic_int **resource = static_cast<atomic_int **>(
      enif_alloc_resource(ATOMICS_RESOURCE_TYPE, sizeof(atomic_int *)));

  if (enif_get_int64(env, argv[0], &value)) {
    *resource = new atomic_int(value);
  }

  ERL_NIF_TERM term = enif_make_resource(env, resource);

  enif_release_resource(resource);

  return term;
}

ERL_NIF_TERM add(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifUInt64 count;
  atomic_int **variable;

  if (!enif_get_uint64(env, argv[1], &count)) {
    return enif_make_badarg(env);
  }

  if (enif_get_resource(env, argv[0], ATOMICS_RESOURCE_TYPE,
                        reinterpret_cast<void **>(&variable))) {
    (*variable)->value += count;

    return make_atom(env, "ok");
  }

  return enif_make_badarg(env);
}

ERL_NIF_TERM sub(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifUInt64 count;
  atomic_int **variable;

  if (!enif_get_uint64(env, argv[1], &count)) {
    return enif_make_badarg(env);
  }

  if (enif_get_resource(env, argv[0], ATOMICS_RESOURCE_TYPE,
                        reinterpret_cast<void **>(&variable))) {
    (*variable)->value -= count;

    return make_atom(env, "ok");
  }

  return enif_make_badarg(env);
}

ERL_NIF_TERM add_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifUInt64 count;
  atomic_int **variable;

  if (!enif_get_uint64(env, argv[1], &count)) {
    return enif_make_badarg(env);
  }

  if (enif_get_resource(env, argv[0], ATOMICS_RESOURCE_TYPE,
                        reinterpret_cast<void **>(&variable))) {
    (*variable)->value += count;

    return enif_make_int64(env, (*variable)->value);
  }

  return enif_make_badarg(env);
}

ERL_NIF_TERM sub_get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifUInt64 count;
  atomic_int **variable;

  if (!enif_get_uint64(env, argv[1], &count)) {
    return enif_make_badarg(env);
  }

  if (enif_get_resource(env, argv[0], ATOMICS_RESOURCE_TYPE,
                        reinterpret_cast<void **>(&variable))) {
    (*variable)->value -= count;

    return enif_make_int64(env, (*variable)->value);
  }

  return enif_make_badarg(env);
}

ERL_NIF_TERM fetch_add(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifUInt64 count;
  atomic_int **variable;

  if (!enif_get_uint64(env, argv[1], &count)) {
    return enif_make_badarg(env);
  }

  if (enif_get_resource(env, argv[0], ATOMICS_RESOURCE_TYPE,
                        reinterpret_cast<void **>(&variable))) {
    int64_t value = (*variable)->value;

    (*variable)->value += count;

    return enif_make_int64(env, value);
  }

  return enif_make_badarg(env);
}

ERL_NIF_TERM fetch_sub(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  ErlNifUInt64 count;
  atomic_int **variable;

  if (!enif_get_uint64(env, argv[1], &count)) {
    return enif_make_badarg(env);
  }

  if (enif_get_resource(env, argv[0], ATOMICS_RESOURCE_TYPE,
                        reinterpret_cast<void **>(&variable))) {

    int64_t value = (*variable)->value;

    (*variable)->value -= count;

    return enif_make_int64(env, value);
  }

  return enif_make_badarg(env);
}

ERL_NIF_TERM put(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  atomic_int **variable;
  ErlNifUInt64 value;

  if (!enif_get_uint64(env, argv[1], &value)) {
    return enif_make_badarg(env);
  }

  if (enif_get_resource(env, argv[0], ATOMICS_RESOURCE_TYPE,
                        reinterpret_cast<void **>(&variable))) {
    atomic_int *v = *variable;

    v->value.store(value);

    return make_atom(env, "ok");
  }

  return enif_make_badarg(env);
}

ERL_NIF_TERM get(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  atomic_int **variable;

  if (enif_get_resource(env, argv[0], ATOMICS_RESOURCE_TYPE,
                        reinterpret_cast<void **>(&variable))) {
    return enif_make_int64(env, (*variable)->value);
  }

  return enif_make_badarg(env);
}

ErlNifFunc nif_funcs[] = {{"init", 1, init},
                          {"get", 1, get},
                          {"put", 2, put},
                          {"add", 2, add},
                          {"sub", 2, sub},
                          {"add_get", 2, add_get},
                          {"sub_get", 2, sub_get},
                          {"fetch_add", 2, fetch_add},
                          {"fetch_sub", 2, fetch_sub}};

void desctructor(ErlNifEnv *env, void *ptr) {
  atomic_int **resource = reinterpret_cast<atomic_int **>(ptr);

  delete *resource;
}

int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
  ATOMICS_RESOURCE_TYPE = enif_open_resource_type(
      env, NULL, "atomics.ref", desctructor, ERL_NIF_RT_CREATE, NULL);

  return 0;
}

int upgrade(ErlNifEnv *env, void **priv_data, void **old_priv_data,
            ERL_NIF_TERM load_info) {
  return 0;
}

ERL_NIF_INIT(Elixir.Elasticlunr.AtomicInt, nif_funcs, load, NULL, upgrade,
             NULL);

ERL_NIF_TERM make_atom(ErlNifEnv *env, char const *value) {
  ERL_NIF_TERM a;

  return enif_make_existing_atom(env, value, &a, ERL_NIF_LATIN1)
             ? a
             : enif_make_atom(env, value);
}
