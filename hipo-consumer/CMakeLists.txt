# Uses HiGHS the way an application would, and fails unless HiPO really runs.
# With -DHIGHS_SOURCE=<dir> HiGHS is added as a subproject, otherwise it comes
# from find_package.
cmake_minimum_required(VERSION 3.15)
project(hipo_consumer LANGUAGES C CXX)

if(HIGHS_SOURCE)
  add_subdirectory("${HIGHS_SOURCE}" highs-subproject)
  set(HIGHS_TARGET highs)
else()
  find_package(highs REQUIRED CONFIG)
  set(HIGHS_TARGET highs::highs)
endif()

add_executable(consumer main.cpp)
target_link_libraries(consumer PRIVATE ${HIGHS_TARGET})
