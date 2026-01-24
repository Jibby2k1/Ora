# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "llama_cpp_dart")
project(${PROJECT_NAME} LANGUAGES CXX)

include(GNUInstallDirs)
set(CMAKE_INSTALL_LIBDIR lib)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" src)

add_custom_target(
  llama_symlink ALL
  COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}/lib"
  COMMAND ${CMAKE_COMMAND} -E create_symlink
          "${CMAKE_BINARY_DIR}/lib/libllama.so.0"
          "${CMAKE_BINARY_DIR}/lib/libllama.so"
  DEPENDS llama
)

set(llama_cpp_dart_bundled_libraries
  "${CMAKE_BINARY_DIR}/lib/libllama.so"
  PARENT_SCOPE
)
