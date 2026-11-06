# Uses HiGHS the way an application would, and fails unless the solver it is
# given really runs. With -DHIGHS_SOURCE=<dir> HiGHS is added as a subproject,
# with -DHIGHS_PKGCONFIG=ON it comes from pkg-config, otherwise from find_package.
cmake_minimum_required(VERSION 3.15)
project(hipo_consumer LANGUAGES C CXX)

if(HIGHS_SOURCE)
  add_subdirectory("${HIGHS_SOURCE}" highs-subproject)
  set(HIGHS_TARGET highs)
elseif(HIGHS_PKGCONFIG)
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(PC_HIGHS REQUIRED highs)
  # The static flags add what a static libhighs needs, and nothing for a shared one
  set(HIGHS_TARGET ${PC_HIGHS_STATIC_LDFLAGS})
  add_compile_options(${PC_HIGHS_STATIC_CFLAGS})
  # pkg-config gives no run path, unlike the CMake targets
  set(CMAKE_BUILD_RPATH "${PC_HIGHS_LIBRARY_DIRS}")
else()
  find_package(highs REQUIRED CONFIG)
  set(HIGHS_TARGET highs::highs)
endif()

add_executable(consumer main.cpp)
target_link_libraries(consumer PRIVATE ${HIGHS_TARGET})
