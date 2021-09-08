MKDIR ?= mkdir -p
CP ?= cp
CAT ?= cat
TAR ?= tar
PWD = $(shell pwd)
SUDO ?= $(and $(filter pip,$(shell whoami)),sudo)
NATIVE_TRIPLE ?= amd64-linux-gnu
BUILD ?= $(PWD)/build

.SECONDEXPANSION:

.SECONDARY: %

define COPY
	$(MKDIR) -p $(dir $@)
	$(CP) -a $< $@
endef

include g/github/github.mk

all: $(BUILD)/qemu-kernel $(BUILD)/debian/debootstrap/stage2.cpio

build/%:
	$(MAKE) $(PWD)/build/$*

%/:
	$(MKDIR) $@

.PHONY: %}

$(BUILD)/debian/debootstrap/stage1.tar: | $(BUILD)/debian/debootstrap/
	sudo rm -rf $(BUILD)/debian/debootstrap/stage1
	sudo debootstrap --foreign --arch=arm64 --include=build-essential,git,linux-image-cloud-arm64,bash,kmod,dash,wget,busybox,busybox-static,net-tools,libpam-systemd,file,xsltproc,mtools,openssl,mokutil,libx11-data,libx11-6,sharutils,dpkg-dev,zsh sid $(BUILD)/debian/debootstrap/stage1 http://deb.debian.org/debian
	(cd $(BUILD)/debian/debootstrap/stage1; sudo tar c .) > $@
	sudo rm -rf $(BUILD)/debian/debootstrap/stage1

$(BUILD)/debian/debootstrap/stage15.tar: $(BUILD)/debian/debootstrap/stage1.tar stage2/init
	sudo rm -rf $(BUILD)/debian/debootstrap/stage15
	$(MKDIR) $(BUILD)/debian/debootstrap/stage15
	(cd $(BUILD)/debian/debootstrap/stage15; sudo tar x) < $<
	(cd $(BUILD)/debian/debootstrap/stage15/var/cache/apt/archives/; for a in *.deb; do sudo dpkg-deb -R $$a $$a.d; sudo dpkg-deb -b -Znone $$a.d; sudo mv $$a.d.deb $$a; sudo rm -rf $$a.d; done)
	for a in $(BUILD)/debian/debootstrap/stage15/var/cache/apt/archives/*.deb; do sudo dpkg -x $$a $(BUILD)/debian/debootstrap/stage15; done
	sudo rm -f $(BUILD)/debian/debootstrap/stage15/init
	sudo cp -f stage2/init $(BUILD)/debian/debootstrap/stage15
	sudo chmod u+x $(BUILD)/debian/debootstrap/stage15/init
	(cd $(BUILD)/debian/debootstrap/stage15; sudo tar c .) > $@
	sudo rm -rf $(BUILD)/debian/debootstrap/stage15

$(BUILD)/qemu-kernel: $(BUILD)/debian/debootstrap/stage15.tar
	sudo rm -rf $(BUILD)/qemu-kernel.d
	mkdir -p $(BUILD)/qemu-kernel.d
	sudo tar -C $(BUILD)/qemu-kernel.d -xf $<
	$(CP) $(BUILD)/qemu-kernel.d/boot/vmlinuz-* $@
	sudo rm -rf $(BUILD)/qemu-kernel.d

%.tar.cpio: %.tar
	sudo rm -rf $(BUILD)/$(notdir $*).tar.d
	sudo mkdir -p $(BUILD)/$(notdir $*).tar.d
	sudo tar -C $(BUILD)/$(notdir $*).tar.d -xf $<
	sudo chown -R root.root $(BUILD)/$(notdir $*).tar.d
	(cd $(BUILD)/$(notdir $*).tar.d; find . | cpio -H newc -o) > $@
	sudo rm -rf $(BUILD)/$(notdir $*).tar.d

$(BUILD)/debian/debootstrap/stage2.cpio: $(BUILD)/debian/debootstrap/stage15.tar.cpio $(BUILD)/qemu-kernel
	dd if=/dev/zero of=tmp bs=1G count=2
	qemu-system-aarch64 -drive if=virtio,index=0,media=disk,driver=raw,file=tmp -machine virt -cpu max -kernel $(BUILD)/qemu-kernel -m 7g -serial stdio -initrd $< -nic user,model=virtio -monitor none -smp 8 -nographic
	uudecode -o $@ < tmp
	rm -f tmp

$(BUILD)/debian/debootstrap/final.cpio: $(BUILD)/debian/debootstrap/stage2.cpio final/init
	sudo rm -rf $(BUILD)/debian/debootstrap/final.d
	sudo mkdir -p $(BUILD)/debian/debootstrap/final.d
	(cd $(BUILD)/debian/debootstrap/final.d; sudo cpio -id) < $<
	sudo cp final/init $(BUILD)/debian/debootstrap/final.d/init
	(cd $(BUILD)/debian/debootstrap/final.d; sudo find . | sudo cpio -H newc -o) > $@
	sudo rm -rf $(BUILD)/debian/debootstrap/final.d

$(BUILD)/debian/debootstrap/for-di.cpio: $(BUILD)/debian/debootstrap/final.cpio for-di/script
	sudo rm -rf $(BUILD)/debian/debootstrap/for-di.d
	sudo $(MKDIR) $(BUILD)/debian/debootstrap/for-di.d
	cp for-di/script $(BUILD)/debian/debootstrap/for-di.d/vda
	dd if=/dev/zero of=$(BUILD)/debian/debootstrap/for-di.d/vdb bs=1G count=4
	qemu-system-aarch64 -drive if=virtio,index=0,media=disk,driver=raw,file=$(BUILD)/debian/debootstrap/for-di.d/vda if=virtio,index=1,media=disk,driver=raw,file=$(BUILD)/debian/debootstrap/for-di.d/vdb -machine virt -cpu max -kernel $(BUILD)/qemu-kernel -m 7g -serial stdio -initrd $< -nic user,model=virtio -monitor none -smp 8 -nographic
	uudecode -o $@ < $(BUILD)/debian/debootstrap/for-di.d/vdb
	sudo rm -rf $(BUILD)/debian/debootstrap/for-di.d

%.xz: %
	xz -9 -e -c --verbose $< > $@
