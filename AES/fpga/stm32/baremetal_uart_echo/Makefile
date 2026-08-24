# Tool information. Prefer arm-none-eabi-* on PATH. A portable shared copy
# may instead set ARM_GNU_TOOLCHAIN_DIR to the extracted Arm GNU Toolchain
# directory; no workstation-specific absolute path is stored here.
TARGET			?= arm-none-eabi
ifeq ($(strip $(ARM_GNU_TOOLCHAIN_DIR)),)
TOOL_PREFIX		:= $(TARGET)-
else
TOOL_PREFIX		:= $(subst \,/,$(ARM_GNU_TOOLCHAIN_DIR))/bin/$(TARGET)-
endif

# Project name & Link script
OUT_FILE_NAME 	= rom_0x08000000
LDS_FILE_NAME	= rom_0x08000000.lds

# Compiler & Linker options: Cortex-M4F, single-precision hardware FPU
CFLAGS  		= -mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard -DSTM32F411xE 
CFLAGS 			+= -std=gnu99 -O3 -Wall -g -c -fno-builtin -funsigned-char -fno-strict-aliasing -fno-common
LDFLAGS 		= -mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard
LDFLAGS    		+= --specs=nano.specs --specs=nosys.specs -u _printf_float -nostartfiles -ffreestanding
LDFLAGS    		+= -Wl,-Map=$(OUT_FILE_NAME).map -Wl,--cref -Wl,-EL -T $(LDS_FILE_NAME)

# Output File definition
OUT_BIN_FILE	= $(OUT_FILE_NAME).bin
OUT_ELF_FILE	= $(OUT_FILE_NAME).elf
OUT_MAP_FILE	= $(OUT_FILE_NAME).map
OUT_DUMP_FILE	= $(OUT_FILE_NAME).dmp

# Tool setting
AS				= "$(TOOL_PREFIX)as"
CC				= "$(TOOL_PREFIX)gcc"
LD 				= "$(TOOL_PREFIX)ld"
OBJCOPY			= "$(TOOL_PREFIX)objcopy"
OBJDUMP			= "$(TOOL_PREFIX)objdump"

# Source & Header File 
CSRC 			= $(wildcard *.c)
ASRC 			= $(wildcard *.s)
HEADER 			= $(wildcard *.h)
OBJS    		= $(CSRC:.c=.o) $(ASRC:.s=.o)
DUMP 			= $(wildcard *.txt)

# Let the GCC driver select matching multilib/include directories. This keeps
# the project compatible with newer Arm GNU Toolchain releases.
LIB_OPTION		= -lc -lgcc
INCLUDE			= -I.

all : $(OUT_BIN_FILE)

$(OUT_BIN_FILE): $(OUT_ELF_FILE)
	$(OBJCOPY) $(OUT_ELF_FILE) $(OUT_BIN_FILE) -O binary
	$(OBJDUMP) -x -D ./$(OUT_ELF_FILE) > ./__dump.txt
	$(OBJDUMP) -x -D -S ./$(OUT_ELF_FILE) > ./__dump_all.txt

$(OUT_FILE_NAME).elf: $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) $(LIB_OPTION) -o $@

$(OBJS): $(ASRC) $(CSRC) $(HEADER)
	$(CC) $(ASRC) $(CSRC) $(INCLUDE) $(CFLAGS) 

clean :
	rm -f $(OUT_BIN_FILE)
	rm -f $(OUT_ELF_FILE)
	rm -f $(OUT_MAP_FILE)
	rm -f $(OBJS)
	rm -f $(DUMP)

run: # for STM32CubeProgrammer
	STM32_Programmer_CLI.exe -c port=SWD -w ./rom_0x08000000.elf -v -rst -q	
