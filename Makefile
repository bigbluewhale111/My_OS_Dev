ASM=nasm

SRC_DIR=src
BUILD_DIR=build

.PHONY : all floppy_image kernel bootloader clean always

#
# Floppy disk image
#
floppy_image: $(BUILD_DIR)/main_floppy.img

$(BUILD_DIR)/main_floppy.img: bootloader kernel
	dd if=/dev/zero of=$(BUILD_DIR)/main_floppy.img bs=512 count=2880
	mkfs.fat -F 12 -n "OS" $(BUILD_DIR)/main_floppy.img
	dd conv=notrunc if=$(BUILD_DIR)/bootloader.bin of=$(BUILD_DIR)/main_floppy.img
	mcopy -i $(BUILD_DIR)/main_floppy.img $(BUILD_DIR)/kernel.bin ::
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
# Clean
#
clean:
	rm -rf $(BUILD_DIR)/*

#
# Always
#
always:
	mkdir -p $(BUILD_DIR)