cmake_minimum_required(VERSION 3.16)
project(tbps_crc_sim)

# Set minimum required versions
set(MIN_GCC_VERSION "11.0.0")
set(MIN_VERILATOR_VERSION "5.022")
set(MIN_COCOTB_VERSION "1.9.2")

# Function to compare version strings
function(version_compare version1 version2 result)
    # Split version strings into components
    string(REPLACE "." ";" VERSION1_LIST ${version1})
    string(REPLACE "." ";" VERSION2_LIST ${version2})

    list(LENGTH VERSION1_LIST VERSION1_LEN)
    list(LENGTH VERSION2_LIST VERSION2_LEN)

    # Pad shorter version with zeros
    if(VERSION1_LEN LESS VERSION2_LEN)
        math(EXPR DIFF "${VERSION2_LEN} - ${VERSION1_LEN}")
        foreach(i RANGE 1 ${DIFF})
            list(APPEND VERSION1_LIST "0")
        endforeach()
    elseif(VERSION2_LEN LESS VERSION1_LEN)
        math(EXPR DIFF "${VERSION1_LEN} - ${VERSION2_LEN}")
        foreach(i RANGE 1 ${DIFF})
            list(APPEND VERSION2_LIST "0")
        endforeach()
    endif()

    # Compare components
    list(LENGTH VERSION1_LIST VERSION_LEN)
    set(COMPARE_RESULT 0)
    foreach(i RANGE 0 ${VERSION_LEN})
        if(i LESS VERSION_LEN)
            list(GET VERSION1_LIST ${i} V1_COMPONENT)
            list(GET VERSION2_LIST ${i} V2_COMPONENT)
            if(V1_COMPONENT GREATER V2_COMPONENT)
                set(COMPARE_RESULT 1)
                break()
            elseif(V1_COMPONENT LESS V2_COMPONENT)
                set(COMPARE_RESULT -1)
                break()
            endif()
        endif()
    endforeach()

    set(${result} ${COMPARE_RESULT} PARENT_SCOPE)
endfunction()

# Check for g++ and version
find_program(GPP_EXECUTABLE g++)
if(NOT GPP_EXECUTABLE)
    message(FATAL_ERROR "g++ not found. Please install g++ version ${MIN_GCC_VERSION} or later.")
endif()

execute_process(
    COMMAND ${GPP_EXECUTABLE} --version
    OUTPUT_VARIABLE GPP_VERSION_OUTPUT
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

string(REGEX MATCH "g\\+\\+ \\(.*\\) ([0-9]+\\.[0-9]+\\.[0-9]+)" GPP_VERSION_MATCH ${GPP_VERSION_OUTPUT})
if(GPP_VERSION_MATCH)
    set(GPP_VERSION ${CMAKE_MATCH_1})
    version_compare(${GPP_VERSION} ${MIN_GCC_VERSION} GPP_VERSION_OK)
    if(GPP_VERSION_OK LESS 0)
        message(FATAL_ERROR "g++ version ${GPP_VERSION} found, but version ${MIN_GCC_VERSION} or later is required.")
    else()
        message(STATUS "g++ version ${GPP_VERSION} found - OK")
    endif()
else()
    message(WARNING "Could not determine g++ version from: ${GPP_VERSION_OUTPUT}")
endif()

# Check for Verilator and version
find_program(VERILATOR_EXECUTABLE verilator)
if(NOT VERILATOR_EXECUTABLE)
    message(FATAL_ERROR "Verilator not found. Please install Verilator version ${MIN_VERILATOR_VERSION} or later.")
endif()

execute_process(
    COMMAND ${VERILATOR_EXECUTABLE} --version
    OUTPUT_VARIABLE VERILATOR_VERSION_OUTPUT
    ERROR_QUIET
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

string(REGEX MATCH "Verilator ([0-9]+\\.[0-9]+)" VERILATOR_VERSION_MATCH ${VERILATOR_VERSION_OUTPUT})
if(VERILATOR_VERSION_MATCH)
    set(VERILATOR_VERSION ${CMAKE_MATCH_1})
    version_compare(${VERILATOR_VERSION} ${MIN_VERILATOR_VERSION} VERILATOR_VERSION_OK)
    if(VERILATOR_VERSION_OK LESS 0)
        message(FATAL_ERROR "Verilator version ${VERILATOR_VERSION} found, but version ${MIN_VERILATOR_VERSION} or later is required.")
    else()
        message(STATUS "Verilator version ${VERILATOR_VERSION} found - OK")
    endif()
else()
    message(FATAL_ERROR "Could not determine Verilator version from: ${VERILATOR_VERSION_OUTPUT}")
endif()

# Check for Python and cocotb
find_package(Python3 REQUIRED COMPONENTS Interpreter)

execute_process(
    COMMAND ${Python3_EXECUTABLE} -c "import cocotb; print(cocotb.__version__)"
    OUTPUT_VARIABLE COCOTB_VERSION_OUTPUT
    ERROR_VARIABLE COCOTB_ERROR
    RESULT_VARIABLE COCOTB_RESULT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(COCOTB_RESULT EQUAL 0)
    set(COCOTB_VERSION ${COCOTB_VERSION_OUTPUT})
    version_compare(${COCOTB_VERSION} ${MIN_COCOTB_VERSION} COCOTB_VERSION_OK)
    if(COCOTB_VERSION_OK LESS 0)
        message(FATAL_ERROR "cocotb version ${COCOTB_VERSION} found, but version ${MIN_COCOTB_VERSION} or later is required.")
    else()
        message(STATUS "cocotb version ${COCOTB_VERSION} found - OK")
    endif()
else()
    message(FATAL_ERROR "cocotb not found or not importable. Please install cocotb version ${MIN_COCOTB_VERSION} or later.\nError: ${COCOTB_ERROR}")
endif()

# Check for pytest
execute_process(
    COMMAND ${Python3_EXECUTABLE} -c "import pytest; print(pytest.__version__)"
    OUTPUT_VARIABLE PYTEST_VERSION_OUTPUT
    ERROR_VARIABLE PYTEST_ERROR
    RESULT_VARIABLE PYTEST_RESULT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(PYTEST_RESULT EQUAL 0)
    message(STATUS "pytest version ${PYTEST_VERSION_OUTPUT} found - OK")
else()
    message(FATAL_ERROR "pytest not found or not importable. Please install pytest.\nError: ${PYTEST_ERROR}")
endif()

# Check for pytest-xdist
execute_process(
    COMMAND ${Python3_EXECUTABLE} -c "import xdist; print('pytest-xdist available')"
    OUTPUT_VARIABLE PYTEST_XDIST_OUTPUT
    ERROR_VARIABLE PYTEST_XDIST_ERROR
    RESULT_VARIABLE PYTEST_XDIST_RESULT
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(PYTEST_XDIST_RESULT EQUAL 0)
    message(STATUS "pytest-xdist found - OK")
else()
    message(FATAL_ERROR "pytest-xdist not found or not importable. Please install pytest-xdist.\nError: ${PYTEST_XDIST_ERROR}")
endif()

# Create pytest target
add_custom_target(pytest
    COMMAND ${Python3_EXECUTABLE} -m pytest --log-cli-level=INFO -n auto ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Running pytest with parallel execution"
    VERBATIM
)

# Print summary
message(STATUS "")
message(STATUS "=== Dependency Check Summary ===")
message(STATUS "g++: ${GPP_VERSION} (required: ${MIN_GCC_VERSION}+)")
message(STATUS "Verilator: ${VERILATOR_VERSION} (required: ${MIN_VERILATOR_VERSION}+)")
message(STATUS "cocotb: ${COCOTB_VERSION} (required: ${MIN_COCOTB_VERSION}+)")
message(STATUS "pytest: ${PYTEST_VERSION_OUTPUT}")
message(STATUS "pytest-xdist: Available")
message(STATUS "")
message(STATUS "All dependencies satisfied!")
message(STATUS "Run 'make pytest' or 'cmake --build . --target pytest' to execute tests")
message(STATUS "")
