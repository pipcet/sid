MKDIR ?= mkdir -p
CP ?= cp
CAT ?= cat
TAR ?= tar
PWD = $(shell pwd)
SUDO ?= $(and $(filter pip,$(shell whoami)),sudo)
NATIVE_TRIPLE ?= amd64-linux-gnu
BUILD ?= $(PWD)/build

.SECONDEXPANSION:

define COPY
	$(MKDIR) -p $(dir $@)
	$(CP) -a $< $@
endef

all: $(BUILD)/qemu-kernel $(BUILD)/debian/debootstrap/stage2.cpio

build/%:
	$(MAKE) $(PWD)/build/$*

%/:
	$(MKDIR) $@

.PHONY: %}

$(BUILD)/debian/debootstrap/stage1.tar: | $(BUILD)/debian/debootstrap/
	sudo debootstrap --foreign --arch=arm64 --include=build-essential,git,linux-image-cloud-arm64,bash,kmod,dash,wget,busybox,busybox-static,net-tools,libpam-systemd,file,xsltproc,mtools,openssl,mokutil,libx11-data,libx11-6,sharutils,dpkg-dev sid $(BUILD)/debian/debootstrap/stage1 http://deb.debian.org/debian
	(cd $(BUILD)/debian/debootstrap/stage1; sudo tar c .) > $@

$(BUILD)/debian/debootstrap/stage15.tar: $(BUILD)/debian/debootstrap/stage1.tar stage2/init
	$(MKDIR) $(BUILD)/debian/debootstrap/stage15
	(cd $(BUILD)/debian/debootstrap/stage15; sudo tar x) < $<
	(cd $(BUILD)/debian/debootstrap/stage15/var/cache/apt/archives/; for a in *.deb; do sudo dpkg-deb -R $$a $$a.d; sudo dpkg-deb -b -Znone $$a.d; sudo mv $$a.d.deb $$a; sudo rm -rf $$a.d; done)
	for a in $(BUILD)/debian/debootstrap/stage15/var/cache/apt/archives/*.deb; do sudo dpkg -x $$a $(BUILD)/debian/debootstrap/stage15; done
	sudo rm -f $(BUILD)/debian/debootstrap/stage15/init
	sudo cp -f stage2/init $(BUILD)/debian/debootstrap/stage15
	sudo chmod u+x $(BUILD)/debian/debootstrap/stage15/init
	(cd $(BUILD)/debian/debootstrap/stage15; sudo tar c .) > $@

$(BUILD)/qemu-kernel: $(BUILD)/debian/debootstrap/stage15.tar
	mkdir -p $(BUILD)/qemu-kernel.d
	tar -C $(BUILD)/qemu-kernel.d -xvf $<
	$(CP) $(BUILD)/qemu-kernel.d/boot/vmlinuz-* $@

%.tar.cpio: %.tar
	mkdir $(BUILD)/$*.tar.d
	tar -C $(BUILD)/$*.tar.d -xf $<
	sudo chown -R root.root $(BUILD)/$*.tar.d
	(cd $(BUILD)/$*.tar.d; find . | cpio -H newc -o) > $@

$(BUILD)/debian/debootstrap/stage2.cpio: $(BUILD)/debian/debootstrap/stage15.tar.cpio $(BUILD)/qemu-kernel
	dd if=/dev/zero of=tmp bs=1G count=1
	qemu-system-aarch64 -drive index=0,media=disk,driver=raw,file=tmp -machine virt -cpu max -kernel $(BUILD)/qemu-kernel -m 7g -serial stdio -initrd $< -nic user,model=virtio -monitor none -smp 8 -nographic
	uudecode -o $@ < tmp
	rm -f tmp
