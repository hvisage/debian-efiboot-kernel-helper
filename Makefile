include /usr/share/dpkg/pkg-info.mk

#export KERNEL_VER=4.19
#export KERNEL_ABI=4.19.0


#KERNEL_DEB=kernel-${KERNEL_VER}_${DEB_VERSION_UPSTREAM_REVISION}_all.deb
#HEADERS_DEB=headers-${KERNEL_VER}_${DEB_VERSION_UPSTREAM_REVISION}_all.deb
HELPER_DEB=hev-kernel-helper_${DEB_VERSION_UPSTREAM_REVISION}_all.deb

BUILD_DIR=build

DEBS=${HELPER_DEB}

SUBDIRS = efiboot bin

.PHONY: all
all: ${SUBDIRS}
	set -e && for i in ${SUBDIRS}; do ${MAKE} -C $$i; done

.PHONY: deb
deb: ${HELPER_DEB}

#${HEADERS_DEB}: ${KERNEL_DEB}
${HELPER_DEB}: debian
	rm -rf ${BUILD_DIR}
	mkdir -p ${BUILD_DIR}/debian
	rsync -a * ${BUILD_DIR}/
	cd ${BUILD_DIR}; debian/rules debian/control
	echo "HeViS.Co mods" > ${BUILD_DIR}/debian/SOURCE
	cd ${BUILD_DIR}; dpkg-buildpackage -b -uc -us
	lintian ${HELPER_DEB}
	cp *deb /files/debs/
	cp zfs-root/zfs-root.sh /files/scripts/

.PHONY: install
install: ${SUBDIRS}
	set -e && for i in ${SUBDIRS}; do ${MAKE} -C $$i $@; done

.PHONY: clean distclean
distclean: clean
clean:
	rm -rf *~ ${BUILD_DIR} *.deb *.dsc *.changes *.buildinfo
