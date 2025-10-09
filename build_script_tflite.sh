#!/bin/bash

set -e  # exit immediately if any command fails

# Download and set up toolchains (ubuntu 22.04) - risc-v musl toolachain, newlib toolchain and canmv-K230 toolchain
mkdir -p "$(dirname "$0")"/toolchain
cd "$(dirname "$0")"/toolchain

wget https://download.rt-thread.org/rt-smart/riscv64/riscv64-unknown-linux-musl-rv64imafdcv-lp64d-20230222.tar.bz2 
tar -xjf riscv64-unknown-linux-musl-rv64imafdcv-lp64d-20230222.tar.bz2

mkdir -p riscv64-musl-ubuntu-22.04-gcc
wget https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2025.09.28/riscv64-musl-ubuntu-22.04-gcc-nightly-2025.09.28-nightly.tar.xz 
tar -xJf riscv64-musl-ubuntu-22.04-gcc-nightly-2025.09.28-nightly.tar.xz -C riscv64-musl-ubuntu-22.04-gcc

mkdir -p riscv64-elf-ubuntu-22.04-gcc
wget https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2025.09.28/riscv64-elf-ubuntu-22.04-gcc-nightly-2025.09.28-nightly.tar.xz
tar -xJf riscv64-elf-ubuntu-22.04-gcc-nightly-2025.09.28-nightly.tar.xz -C riscv64-elf-ubuntu-22.04-gcc
cd - || exit

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

# if only clean is chosen - execute clean and exit
if [ "$ONLY_CLEAN" = true ]; then
    echo -e "\nRunning make clean..."
    make -j$(nproc) -f tflite-micro/tensorflow/lite/micro/tools/make/Makefile clean
    echo "Clean completed. Exiting."
    exit 0
fi

# Step 1: run make clean unless ONLY_LINK is true
if [ "$ONLY_LINK" != true ]; then
    echo -e "\nStep 1: Running make clean..."
    make -j$(nproc) -f tflite-micro/tensorflow/lite/micro/tools/make/Makefile clean
fi

# Toolchain selection
if [ "$ONLY_LINK" = true ]; then
    echo -e "\nYou chose only the linking step. Please select the toolchain:"
else
    echo -e "\nSelect the toolchain to use:"
fi

echo "1) GNU Toolchain without V Extension (riscv64-unknown-elf-gcc)"
echo "2) Musl Toolchain with V Extension (riscv64-unknown-linux-musl-gcc)"
echo "3) Musl Toolchain without V Extension (riscv64-unknown-linux-musl-gcc)"
echo "4) Exit"

read -p "Enter a number (1-4): " toolchain_selection

# assign the chosen toolchain
case $toolchain_selection in
    1) TOOLCHAIN="riscv64-unknown-elf-gcc" 
       TARGET="riscv_isa_elf_rv64imafdc"
       LINKING_REQUIRED=false
       ;;
    2) TOOLCHAIN="riscv64-unknown-linux-musl-gcc" 
       TARGET="riscv_isa_musl_rv64imafdcv"
       LINKING_TOOLCHAIN_PATH="./toolchain/riscv64-linux-musleabi_for_x86_64-pc-linux-gnu/bin/riscv64-unknown-linux-musl-g++"
       LINKING_REQUIRED=true
       LINKING_IMAFDCV=true
       ;;
    3) TOOLCHAIN="riscv64-unknown-linux-musl-gcc" 
       TARGET="riscv_isa_musl_rv64imafdc"
       LINKING_TOOLCHAIN_PATH="./toolchain/riscv64-linux-musleabi_for_x86_64-pc-linux-gnu/bin/riscv64-unknown-linux-musl-g++"
       LINKING_REQUIRED=true
       LINKING_IMAFDC=true
       ;;
    4) echo "Exiting."; exit 0 ;;
    *) echo "Invalid selection."; exit 1 ;;
esac

# if only linking is chosen, skip compilation
if [ "$ONLY_LINK" = true ]; then
    echo -e "\nSkipping compilation. Only linking..."
else
    echo -e "\nSelected model: $TARGET_PROGRAM"
    echo "Selected toolchain: $TOOLCHAIN"

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
        -Wl,--whole-archive -lrtthread -lpthread -Wl,--no-whole-archive -n --static \
        $(find "$TARGET_DIR" -name "*.o" ! -name "hexdump_test.o") \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/lib/risc-v/rv64 \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/rt-thread/lib/risc-v/rv64 \
        -Wl,--start-group -lrtthread -lpthread -Wl,--no-warn-rwx-segments,--end-group

    echo -e "\nCompilation completed successfully: ${TARGET_PROGRAM}_${TARGET}.elf"

elif [ "$LINKING_REQUIRED" = true ] && [ "$LINKING_IMAFDC" = true ]; then
    echo -e "\nStep 3: Linking with $TOOLCHAIN..."

    TARGET_DIR="gen/${TARGET}_x86_64_default_gcc/obj/"

    $LINKING_TOOLCHAIN_PATH -o "${TARGET_PROGRAM}_${TARGET}.elf" -mcmodel=medany -march=rv64imafdc -mabi=lp64d \
        -T k230_sdk/src/big/mpp/userapps/sample/linker_scripts/riscv64/link.lds \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/rt-thread/lib \
        -Wl,--whole-archive -lrtthread -lpthread -Wl,--no-whole-archive -n --static \
        $(find "$TARGET_DIR" -name "*.o" ! -name "hexdump_test.o") \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/lib/risc-v/rv64 \
        -Lk230_sdk/src/big/rt-smart/userapps/sdk/rt-thread/lib/risc-v/rv64 \
        -Wl,--start-group -lrtthread -lpthread -Wl,--no-warn-rwx-segments,--end-group

    echo -e "\nCompilation completed successfully: ${TARGET_PROGRAM}_${TARGET}.elf"
else
    echo -e "\nSkipping linking step (Not required for GNU Toolchain)."
fi