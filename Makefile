ASM=nasm
CC=gcc

SRC_DIR=src
BUILD_DIR=build
TEST_DIR=test

.PHONY : all floppy_image kernel bootloader clean always
# all: test_fat

#
# Floppy disk image
#
floppy_image: $(BUILD_DIR)/main_floppy.img

$(BUILD_DIR)/main_floppy.img: bootloader kernel
	dd if=/dev/zero of=$(BUILD_DIR)/main_floppy.img bs=512 count=2880
	mkfs.fat -F 12 -n "OS" $(BUILD_DIR)/main_floppy.img
	dd conv=notrunc if=$(BUILD_DIR)/bootloader.bin of=$(BUILD_DIR)/main_floppy.img
	mcopy -i $(BUILD_DIR)/main_floppy.img $(BUILD_DIR)/kernel.bin "::kernel.bin"
	mcopy -i $(BUILD_DIR)/main_floppy.img test.txt "::test.txt"

#
# Bootloader
#
bootloader: $(BUILD_DIR)/bootloader.bin

$(BUILD_DIR)/bootloader.bin: always
	$(ASM) $(SRC_DIR)/bootloader/boot.asm -f bin -o $(BUILD_DIR)/bootloader.bin

#
# Kernel
#
kernel: $(BUILD_DIR)/kernel.bin

$(BUILD_DIR)/kernel.bin: always
	$(ASM) $(SRC_DIR)/kernel/kernel.asm -f bin -o $(BUILD_DIR)/kernel.bin

#
# Test fat
#
test_fat: $(TEST_DIR)/fat.c
$(TEST_DIR)/fat.c: always
	$(CC) -g $(TEST_DIR)/fat.c -o $(BUILD_DIR)/fat

#
# Clean
#
clean:
	rm -rf $(BUILD_DIR)/*

#
# Always
#
always:
	mkdir -p $(BUILD_DIR)