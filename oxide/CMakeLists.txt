# Wrapper CMakeLists.txt for building p4c on illumos
# bf-asm requires C++20, so we use p4c's default C++20 standard

cmake_minimum_required(VERSION 3.16.3)
project(p4c-illumos LANGUAGES C CXX)

# Include the actual p4c (uses C++20)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/.. ${CMAKE_CURRENT_BINARY_DIR}/p4c)
