##################################################################
#
# Core Flight System architecture-specific build recipes
#
# This file is invoked by the top-level mission recipe for
# to build cFE/cFS for each target processor
#
# Note that the target CPUs may use different architectures, therefore each
# architecture must be done as a separate sub-build since none of the binaries 
# can be shared.
#
##################################################################


##################################################################
#
# FUNCTION: initialize_globals
#
# Set up global mission configuration variables.
# This function determines the mission configuration directory and 
# also reads any startup state info from file(s) on the disk
# 
# In the CPU (cross) build this only reads a cache file that was
# generated by the mission (top-level) build.  Therefore all 
# architecture-specific cross builds will get the same settings.
#
function(initialize_globals)

  message("--- ${MISSION_BINARY_DIR}")
  # Sanity check -- the parent build script should have set MISSION_BINARY_DIR
  if (NOT IS_DIRECTORY "${MISSION_BINARY_DIR}")
      message(FATAL_ERROR "BUG -- MISSION_BINARY_DIR not a valid directory in arch_build.cmake")
  endif()

  # Read the variable values from the cache file.
  set(MISSION_IMPORTED_VARS)
  file(READ "${MISSION_BINARY_DIR}/mission_vars.cache" PARENTVARS)
  string(REGEX REPLACE ";" "\\\\;" PARENTVARS "${PARENTVARS}")
  string(REGEX REPLACE "\n" ";" PARENTVARS "${PARENTVARS}")
  foreach(PV ${PARENTVARS})
    if (VARNAME)
      set(${VARNAME} ${PV} PARENT_SCOPE)
      list(APPEND MISSION_IMPORTED_VARS ${VARNAME})
      unset(VARNAME)
    else()
      set(VARNAME ${PV})
    endif()
  endforeach(PV ${PARENTVARS})
  unset(VARNAME)
  unset(PARENTVARS)
  set(MISSION_IMPORTED_VARS ${MISSION_IMPORTED_VARS} PARENT_SCOPE)
    
endfunction(initialize_globals)


##################################################################
#
# FUNCTION: add_psp_module
#
# Simplified routine to add a driver to the PSP in use on this arch
# Called by module listfiles
#
function(add_psp_module MOD_NAME MOD_SRC_FILES)

  # Include the PSP shared directory so it can get to cfe_psp_module.h
  include_directories(${MISSION_SOURCE_DIR}/psp/fsw/shared)
  add_definitions(-D_CFE_PSP_MODULE_)
  
  # Create the module
  add_library(${MOD_NAME} STATIC ${MOD_SRC_FILES} ${ARGN})

endfunction(add_psp_module)

##################################################################
#
# FUNCTION: add_cfe_app
#
# Simplified routine to add a CFS app or lib this arch
# Called by module listfiles
#
function(add_cfe_app APP_NAME APP_SRC_FILES)

  # currently this will build an app with either static linkage or shared/module linkage,
  # but this does not currently support both for a single arch (could be revised if that is needed)
  if (APP_INSTALL_LIST)
     set(APPTYPE "MODULE")
  else()
     set(APPTYPE "STATIC")
  endif()
    
  # Create the app module
  add_library(${APP_NAME} ${APPTYPE} ${APP_SRC_FILES} ${ARGN})
  
  if (APP_INSTALL_LIST)
    cfs_app_do_install(${APP_NAME} ${APP_INSTALL_LIST})
  endif (APP_INSTALL_LIST)
  
endfunction(add_cfe_app)

##################################################################
#
# FUNCTION: add_cfe_tables
#
# Simplified routine to add CFS tables to be built with an app
#
function(add_cfe_tables APP_NAME TBL_SRC_FILES)

  # The table source must be compiled using the same "include_directories"
  # as any other target, but it uses the "add_custom_command" so there is
  # no automatic way to do this (at least in the older cmakes)
  get_current_cflags(TBL_CFLAGS ${CMAKE_C_FLAGS})

  # Create the intermediate table objects using the target compiler,
  # then use "elf2cfetbl" to convert to a .tbl file
  set(TBL_LIST)
  foreach(TBL ${TBL_SRC_FILES} ${ARGN})
  
    # Get name without extension (NAME_WE) and append to list of tables
    get_filename_component(TBLWE ${TBL} NAME_WE)
    
    foreach(TGT ${APP_INSTALL_LIST})
      set(TABLE_DESTDIR "${CMAKE_CURRENT_BINARY_DIR}/tables_${TGT}")
      file(MAKE_DIRECTORY ${TABLE_DESTDIR})
      list(APPEND TBL_LIST "${TABLE_DESTDIR}/${TBLWE}.tbl")
      
      # Check if an override exists at the mission level (recommended practice)
      # This allows a mission to implement a customized table without modifying
      # the original - this also makes for easier merging/updating if needed.
      if (EXISTS "${MISSION_DEFS}/tables/${TGT}_${TBLWE}.c")
        set(TBL_SRC "${MISSION_DEFS}/tables/${TGT}_${TBLWE}.c")
      elseif (EXISTS "${MISSION_SOURCE_DIR}/tables/${TGT}_${TBLWE}.c")
        set(TBL_SRC "${MISSION_SOURCE_DIR}/tables/${TGT}_${TBLWE}.c")
      elseif (EXISTS "${MISSION_DEFS}/tables/${TBLWE}.c")
        set(TBL_SRC "${MISSION_DEFS}/tables/${TBLWE}.c")
      elseif (EXISTS "${MISSION_SOURCE_DIR}/tables/${TBLWE}.c")
        set(TBL_SRC "${MISSION_SOURCE_DIR}/tables/${TBLWE}.c")
      elseif (IS_ABSOLUTE "${TBL}")
        set(TBL_SRC "${TBL}")
      else()
        set(TBL_SRC "${CMAKE_CURRENT_SOURCE_DIR}/${TBL}")
      endif()

      if (NOT EXISTS "${TBL_SRC}")
         message(FATAL_ERROR "ERROR: No source file for table ${TBLWE}")    
      else()
        message("NOTE: Selected ${TBL_SRC} as source for ${TBLWE}")
      endif()    
    
      # IMPORTANT: This rule assumes that the output filename of elf2cfetbl matches
      # the input file name but with a different extension (.o -> .tbl)
      # The actual output filename is embedded in the source file (.c), however
      # this must match and if it does not the build will break.  That's just the
      # way it is, because NO make system supports changing rules based on the
      # current content of a dependency (rightfully so).
      add_custom_command(
        OUTPUT "${TABLE_DESTDIR}/${TBLWE}.tbl"
        COMMAND ${CMAKE_C_COMPILER} ${TBL_CFLAGS} -c -o ${TBLWE}.o ${TBL_SRC}
        COMMAND echo "will apply elf tool to the ${TBLWE}.o"
        COMMAND echo ${MISSION_BINARY_DIR}/bin/elf2cfetbl ${TBLWE}.o
#        COMMAND ${MISSION_BINARY_DIR}/bin/elf2cfetbl ${TBLWE}.o
#        DEPENDS ${MISSION_BINARY_DIR}/bin/elf2cfetbl ${TBL_SRC}
        WORKING_DIRECTORY ${TABLE_DESTDIR}
      )
      # Create the install targets for all the tables
      install(FILES /sandbox/sample_table.tbl DESTINATION ${TGT}/${INSTALL_SUBDIR})
    endforeach(TGT ${APP_INSTALL_LIST})
    
  endforeach(TBL ${TBL_SRC_FILES} ${ARGN})

  # Make a custom target that depends on all the tables  
  add_custom_target(${APP_NAME}_tables ALL DEPENDS ${TBL_LIST})
  
endfunction(add_cfe_tables)

##################################################################
#
# FUNCTION: add_unit_test_lib
#
# Add a library for unit testing.  This is basically the same as the 
# normal CMake "add_library" but enables the code coverage compiler options.
#
function(add_unit_test_lib UT_NAME UT_SRCS)
    add_library(utl_${UT_NAME} STATIC  ${UT_SRCS} ${ARGN})
    set_target_properties(utl_${UT_NAME} PROPERTIES COMPILE_FLAGS "${CMAKE_C_FLAGS} -pg --coverage")
endfunction(add_unit_test_lib)

##################################################################
#
# FUNCTION: add_unit_test_exe
#
# Create unit test executable.  This links the UT main executive with
# a library that is placed under test (created via add_unit_test_lib)
# It also registers the final executable target with ctest so it will
# be run during the "make test" target or when ctest is run.
#
function(add_unit_test_exe UT_NAME UT_SRCS)
    add_executable(${UT_NAME} ${utexec_MISSION_DIR}/src/utexec.c ${UT_SRCS} ${ARGN})
    
    get_target_property(UTCDEFS ${UT_NAME} COMPILE_DEFINITIONS)
    list(APPEND UTCDEFS "DEFAULT_REF_DIR=\"${CMAKE_CURRENT_SOURCE_DIR}\"")
    
    get_target_property(UTCFLAGS ${UT_NAME} COMPILE_FLAGS)
    if (UTCFLAGS STREQUAL "UTCFLAGS-NOTFOUND")
        set(UTCFLAGS)
    endif()
    set(UTCFLAGS "${UTCFLAGS} -I${utexec_MISSION_DIR}/inc -I${CMAKE_CURRENT_SOURCE_DIR}")
    
    get_target_property(UTLFLAGS ${UT_NAME} LINK_FLAGS)
    if (UTLFLAGS STREQUAL "UTLFLAGS-NOTFOUND")
        set(UTLFLAGS)
    endif()
    set(UTLFLAGS "${UTLFLAGS} -pg --coverage")
    
    set_target_properties(${UT_NAME} PROPERTIES LINK_FLAGS "${UTLFLAGS}" COMPILE_DEFINITIONS "${UTCDEFS}" COMPILE_FLAGS "${UTCFLAGS}")
    target_link_libraries(${UT_NAME} utl_${UT_NAME}) 
    add_test(${UT_NAME} ${UT_NAME})
endfunction(add_unit_test_exe)


##################################################################
#
# FUNCTION: cfe_exec_do_install
#
# Called to install a CFE core executable target to the staging area.
# Some architectures/OS's need special extra steps, and this
# function can be overridden in a custom cmake file for those platforms
#
function(cfe_exec_do_install CPU_NAME)

    # By default just stage it to a directory of the same name
    install(TARGETS core-${CPU_NAME} DESTINATION ${CPU_NAME})
    
endfunction(cfe_exec_do_install)

##################################################################
#
# FUNCTION: cfs_app_do_install
#
# Called to install a CFS application target to the staging area.
# Some architectures/OS's need special extra steps, and this
# function can be overridden in a custom cmake file for those platforms
#
function(cfs_app_do_install APP_NAME)

    # override the default behavior of attaching a "lib" prefix
    set_target_properties(${APP_NAME} PROPERTIES 
        PREFIX "" OUTPUT_NAME "${APP_NAME}")
    
    # Create the install targets for this shared/modular app
    foreach(TGT ${ARGN})
      install(TARGETS ${APP_NAME} DESTINATION ${TGT}/${INSTALL_SUBDIR})
    endforeach()

endfunction(cfs_app_do_install)


##################################################################
#
# FUNCTION: prepare
#
# Called by the top-level CMakeLists.txt to set up prerequisites
#
function(prepare)

  # Generate the "osconfig.h" wrapper file as indicated by the configuration
  # If specific system config options were not specified, use defaults
  if (NOT OSAL_SYSTEM_OSCONFIG)
    set(OSAL_SYSTEM_OSCONFIG default)
  endif (NOT OSAL_SYSTEM_OSCONFIG)    
  generate_config_includefile("inc/osconfig.h" osconfig.h ${OSAL_SYSTEM_OSCONFIG} ${TARGETSYSTEM})

  # Allow sources to "ifdef" certain things if running on simulated hardware
  # This should be used sparingly, typically to fake access to hardware that is not present
  if (SIMULATION)
    add_definitions(-DSIMULATION=${SIMULATION})
  endif (SIMULATION)
  
  # Check that PSPNAME, BSPTYPE, and OSTYPE are set properly for this arch
  if (NOT CFE_SYSTEM_PSPNAME OR NOT OSAL_SYSTEM_OSTYPE)
    if (CMAKE_CROSSCOMPILING)
      message(FATAL_ERROR "Cross-compile toolchain ${CMAKE_TOOLCHAIN_FILE} must define CFE_SYSTEM_PSPNAME and OSAL_SYSTEM_OSTYPE")
    elseif ("${CMAKE_SYSTEM_NAME}" STREQUAL "Linux" OR 
            "${CMAKE_SYSTEM_NAME}" STREQUAL "CYGWIN" OR
            "${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")
      # Export the variables determined here up to the parent scope
      SET(CFE_SYSTEM_PSPNAME      "pc-linux" PARENT_SCOPE)
      SET(OSAL_SYSTEM_OSTYPE      "posix"    PARENT_SCOPE)
    else ()
      # Not cross compiling and host system is not recognized
      message(FATAL_ERROR "Do not know how to set CFE_SYSTEM_PSPNAME and OSAL_SYSTEM_OSTYPE on ${CMAKE_SYSTEM_NAME} system")
    endif()
  endif (NOT CFE_SYSTEM_PSPNAME OR NOT OSAL_SYSTEM_OSTYPE)
  
  # Truncate the global TGTSYS_LIST to be only the target architecture
  set(TGTSYS_LIST ${TARGETSYSTEM} PARENT_SCOPE)
 
endfunction(prepare)


##################################################################
#
# FUNCTION: process_arch
#
# Called by the top-level CMakeLists.txt to set up targets for this arch
# This is where the real work is done
#
function(process_arch SYSVAR)

  # Check if something actually uses this arch; 
  # if this list is empty then do nothing, skip building osal/psp
  if (NOT DEFINED TGTSYS_${SYSVAR})
    return()
  endif()
  
  # Generate a list of targets that share this system architecture
  set(INSTALL_TARGET_LIST)
  foreach(TGTID ${TGTSYS_${SYSVAR}})
    set(TGTNAME ${TGT${TGTID}_NAME})
    if(NOT TGTNAME)
      set(TGTNAME "cpu${TGTID}")
    endif(NOT TGTNAME)
    list(APPEND INSTALL_TARGET_LIST ${TGTNAME})
  endforeach()
       
  # Include any specific compiler flags or config from the selected PSP
  include(${MISSION_SOURCE_DIR}/psp/fsw/${CFE_SYSTEM_PSPNAME}/make/build_options.cmake)
    
  # The "inc" directory in the binary dir contains the generated wrappers, if any
  include_directories(${MISSION_BINARY_DIR}/inc)
  include_directories(${CMAKE_BINARY_DIR}/inc)

  # Configure OSAL target first, as it also determines important compiler flags
  add_subdirectory(${MISSION_SOURCE_DIR}/osal osal)
  
  # The OSAL displays its selected OS, so it is logical to display the selected PSP
  # This can help with debugging if things go wrong.
  message(STATUS "PSP Selection: ${CFE_SYSTEM_PSPNAME}")

  # Add all widely-used public headers to the include path chain
  include_directories(${MISSION_SOURCE_DIR}/osal/src/os/inc)
  include_directories(${MISSION_SOURCE_DIR}/psp/fsw/inc)  
  include_directories(${MISSION_SOURCE_DIR}/cfe/fsw/cfe-core/src/inc)
  include_directories(${MISSION_SOURCE_DIR}/cfe/cmake/target/inc)
    
  # Append the PSP and OSAL selections to the Doxyfile so it will be included
  # in the generated documentation automatically.
  # Also extract the "-D" options within CFLAGS and inform Doxygen about these
  string(REGEX MATCHALL "-D[A-Za-z0-9_=]+" DOXYGEN_DEFINED_MACROS "${CMAKE_C_FLAGS}")
  string(REGEX REPLACE "-D" " " DOXYGEN_DEFINED_MACROS "${DOXYGEN_DEFINED_MACROS}")
  file(APPEND "${MISSION_BINARY_DIR}/doc/mission-content.doxyfile" 
    "PREDEFINED += ${DOXYGEN_DEFINED_MACROS}\n"
    "INPUT += ${MISSION_SOURCE_DIR}/osal/src/os/${OSAL_SYSTEM_OSTYPE}\n"
    "INPUT += ${MISSION_SOURCE_DIR}/psp/fsw/${CFE_SYSTEM_PSPNAME}\n")

  # Append to usersguide.doxyfile
  file(APPEND "${MISSION_BINARY_DIR}/doc/cfe-usersguide.doxyfile" 
    "INPUT += ${MISSION_SOURCE_DIR}/psp/fsw/${CFE_SYSTEM_PSPNAME}/src\n")
   
  # The PSP and/or OSAL should have defined where to install the binaries.
  # If not, just install them in /cf as a default (this can be modified 
  # by the packaging script if it is wrong for the target)
  if (NOT INSTALL_SUBDIR)
    set(INSTALL_SUBDIR cf)
  endif (NOT INSTALL_SUBDIR)
      
  # Add any dependencies which MIGHT be required for subsequent apps/libs/tools
  # The cfe-core and osal are handled explicitly since these have special extra config
  foreach(DEP ${MISSION_DEPS})
    if (NOT DEP STREQUAL "cfe-core" AND
        NOT DEP STREQUAL "osal")
      add_subdirectory(${${DEP}_MISSION_DIR} ${DEP})
    endif()
  endforeach(DEP ${MISSION_DEPS})
    
  # Clear the app lists
  set(ARCH_APP_SRCS)
  foreach(APP ${TGTSYS_${SYSVAR}_APPS})
    set(TGTLIST_${APP})
  endforeach()
  foreach(DRV ${TGTSYS_${SYSVAR}_DRIVERS})
    set(TGTLIST_DRV_${DRV})
  endforeach()

  # INCLUDE_REFACTOR: apps and the PSP like to #include cfe_platform_cfg.h -- they shouldn't
  # This will become unnecessary when dependency refactoring is merged in, but for now
  # they need to be able to find it.  Remove the next line once refactoring is merged.
  # Also do not do this if more than one CPU shares this architecture - this hack can only
  # be done if a 1:1 mapping between cpus and architectures (so all apps are rebuilt per-cpu)
  list(LENGTH TGTSYS_${SYSVAR} ARCHLEN)
  if (ARCHLEN EQUAL 1)
    include_directories(${CMAKE_BINARY_DIR}/cfe_core_default_${TGT${TGTSYS_${SYSVAR}}_NAME}/inc)
  endif (ARCHLEN EQUAL 1)
        
  # Process each PSP module that is referenced on this system architecture (any cpu)
  foreach(PSPMOD ${TGTSYS_${SYSVAR}_PSPMODULES}) 
    message(STATUS "Building PSP Module: ${PSPMOD}")
    add_subdirectory(${${PSPMOD}_MISSION_DIR} psp/${PSPMOD})
  endforeach()
  
  # Process each app that is used on this system architecture
  set(APP_INSTALL_LIST)
  foreach(APP ${TGTSYS_${SYSVAR}_STATICAPPS})
    message(STATUS "Building Static App: ${APP}")
    add_subdirectory(${${APP}_MISSION_DIR} apps/${APP})
  endforeach()

  # Configure the selected PSP
  # The naming convention allows more than one PSP per arch,
  # however in practice this gets too complicated so it is
  # currently a 1:1 relationship.  This may change at some point.
  add_subdirectory(${MISSION_SOURCE_DIR}/psp psp/${CFE_SYSTEM_PSPNAME})
        
  # Process each target that shares this system architecture
  # First Pass: Assemble the list of apps that should be compiled 
  foreach(TGTID ${TGTSYS_${SYSVAR}})
      
    set(TGTNAME ${TGT${TGTID}_NAME})
    if(NOT TGTNAME)
      set(TGTNAME "cpu${TGTID}")
      set(TGT${TGTID}_NAME "${TGTNAME}")
    endif(NOT TGTNAME)
       
    # Append to the app install list for this CPU
    foreach(APP ${TGT${TGTID}_APPLIST})
      set(TGTLIST_${APP} ${TGTLIST_${APP}} ${TGTNAME})
    endforeach(APP ${TGT${TGTID}_APPLIST})
      
  endforeach(TGTID ${TGTSYS_${SYSVAR}})

#  add_compile_options(-fPIC -fsanitize=undefined)
#  add_link_options(-fPIC -fsanitize=undefined)

  cmake_policy(SET CMP0079 NEW)
  # Process each app that is used on this system architecture
  foreach(APP ${TGTSYS_${SYSVAR}_APPS})
    set(APP_INSTALL_LIST ${TGTLIST_${APP}})
    message(STATUS "Building App: ${APP} install=${APP_INSTALL_LIST}")
    add_subdirectory(${${APP}_MISSION_DIR} apps/${APP})

    set_target_properties(${APP} PROPERTIES NO_SONAME TRUE)
    target_link_libraries(${APP} cfe_core_default_cpu1 osal psp-pc-linux target-config-WIP)
    target_link_options(${APP} PRIVATE -all_load)
  endforeach()
  
  # If unit test is enabled, build a generic ut stub library for CFE
  if (ENABLE_UNIT_TESTS)
    add_subdirectory(${cfe-core_MISSION_DIR}/ut-stubs ut_cfe_core_stubs)
  endif (ENABLE_UNIT_TESTS)

  # Process each target that shares this system architecture
  # Second Pass: Build cfe-core and link final target executable 
  foreach(TGTID ${TGTSYS_${SYSVAR}})
  
    set(TGTNAME ${TGT${TGTID}_NAME})    
    set(TGTPLATFORM ${TGT${TGTID}_PLATFORM})
    if(NOT TGTPLATFORM)
      set(TGTPLATFORM "default" ${TGTNAME})
    endif(NOT TGTPLATFORM)

    string(REPLACE ";" "_" CFE_CORE_TARGET "cfe_core_${TGTPLATFORM}")
    if (NOT TARGET ${CFE_CORE_TARGET})

      # Generate wrapper file for the requisite cfe_platform_cfg.h file
      generate_config_includefile("${CFE_CORE_TARGET}/inc/cfe_msgids.h" msgids.h ${TGTPLATFORM})
      generate_config_includefile("${CFE_CORE_TARGET}/inc/cfe_platform_cfg.h" platform_cfg.h ${TGTPLATFORM})
      
      # Actual core library is a subdirectory
      add_subdirectory(${MISSION_SOURCE_DIR}/cfe/fsw/cfe-core ${CFE_CORE_TARGET})
      
    endif (NOT TARGET ${CFE_CORE_TARGET})

    # Target to generate the actual executable file
    add_subdirectory(cmake/target ${TGTNAME})
  endforeach(TGTID ${TGTSYS_${SYSVAR}})
 
 
endfunction(process_arch SYSVAR)

