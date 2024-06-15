cmake_minimum_required(VERSION 3.29.0)
project(elasticlunr LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED True)

if(NOT DEFINED ENV{MIX_APP_PATH})
  set(MIX_APP_PATH ${PROJECT_SOURCE_DIR})
else()
  set(MIX_APP_PATH $ENV{MIX_APP_PATH})
endif()

if(APPLE)
  set(CMAKE_SHARED_LIBRARY_SUFFIX .so)
endif()

if(DEFINED ENV{ERTS_INCLUDE_DIR})
  set(ERTS_INCLUDE_DIR $ENV{ERTS_INCLUDE_DIR})
endif()

cmake_path(APPEND PRIV_PATH ${MIX_COMPILE_PATH} "../priv")

add_library(nif SHARED c_src/atomic_int.cpp)

target_include_directories(nif SYSTEM PUBLIC ${ERTS_INCLUDE_DIR})
target_link_options(nif PUBLIC -undefined dynamic_lookup)

add_custom_command(
  TARGET nif POST_BUILD
  COMMAND mkdir -p ${PRIV_PATH} && cp $<TARGET_FILE:nif> ${PRIV_PATH}
)
