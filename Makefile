.SUFFIXES: .xv6

# Using native tools (e.g., on X86 Linux)
TOOLPREFIX =

# If the makefile can't find QEMU, specify its path here
QEMU = qemu-system-i386

CC = $(TOOLPREFIX)cc
AS = $(TOOLPREFIX)as
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump
CFLAGS = -static -O2 -Wall -MD -ggdb -m32 -Werror -fno-pic -fno-builtin -fno-stack-protector -fno-strict-aliasing -fno-omit-frame-pointer
ASFLAGS = -m32 -gdwarf-2 -Wa,-divide

# LLVM+FreeBSD specific
LDFLAGS += -m elf_i386_fbsd
CFLAGS += -fno-pie

OBJS = \
	bio.o\
	console.o\
	exec.o\
	file.o\
	fs.o\
	ide.o\
	ioapic.o\
	kalloc.o\
	kbd.o\
	lapic.o\
	log.o\
	main.o\
	mp.o\
	picirq.o\
	pipe.o\
	proc.o\
	sleeplock.o\
	spinlock.o\
	string.o\
	swtch.o\
	syscall.o\
	sysfile.o\
	sysproc.o\
	trapasm.o\
	trap.o\
	uart.o\
	vectors.o\
	vm.o\

UPROGS=\
	cat.xv6\
	echo.xv6\
	forktest.xv6\
	grep.xv6\
	init.xv6\
	kill.xv6\
	ln.xv6\
	ls.xv6\
	mkdir.xv6\
	rm.xv6\
	sh.xv6\
	stressfs.xv6\
	usertests.xv6\
	wc.xv6\
	zombie.xv6\

ULIB = ulib.o usys.o printf.o umalloc.o

xv6.img: bootblock kernel
	dd if=/dev/zero of=xv6.img count=10000
	dd if=bootblock of=xv6.img conv=notrunc
	dd if=kernel of=xv6.img seek=1 conv=notrunc

fs.img: mkfs README $(UPROGS)
	./mkfs fs.img README $(UPROGS)

os.img: xv6.img fs.img
	cat xv6.img fs.img > os.img

bootblock: bootasm.S bootmain.c
	$(CC) $(CFLAGS) -fno-pic -Os -nostdinc -I. -c bootmain.c
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I. -c bootasm.S
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7C00 -o bootblock.o bootasm.o bootmain.o
	$(OBJDUMP) -S bootblock.o > bootblock.asm
	$(OBJCOPY) -S -O binary -j .text bootblock.o bootblock
	./sign.pl bootblock

entryother: entryother.S
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I. -c entryother.S
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7000 -o bootblockother.o entryother.o
	$(OBJCOPY) -S -O binary -j .text bootblockother.o entryother
	$(OBJDUMP) -S bootblockother.o > entryother.asm

initcode: initcode.S
	$(CC) $(CFLAGS) -nostdinc -I. -c initcode.S
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o initcode.out initcode.o
	$(OBJCOPY) -S -O binary initcode.out initcode
	$(OBJDUMP) -S initcode.o > initcode.asm

kernel: $(OBJS) entry.o entryother initcode kernel.ld
	$(LD) $(LDFLAGS) -T kernel.ld -o kernel entry.o $(OBJS) -b binary initcode entryother
	$(OBJDUMP) -S kernel > kernel.asm

vectors.S: vectors.pl
	./vectors.pl > vectors.S

.o.xv6: $(ULIB)
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $< $(ULIB)
	$(OBJDUMP) -S $@ > $*.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $*.sym

forktest.xv6: forktest.o $(ULIB)
	# forktest has less library code linked in - needs to be small
	# in order to be able to max out the proc table.
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o forktest.xv6 forktest.o ulib.o usys.o
	$(OBJDUMP) -S forktest.xv6 > forktest.asm

mkfs: mkfs.c fs.h
	$(CC) -Werror -Wall -o mkfs mkfs.c

clean: 
	rm -f *.tex *.dvi *.idx *.aux *.log *.ind *.ilg \
	*.o *.d *.asm *.sym vectors.S bootblock entryother \
	initcode initcode.out kernel xv6.img fs.img os.img \
	kernelmemfs xv6memfs.img mkfs .gdbinit \
	$(UPROGS)

CPUS     = 2
QEMUOPTS = -drive file=os.img,index=0,media=disk,format=raw -smp $(CPUS) -m 512

qemu: os.img
	$(QEMU) -serial mon:stdio $(QEMUOPTS)
