
- **Available Benchmarks (all fully functional):**
    - Image Classification
    - Anomaly Detection
    - Person Detection
    - Keyword Spotting
- **Location:**
    - Benchmarks are located in the `tflite-micro` directory under `examples`
- **Program Structure:**
    - all benchmarks share a similar structure
    - the main differences are in how the input is handled (e.g., via header files or by reading .bin files for inference)
- **Optimizations:**
    - no optimizations have been performed so far
    - models come directly from the MLPerf Tiny Repository, and the benchmark files adapted for RISC-V and tflite-micro are standard

**Folder structure for my current workflow:**
```
k230_sdk
	|-- ...
	|-- toolchain
			|-- riscv64-linux-musleabi_for_x86_64-pc-linux-gnu
			|-- Xuantie-900-gcc-linux-5.10.4-glibc-x86_64-V2.6.0
tflite-micro
	|-- ...
	|-- tensorflow
			|-- lite
				|-- micro
					|-- examples
						|-- ...
						|-- mlperf_riscv_anomaly_detection
								|-- main.cc
								|-- ...
						|-- mlperf_riscv_image_classification
								|-- main.cc
								|-- ...
						|-- mlperf_riscv_keyword_spotting
							    |-- main.cc
								|-- ...
						|-- mlperf_riscv_person_detection
								|-- main.cc
								|-- ...
						|-- ...
					|-- ...
					|-- tools
						|-- make
							|-- targets
							|-- ...
							|-- riscv_isa_elf_rv64imafdc_makefile.inc
						    |-- riscv_isa_elf_rv64imafdcv_makefile.inc
						    |-- riscv_isa_musl_rv64imafdc_makefile.inc
						    |-- riscv_isa_musl_rv64imafdcv_makefile.inc
						    |-- ...
toolchain
	|-- riscv_elf
			|-- bin
				|-- riscv64-unknown-linux-elf-gcc
				|-- ...
			|-- ...
	|-- riscv_musl
			|-- bin
				|-- riscv64-unknown-linux-musl-gcc
				|-- ...
			|-- ...
	|-- riscv_musl_gc
			|-- bin
				|-- riscv64-unknown-linux-musl-gcc
				|-- ...
			|-- ...
build_script.sh

```

---

### Build Workflow via a Bash Script

- **Custom Bash Script:**
    - automates the compilation and linking process
- **Main Steps:**
    - **Model Selection:**
        
        - a menu allows you to choose which benchmark to compile, or to select just the linking step or cleaning
    - **Toolchain Selection:**
        - two main toolchain options:
            - **GNU Toolchain without V Extension:**
                - uses `riscv64-unknown-elf-gcc`
                - no separate linking step is needed
            - **Musl Toolchain (with or without V Extension):**
                - both variants use `riscv64-unknown-linux-musl-gcc`
                - a separate linking step is performed using the Canaan proprietary toolchain (available only as a binary distribution)
    - **Compilation:**
        - when a benchmark is selected (and not just linking or cleaning), the script compiles using the Makefile in the `tflite-micro` directory
        - the appropriate TARGET parameter is set (e.g., `riscv_isa_rv64imafdc` or `riscv_isa_rv64imafdcv`)
    - **Linking:**
        - for the Musl toolchain, a special linking step is performed using the Canaan toolchain.
        - .o files are combined, excluding `hexdump_test.o` (which has its own main function and is only used for compilation testing)
        - the linker options vary based on the chosen toolchain version:
            - With V Extension: use `-march=rv64imafdcv`
            - Without V Extension: use `-march=rv64imafdc`

		- **Compilation with the Toolchain without V Extension:**
		    - the Canaan toolchain (used for linking) is built with V extension support
		    - my program is compiled without V extension
		    - for linking, I use the options:  
		        `mcmodel=medany -march=rv64imafdc -mabi=lp64d`
		- **Compilation with the Toolchain with V Extension:**
		    - the Canaan toolchain is built with V extension support
			- my program is also compiled with V extension
		    - for linking, I use the options:  
		        `mcmodel=medany -march=rv64imafdcv -mabi=lp64d`

    - **Deployment:**
        - after successful compilation and linking, the resulting ELF file is copied to the K230 board using `scp`
        - the file is then executed on the Big Core via `screen /dev/ttyAMC1 115200`

### Bash-Script

_build-script.sh_
```
#!/bin/bash

set -e  # exit immediately if any command fails

# display model selection menu
echo "Select the model you want to compile:"
echo "1) mlperf_riscv_image_classification"
echo "2) mlperf_riscv_person_detection"
echo "3) mlperf_riscv_keyword_spotting"
echo "4) mlperf_riscv_anomaly_detection"
echo "5) Only Linking"
echo "6) Only Clean"
echo "7) Exit"

# read user input for the model
read -p "Enter a number (1-7): " model_selection

# assign the chosen target program
case $model_selection in
    1) TARGET_PROGRAM="mlperf_riscv_image_classification" ;;
    2) TARGET_PROGRAM="mlperf_riscv_person_detection" ;;
    3) TARGET_PROGRAM="mlperf_riscv_keyword_spotting" ;;
    4) TARGET_PROGRAM="mlperf_riscv_anomaly_detection" ;;
    5) ONLY_LINK=true ;;
    6) ONLY_CLEAN=true ;;
    7) echo "Exiting."; exit 0 ;;
    *) echo "Invalid selection."; exit 1 ;;
esac

# Step 1: run make clean
echo -e "\nStep 1: Running make clean..."
make -j$(nproc) -f tflite-micro/tensorflow/lite/micro/tools/make/Makefile clean

# if only clean is chosen - exiting
if [ "$ONLY_CLEAN" = true ]; then
    echo "Only make clean completed. Exiting."
    exit 0
fi

# if only linking is chosen, we need a target
if [ "$ONLY_LINK" = true ]; then
    echo -e "\nYou chose only the linking step. Please select the toolchain:"
else
    echo -e "\nSelect the toolchain to use:"
fi

echo "1) GNU Toolchain without V Extension (riscv64-unknown-elf-gcc)"
echo "2) Musl Toolchain with V Extension (riscv64-unknown-linux-musl-gcc)"
echo "3) Musl Toolchain without V Extension (riscv64-unknown-linux-musl-gcc)"
echo "4) Exit"

# read user input for the toolchain
read -p "Enter a number (1-4): " toolchain_selection

# assign the chosen toolchain
case $toolchain_selection in
    1) TOOLCHAIN="riscv64-unknown-elf-gcc" 
       TARGET="riscv_isa_elf_rv64imafdc"
       LINKING_REQUIRED=false  # no additional linking step for GNU Toolchain
       ;;
    2) TOOLCHAIN="riscv64-unknown-linux-musl-gcc" 
       TARGET="riscv_isa_musl_rv64imafdcv"
       LINKING_TOOLCHAIN_PATH="k230_sdk/toolchain/riscv64-linux-musleabi_for_x86_64-pc-linux-gnu/bin/riscv64-unknown-linux-musl-gcc"
       LINKING_REQUIRED=true  # perform linking only for Musl
       LINKING_IMAFDCV=true # perform linking only for riscv_isa_rv64imafdcv
       ;;
    3) TOOLCHAIN="riscv64-unknown-linux-musl-gcc" 
       TARGET="riscv_isa_musl_rv64imafdc"
       LINKING_TOOLCHAIN_PATH="k230_sdk/toolchain/riscv64-linux-musleabi_for_x86_64-pc-linux-gnu/bin/riscv64-unknown-linux-musl-gcc"
       LINKING_REQUIRED=true  # perform linking only for Musl
       LINKING_IMAFDC=true # perform linking only for riscv_isa_rv64imafdc
       ;;
    4) echo "Exiting."; exit 0 ;;
    *) echo "Invalid selection."; exit 1 ;;
esac

# if only linking is chosen, go to step 3
if [ "$ONLY_LINK" = true ]; then
    echo -e "\nSkipping compilation. Only linking..."
    LINKING_REQUIRED=true  # Setze Linking auf True
else
    echo -e "\nSelected model: $TARGET_PROGRAM"
    echo "Selected toolchain: $TOOLCHAIN"

    # Step 2: compile the selected model using the selected toolchain
    echo -e "\nStep 2: Compiling with $TOOLCHAIN..."
    make -j$(nproc) -f tflite-micro/tensorflow/lite/micro/tools/make/Makefile TARGET=$TARGET $TARGET_PROGRAM
fi

# Step 3: linking (only for musl Toolchain)
if [ "$LINKING_REQUIRED" = true ] && [ "$LINKING_IMAFDCV" = true ]; then
    echo -e "\nStep 3: Linking with $TOOLCHAIN..."

    TARGET_DIR="gen/${TARGET}_x86_64_default_gcc/obj/"

    $LINKING_TOOLCHAIN_PATH -o "${TARGET_PROGRAM}_${TARGET}.elf" -mcmodel=medany -march=rv64imafdcv -mabi=lp64d \
        -T k230_sdk/src/big/mpp/userapps/sample/linker_scripts/riscv64/link.lds \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/rt-thread/lib \
        -Wl,--whole-archive -lrtthread -Wl,--no-whole-archive -n --static \
        $(find "$TARGET_DIR" -name "*.o" ! -name "hexdump_test.o") \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/lib/risc-v/rv64 \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/rt-thread/lib/risc-v/rv64 \
        -Wl,--start-group -lrtthread -Wl,--no-warn-rwx-segments,--end-group

    echo -e "\nCompilation completed successfully: ${TARGET_PROGRAM}_${TARGET}.elf"

elif [ "$LINKING_REQUIRED" = true ] && [ "$LINKING_IMAFDC" = true ]; then
    echo -e "\nStep 3: Linking with $TOOLCHAIN..."

    TARGET_DIR="gen/${TARGET}_x86_64_default_gcc/obj/"

    $LINKING_TOOLCHAIN_PATH -o "${TARGET_PROGRAM}_${TARGET}.elf" -mcmodel=medany -march=rv64imafdc -mabi=lp64d \
        -T k230_sdk/src/big/mpp/userapps/sample/linker_scripts/riscv64/link.lds \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/rt-thread/lib \
        -Wl,--whole-archive -lrtthread -Wl,--no-whole-archive -n --static \
        $(find "$TARGET_DIR" -name "*.o" ! -name "hexdump_test.o") \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/lib/risc-v/rv64 \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/rt-thread/lib/risc-v/rv64 \
        -Wl,--start-group -lrtthread -Wl,--no-warn-rwx-segments,--end-group

    echo -e "\nCompilation completed successfully: ${TARGET_PROGRAM}_${TARGET}.elf"
else
    echo -e "\nSkipping linking step (Not required for GNU Toolchain)."
fi
```

---

### Special Considerations for Toolchain Integration

- **Different Toolchains for Compilation and Linking:**
    
    - compilation is done with the RISCV GNU toolchain (Musl), either with or without the V Extension
    - the program is then linked with the Canaan toolchain because the K230 board’s Big Core (RISC-V with V Extension) requires a specific linking process
    - **Question:**
        - _Is it fundamentally possible to use different toolchains (one for compilation and one for linking)?_
        - my experiments suggest that it is possible if ABI and architecture parameters are passed consistently
- **Linking Exception:**
    - `hexdump_test.o` is explicitly excluded to avoid conflicts with my main function and because it is only used for compilation tests of tflite-micro

#### Example
**riscv_isa_musl_rv64imafdcv_makefile.inc** in 
`tflite-micro/tensorflow/lite/micro/tools/make/targets`

```
# Settings for RISCV 64-bit toolchain.
TARGET_ARCH := riscv64
TARGET_TOOLCHAIN_PREFIX := riscv64-unknown-linux-musl-

RISCV_ARCH := rv64imafdcv
RISCV_ABI := lp64d
RISCV_CODE_MODEL := medany

# Allow additional flags on the command line for debugging.
# Flag for the big core to compute the timestamp with rdcycle in submitter_implemented.cc
RISCV_EXTRA_CFLAGS += -DBIG_CORE
  
#TARGET_DEFAULT_TOOLCHAIN_ROOT := $(DOWNLOADS_DIR)/riscv_toolchain/bin/
TARGET_DEFAULT_TOOLCHAIN_ROOT := $(TENSORFLOW_ROOT)/../toolchain/riscv_musl/bin/
TARGET_TOOLCHAIN_ROOT := $(TARGET_DEFAULT_TOOLCHAIN_ROOT)
ifeq ($(TARGET_TOOLCHAIN_ROOT), $(TARGET_DEFAULT_TOOLCHAIN_ROOT))
  $(eval $(call add_third_party_download,$(RISCV_TOOLCHAIN_URL),$(RISCV_TOOLCHAIN_MD5),riscv_toolchain,))
endif

export PATH := $(TARGET_TOOLCHAIN_ROOT):$(PATH)

PLATFORM_FLAGS = \
  -march=$(RISCV_ARCH) \
  -mabi=$(RISCV_ABI) \
  -mcmodel=$(RISCV_CODE_MODEL) \
  -mexplicit-relocs \
  -funsigned-char \
  -fno-delete-null-pointer-checks \
  -fomit-frame-pointer \
  -DTF_LITE_MCU_DEBUG_LOG \
  -DTF_LITE_USE_GLOBAL_CMATH_FUNCTIONS

CXXFLAGS += $(PLATFORM_FLAGS) \
  -fpermissive \
  -fno-use-cxa-atexit \
  -DTF_LITE_USE_GLOBAL_MIN \
  -DTF_LITE_USE_GLOBAL_MAX

CCFLAGS += $(PLATFORM_FLAGS)

BUILD_TYPE := micro

#LDFLAGS += --specs=nano.specs
LDFLAGS := $(filter-out --specs=nano.specs,$(LDFLAGS))

$(info PLATFORM_FLAGS: $(PLATFORM_FLAGS))
$(info LDFLAGS: $(LDFLAGS))

# See http://b/158651472 for why memory arena threshold test is disabled.
EXCLUDED_TESTS := \
  $(TENSORFLOW_ROOT)tensorflow/lite/micro/memory_arena_threshold_test.cc

MICROLITE_TEST_SRCS := $(filter-out $(EXCLUDED_TESTS), $(MICROLITE_TEST_SRCS))

CCFLAGS += $(RISCV_EXTRA_CFLAGS)
CXXFLAGS += $(RISCV_EXTRA_CFLAGS)

# This disables the "linker relaxation" optimization, which produced incorrect code.
# TODO(b/279805615): Check whether this is fixed in newer versions of the toolchain.
LDFLAGS += -mno-relax

```
---

### Initial Results and Observations

- **Benchmark: "Image Classification"**

    - **With V Extension:**
        - output includes entries like `m-lap-us`, `m-cycles-count`, `m-instret-count`, etc
        - `objdump` shows vector instructions (e.g., `vmv.*`, `vadd.vv`, `vsub.vv`, etc)
        - the resulting ELF file is approximately 1.2 MB in size

    - **Without V Extension:**
		- the output measurements are similar, with nearly identical numbers
		- `objdump` does not show any vector instructions
		- the ELF file is processed with a strip command to remove the `.riscv.attributes` section:
		    - Command:  
			    `k230_sdk/toolchain/riscv64-linux-musleabi_for_x86_64-pc-linux-gnu/bin/riscv64-unknown-linux-musl-strip --remove-section=.riscv.attributes mlperf_riscv_image_classification_riscv_isa_musl_rv64imafdc.elf`
		- after stripping, the resulting ELF file is approximately 722 KB in size
		- `objdump` confirms that no vector instructions are present

- **Observation:**
    - despite using the V Extension, no performance improvement or reduction in instruction count has been observed
    - runtimes, cycles, and instruction counts are nearly identical
- **Possible Explanations:**
    - tflite-micro might be so heavily optimized that the benefits of vector instructions are not significant
    - further code optimizations or adjustments may be necessary to fully leverage the V Extension

| with V extension                                                                                                                                                                                                                                                                                                                                                                                                                                         | without V extension                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| infer 50 10<br>m-warmup-start-10<br>m-warmup-done<br>m-infer-start-50<br>m-lap-us-2789341993<br>m-lap-us-2819586832<br>m-infer-done<br>m-results-[0.992,0.000,0.004,0.0000, ...<br>m-cycles-count-48388688109<br>m-instret-count-30385035484<br>m-cycles-count-per-infer-967773762.18<br>m-cycles-per-instructions-1.59<br>m-runtime-us-30244839<br>m-runtime-sec-30.244839<br>m-latency-us-604896.78<br>m-latency-sec-0.604897<br>m-throughput-IPS-1.65 | infer 50 10<br>m-warmup-start-10<br>m-warmup-done<br>m-infer-start-50<br>m-lap-us-2861285462<br>m-lap-us-2891525818<br>m-infer-done<br>m-results-[0.992,0.000,0.004,0.000, ...<br>m-cycles-count-48381514787<br>m-instret-count-30385023379<br>m-cycles-count-per-infer-967630295.74<br>m-cycles-per-instructions-1.59<br>m-runtime-us-30240356<br>m-runtime-sec-30.240356<br>m-latency-us-604807.12<br>m-latency-sec-0.604807<br>m-throughput-IPS-1.65 |

---

### Measurement Methodology and Calculations

- **Measuring Cycles ("m-cycles-count"):**
    
    - **Method:**
        - uses the RISC-V assembly instruction `rdcycle` to read the current cycle count
    - **Calculation:**
        - the difference between start and end cycles is divided by the CPU frequency to calculate elapsed time
        - standard clock frequencies: 1.6 GHz for the big core and 800 MHz for the small core

[[https://developer.canaan-creative.com/k230/en/rtt/dev/02_applications/tutorials/K230_Boot_Optimization_Guide.html]]

> The CPU core of K230 is RISCV. Users can use the following code in any software on the large or small core to get the current time.
> 
> uint64_t perf_get_smodecycles(void)
> {
>     uint64_t cnt;
>     __asm__ __volatile__(
>         "rdcycle %0" : "=r"(cnt)
>     );
>     return cnt;
> }
> 
> The obtained value is the number of clock cycles the CPU has run. Dividing it by the CPU frequency gives the current running time. The default clock frequency of the large core in k230_sdk is 1.6GHz, and the clock frequency of the small core is 800MHz.


- **Measuring Instruction Count ("m-instret-count"):**
    
    - **Method:**
        - uses `rdinstret` to count the executed instructions exactly like `rdcycle`
    - **Further Calculations:**
        - Cycle count per inference
        - CPI (Cycles per Instruction)
        - Total runtime in microseconds and seconds
        - Latency per inference
        - Throughput (in inferences per second, IPS)

```
uint64_t cycle_count = end_cycles - start_cycles;
double cycle_count_per_infer = (double) cycle_count / (double) total_inferences;
uint64_t instret_count = end_instret - start_instret;
double cpi = (double) cycle_count / (double) instret_count;
unsigned long runtime_us = end_time - start_time;
double runtime_sec = (double) runtime_us / 1e6; // convert microsec to sec
double latency_us = (double) runtime_us / (double) total_inferences;
double latency_sec = latency_us / 1e6;  // convert microsec to sec
// IPS = 1,000,000 / latency in µs
double throughput = 1e6 / latency_us;
```

---

### Open Questions and Further Considerations

- **Toolchain and Linking Process:**

	- **Expectation:**
	    - using different toolchains for compilation and linking should work seamlessly without introducing errors or performance penalties
	- **Observation:**
	    - the current setup successfully compiles with the RISCV GNU toolchain and links with the Canaan toolchain, but it's unclear if any subtle issues might affect performance or compatibility
	- **Question:**
	    - _Could using two different toolchains (one for compilation and one for linking) lead to unforeseen compatibility issues or impact runtime performance?_

- **Performance Benefits of the V Extension:**
    
    - **Expectation:**
        - the program should run faster with the V Extension
    - **Observation:**
        - both variants (with and without the V Extension) yield nearly identical results
    - **Question:**
        - _Is tflite-micro already so optimized, or is there still room for optimization or potential issues in the system?_

- **Benchmark and Performance Measurements:**

	- **Expectation:**
	    - if the V Extension provides a performance benefit, the benchmark results should reflect lower cycle counts, reduced instruction counts, and improved runtimes when using it
	- **Observation:**
	    - both variants (with and without the V Extension) yield nearly identical results in terms of cycles, instruction counts, and runtime
	- **Question:**
	    - _Are the current measurement methods (using `rdcycle` and `rdinstret`) sufficient to capture all performance improvements, or might there be hidden factors that need to be considered?_

- **Compiler Optimizations and Auto-Vectorization:**

	- **Observation:**
	    - the compiler might be auto-vectorizing the code, potentially obscuring the benefits of the V Extension.
	- **Possible Action:**
	    - disable auto-vectorization explicitly (using flags such as `-fno-tree-vectorize`, `-fno-tree-loop-vectorize`, and `-fno-tree-slp-vectorize`) to see if performance metrics change.
	- **Question:**
	    - _Could disabling auto-vectorization reveal whether it is currently masking the expected performance benefits of the V Extension?_