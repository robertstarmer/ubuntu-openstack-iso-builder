#/bin/bash
# From: https://help.ubuntu.com/community/InstallCDCustomization/Scripts
# http://creativecommons.org/licenses/by-sa/3.0/
#
# Script by Leigh Purdie
# Script reworked by:
#  - Robert Starmer @ Cisco Systems Inc.
#  - Stanley Abrahms @ One-Cloud Inc.
#
# Install a Ubuntu system
#    capture the entire system as installed, or as needed for an
#    OpenStack install using the default package_list.txt file
#

set -x
# The Base Directory, assumes you git-cloned the script as root
BASEDIR="/root/GUI-Installer"

# This directory will contain additional files and directories
# that need to be copied over to the root directory of the
# new CD.
EXTRASDIR="$BASEDIR/build"
# An Ubuntu preseed file, used to configure your new system.
# This can (when properly configured) provide a completely automated
# install process
SEEDFILE="ubuntu-server.seed"

# Ubuntu ISO image
RELEASE="precise"
CDISO="ubuntu-12.04.3-server-amd64.iso"
CDIMAGE="$BASEDIR/$CDISO"

# Where the ubuntu iso image will be mounted
CDSOURCEDIR="$BASEDIR/cdsource"

# Directory for building packages
SOURCEDIR="$BASEDIR/source"

# GPG
GPGKEYNAME="OpenStack GUI Installation Key"
GPGKEYCOMMENT="Package Signing"
GPGKEYEMAIL="gui@onecloud.com"
GPGKEYPHRASE="cloud"
MYGPGKEY="$GPGKEYNAME ($GPGKEYCOMMENT) <$GPGKEYEMAIL>"

# Package list (dpkg -l) from an installed system.
PACKAGELIST="$SOURCEDIR/PackageList"

# Output CD name
CDDIR=$BASEDIR
CDNAME="aio.iso"

# 640x480 PNG with colours as specified in
# https://wiki.ubuntu.com/USplashCustomizationHowto
#USPLASH="$SOURCEDIR/cisco-openstack.png"

# ------------ End of modifications.


################## Initial requirements
id | grep -c uid=0 >/dev/null
if [ $? -gt 0 ]; then
        echo "You need to be root in order to run this script.."
        echo " - sudo /bin/sh prior to executing."
        exit
fi

# Install app
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/havana main" >> /etc/apt/sources.list
# sed -e 's/us.*com/mirror.ctocllab.cisco.com/' -i /etc/apt/sources.list
apt-get update 
apt-get install reprepro genisoimage wget gnupg-agent stress vim -y

which gpg > /dev/null
if [ $? -eq 1 ]; then
        echo "Please install gpg to generate signing keys"
        exit
fi

# Get ISO
if [ ! -f $CDIMAGE ]; then
  wget -O $CDIMAGE http://releases.ubuntu.com/$RELEASE/$CDISO
fi

if [ ! -f $CDIMAGE ]; then
        echo "Cannot find your ubuntu image. Change CDIMAGE path."
        exit
fi


# Create a few directories.
if [ ! -d $BASEDIR ]; then mkdir -p $BASEDIR; fi
if [ ! -d $BASEDIR/FinalCD ]; then mkdir -p $BASEDIR/FinalCD; fi
if [ ! -z $EXTRASDIR ]; then
        if [ ! -d $EXTRASDIR ]; then mkdir -p $EXTRASDIR; fi
        if [ ! -d $EXTRASDIR/preseed ]; then mkdir -p $EXTRASDIR/preseed; fi
	cp -R $BASEDIR/proto-build/* $EXTRASDIR/
fi
if [ ! -d $CDSOURCEDIR ]; then mkdir -p $CDSOURCEDIR; fi
if [ ! -d $SOURCEDIR ]; then mkdir -p $SOURCEDIR; fi
if [ ! -d $SOURCEDIR/keyring ]; then mkdir -p $SOURCEDIR/keyring; fi
if [ ! -d $SOURCEDIR/ubuntu-meta ]; then mkdir -p $SOURCEDIR/ubuntu-meta; fi

# let us grab some Cisco code
git clone https://github.com/CiscoSystems/puppet_openstack_builder -b coi-development $BASEDIR/proto-build/puppet_openstack_builder
cp $BASEDIR/cisco.install.sh $BASEDIR/proto-build/puppet_openstack_builder/install-scripts/
# Start and enable gpg-agent
if test -f $HOME/.gpg-agent-info && kill -0 `cut -d: -f 2 $HOME/.gpg-agent-info` 2> /dev/null; then
	GPG_AGENT_INFO=`cat $HOME/.gpg-agent-info`
	export GPG_AGENT_INFO
else
	eval `gpg-agent --daemon --write-env-file ~/.gpg-agent-info`
fi

if [ -f "${HOME}/.gpg-agent-info" ]; then
	. "${HOME}/.gpg-agent-info"
	export GPG_AGENT_INFO
	export SSH_AUTH_SOCK
	export SSH_AGENT_PID
fi

export GPG_TTY=`tty`

if [ -f "${HOME}/.gpg-agent-info" ]; then
           . "${HOME}/.gpg-agent-info"
           export GPG_AGENT_INFO
           export SSH_AUTH_SOCK
fi


gpg --list-keys | grep "$GPGKEYNAME" >/dev/null
if [ $? -ne 0 ]; then
        echo "No GPG Key found in your keyring."
        echo "Generating a new gpg key ($GPGKEYNAME $GPGKEYCOMMENT) with a passphrase of $GPGKEYPHRASE .."
        echo ""
        echo "Key-Type: DSA
Key-Length: 1024
Subkey-Type: ELG-E
Subkey-Length: 2048
Name-Real: $GPGKEYNAME
Name-Comment: $GPGKEYCOMMENT
Name-Email: $GPGKEYEMAIL
Expire-Date: 0
Passphrase: $GPGKEYPHRASE" > $BASEDIR/key.inc

gpg --gen-key --batch --gen-key $BASEDIR/key.inc
        # Note: If you wish to remove the passphrase from the key:
        # (Don't do this if you want to use this key for ANYTHING other
        # than a temporary ubuntu CD installation signing key)
        # gpg --edit-key
        # passwd
        # (enter old phrase)
        # (blank)
        # (blank)
        # y
        # quit
        # y
fi

if [ ! -f $CDSOURCEDIR/md5sum.txt ]; then
        echo -n "Mounting Ubuntu iso.. "
        mount | grep $CDSOURCEDIR
        if [ $? -eq 0 ]; then
                umount $CDSOURCEDIR
        fi

        mount -o loop $CDIMAGE $CDSOURCEDIR/
        if [ ! -f $CDSOURCEDIR/md5sum.txt ]; then
                echo "Mount did not succeed. Exiting."
                exit
        fi
        echo "OK"
fi

#if [ ! -f $SOURCEDIR/apt.conf ]; then
#       echo -n "No APT.CONF file found... generating one."
#       # Try and generate one?
#       cat $CDSOURCEDIR/dists/precise/Release | egrep -v "^ " | egrep -v "^(Date|MD5Sum|SHA1)" | sed 's/: */ "/' | sed 's/^/APT::FTPArchive::Release::/' | sed 's/$/";/' > $SOURCEDIR/apt.conf
#       echo "Ok. APT"
#fi
#

################## Copy over the source data

echo -n "Resyncing old data...  "

cd $BASEDIR/FinalCD
rsync -atz --delete $CDSOURCEDIR/ $BASEDIR/FinalCD/
echo "OK"

mkdir -p $BASEDIR/FinalCD/mirror/conf
cat > $BASEDIR/FinalCD/mirror/conf/distributions<<EOF
Origin: Ubuntu
Label: Ubuntu
Codename: precise
Suite: stable
Version: 12.04
Architectures: amd64
Components: extras
DebOverride: override
Description: OpenStack components mirror
Pull: precise
SignWith: yes
EOF
#DebOverride: override.precise.extra.main

rm -rf $BASEDIR/FinalCD/{dists,pool}
mkdir -p $BASEDIR/FinalCD/conf
cat > $BASEDIR/FinalCD/conf/distributions<<EOF
Origin: Ubuntu
Label: Ubuntu
Codename: precise
Suite: stable
Version: 12.04
Architectures: amd64 i386
Components: main
DebOverride: override
UDebComponents: main
Description: GUI-Installer cd mirror
SignWith: yes
Pull: precise
EOF

echo "Grab overrides"
# add override parameters to distributions files (above)
if [ ! -f $BASEDIR/indices/override.precise.extra.main ]; then
	mkdir -p $BASEDIR/indices
        for i in override.precise.extra.main override.precise.main override.precise.main.debian-installer; do
                cd $BASEDIR/indices
                wget http://archive.ubuntu.com/ubuntu/indices/$i
        done
	# Create a 'fixed' version of the extras.main override package.
	# Idea/Perl by Ferry Hendrikx, 2006
	cat $BASEDIR/indices/override.precise.extra.main | egrep -v ' Task ' > $BASEDIR/indices/override
	gunzip -c $CDSOURCEDIR/dists/precise/main/binary-amd64/Packages.gz | perl -e 'while (<>) { chomp; if(/^Package\:\s*(.+)$/) { $pkg=$1; } elsif(/^Task\:\s(.+)$/) { print "$pkg\tTask\t$1\n"; } }' >> $BASEDIR/indices/override

	#cat $BASEDIR/indices/*main > $BASEDIR/indices/override

	cp $BASEDIR/indices/* $BASEDIR/FinalCD/conf/
	cp $BASEDIR/indices/* $BASEDIR/FinalCD/mirror/conf/
else
	cp $BASEDIR/indices/* $BASEDIR/FinalCD/conf/	
	cp $BASEDIR/indices/* $BASEDIR/FinalCD/mirror/conf/	
fi

#rebuild the archive
reprepro -V -b $BASEDIR/FinalCD -C main includedeb precise `find $BASEDIR/cdsource -name '*\.deb'`
reprepro -V -b $BASEDIR/FinalCD -C main includeudeb precise `find $BASEDIR/cdsource -name '*udeb'`

################## Remove packages that we no longer require

echo "Create symlinks to stable/unstable"
cd $BASEDIR/FinalCD/dists
ln -s precise stable
ln -s precise unstable

### PackageList is a dpkg -l from our 'build' server.
##if [ ! -f $PACKAGELIST ]; then
##        echo "No PackageList found. Assuming that you do not require any packages to be removed"
##else
##        cat $PACKAGELIST | grep "^ii" | awk '{print $2 "_" $3}' > $SOURCEDIR/temppackages
##
##        echo "Removing files that are no longer required.."
##        cd $BASEDIR/FinalCD
##        # Only use main for the moment. Keep all 'restricted' debs
##        rm -f $SOURCEDIR/RemovePackages
##        # Note: Leave the udeb's alone.
##        for i in `find pool/main -type f -name "*.deb" -print`; do
##                FILE=`basename $i | sed 's/_[a-zA-Z0-9\.]*$//'`
##                GFILE=`echo $FILE | sed 's/\+/\\\+/g' | sed 's/\./\\\./g'`
##                # pool/main/a/alien/alien_8.53_all.deb becomes alien_8.53
##                egrep "^"$GFILE $SOURCEDIR/temppackages >/dev/null
##                if [ $? -ne 0 ]; then
##                        # NOT Found
##                        # Note: Keep a couple of anciliary files
##
##                        zcat $CDSOURCEDIR/dists/precise/main/debian-installer/binary-amd64/Packages | grep "Filename: $i" > /dev/null
##                        if [ $? -eq 0 ]; then
##                                # Keep the debian-installer files - we need them.
##                                echo "* Keeping special file $FILE"
##                        else
##                                echo "- Removing unneeded file $FILE"
##                                rm -f $BASEDIR/FinalCD/$i
##
##                        fi
##                else
##                        echo "+ Retaining $FILE"
##                fi
##        done
##fi


echo -n "Generating keyfile..   "

cd $SOURCEDIR/keyring
KEYRING=`find * -maxdepth 1 -name "ubuntu-keyring*" -type d -print`
if [ -z "$KEYRING" ]; then
        apt-get source ubuntu-keyring
        KEYRING=`find * -maxdepth 1 -name "ubuntu-keyring*" -type d -print`
        if [ -z "$KEYRING" ]; then
                echo "Cannot grab keyring source! Exiting."
                exit
        fi
fi

cd $SOURCEDIR/keyring/$KEYRING/keyrings
gpg --import < ubuntu-archive-keyring.gpg >/dev/null
gpg --list-keys | grep 4BD6EC30 >/dev/null
if [ $? -ne 0 ]; then
	gpg --keyserver pool.sks-keyservers.net --recv-key 4BD6EC30 >/dev/null
fi
gpg --list-keys | grep 17ED316D >/dev/null
if [ $? -ne 0 ]; then
	gpg --keyserver pool.sks-keyservers.net --recv-key 17ED316D >/dev/null
fi
gpg --list-keys | grep EC4926EA >/dev/null
if [ $? -ne 0 ]; then
	gpg  --keyserver keyserver.ubuntu.com --recv-key EC4926EA>/dev/null
fi

rm -f ubuntu-archive-keyring.gpg
gpg --output=ubuntu-archive-keyring.gpg --export C0B21F32 EFE21092 FBB75451 437D05B5 4BD6EC30 17ED316D "$GPGKEYNAME" >/dev/null
cd ..
dpkg-buildpackage -rfakeroot -m"$MYGPGKEY" -k"$MYGPGKEY" >/dev/null

echo "cleaning up keyring in ${PWD}"
ls -l ../*deb

reprepro -V -b $BASEDIR/FinalCD -T deb -C main remove precise ubuntu-keyring
reprepro -V -b $BASEDIR/FinalCD -T udeb -C main remove precise ubuntu-keyring-udeb
reprepro -V -b $BASEDIR/FinalCD -C main includedeb precise ../ubuntu-keyring*.deb
reprepro -V -b $BASEDIR/FinalCD -C main includeudeb precise ../ubuntu-keyring*.udeb

if [ $? -gt 0 ]; then
        echo "Cannot copy the modified ubuntu-keyring over to the pool/main folder. Exiting."
        exit
fi

echo "OK"


################## Copy over the extra packages (if any)
if [ ! -z $EXTRASDIR ]; then
        echo -n "Copying Extra files...  "
        rsync -az $EXTRASDIR/ $BASEDIR/FinalCD/
        echo "OK"

        if [ ! -f "$EXTRASDIR/preseed/$SEEDFILE" ]; then
                echo "No seed file found. Creating one in $EXTRASDIR/preseed/$SEEDFILE."
                echo "- You will probably want to modify this file."
                echo "base-config  base-config/package-selection      string ~tubuntu-minimal|~tubuntu-desktop" > $EXTRASDIR/preseed/$SEEDFILE
        fi

        if [ -f $PACKAGELIST ]; then
                echo "Replacing ubuntu-desktop with a pruned package list.. "
                cd $SOURCEDIR/ubuntu-meta
                rm -rf ubuntu-*
                apt-get source ubuntu-meta
                META=`find * -maxdepth 1 -name "ubuntu-meta*" -type d -print`
                if [ -z "$META" ]; then
                      echo "Cannot grab source to ubuntu-meta. Exiting."
                      exit
                fi

                cd $META
                for i in `ls desktop*`; do
                        grep "^ii" $PACKAGELIST | awk '{print $2}' > $i.tmp
                        mv $i.tmp $i
                done

                dpkg-buildpackage -rfakeroot -m"$MYGPGKEY" -k"$MYGPGKEY" >/dev/null
                cd ..
                #rm -f $BASEDIR/FinalCD/pool/main/u/ubuntu-meta/ubuntu-desktop*.deb
                
		reprepro -V -b $BASEDIR/FinalCD -C main remove precise ubuntu-desktop
		reprepro -V -b $BASEDIR/FinalCD -T udeb -C main remove precise ubuntu-desktop-udeb
		reprepro -V -b $BASEDIR/FinalCD -C main includedeb precise ./ubuntu-desktop*.deb
		reprepro -V -b $BASEDIR/FinalCD -C main includeudeb precise ./ubuntu-desktop*.udeb

                cp $EXTRASDIR/preseed/$SEEDFILE $BASEDIR/FinalCD/preseed/$SEEDFILE

        fi

#        if [ ! -f "$EXTRASDIR/isolinux/isolinux.cfg" ]; then
#                cat $CDSOURCEDIR/isolinux/isolinux.cfg | sed "s/^APPEND.*/APPEND   preseed\/file=\/cdrom\/preseed\/$SEEDFILE vga=normal initrd=\/install\/initrd.gz ramdisk_size=16384 root=\/dev\/rd\/0 DEBCONF_PRIORITY=critical debconf\/priority=critical rw --/" > $BASEDIR/FinalCD/isolinux/isolinux.cfg
#        fi
#	if [ -f "$CDSOURCEDIR/isolinux/txt.cfg" ]; then
#		cat $CDSOURCEDIR/isolinux/txt.cfg | sed "s/ubuntu.seed/$SEEDFILE/" > $BASEDIR/FinalCD/isolinux/txt.cfg
#		cat $CDSOURCEDIR/isolinux/txt.cfg | sed "s/\(seed.*\)--.*$/\1 debian-installer\/locale=en_US.UTF-8 console-setup\/layoutcode=us debconf\/language=en country=US priority=critical --/" > $BASEDIR/FinalCD/isolinux/txt.cfg
#	fi
	#cat > $BASEDIR/FinalCD/isolinux/txt.cfg <<EOF
	cat > $BASEDIR/FinalCD/isolinux/isolinux.cfg <<EOF
default install
timeout 0
prompt 0
label install
  menu label ^Install Ubuntu Server
  kernel /install/vmlinuz
  append  file=/cdrom/preseed/ubuntu-server.seed  text vga=788 initrd=/install/initrd.gz quiet priority=critical language=en locale=en_US.UTF-8 layoutcode=us country=US --
EOF

        echo "OK"
fi

if [ ! -z "$USPLASH" ]; then
        echo "Modifying Usplash (NOTE: libgd2-dev required)"

        cd $SOURCEDIR
        if [ ! -d usplash ]; then
                mkdir usplash
        fi
        cd usplash
        SPLASH=`find * -maxdepth 1 -type d -name "usplash*" -type d -print`
        if [ -z "$SPLASH" ]; then
                apt-get source usplash
                SPLASH=`find * -maxdepth 1 -type d -name "usplash*" -type d -print`
        fi
        if [ -z "$SPLASH" ]; then
                echo "Cannot download USPLASH source. Exiting."
                exit
        fi

        cp $USPLASH $SOURCEDIR/usplash/$SPLASH/usplash-artwork.png
        cd $SOURCEDIR/usplash/$SPLASH
        dpkg-buildpackage -rfakeroot -m"$MYGPGKEY" -k"$MYGPGKEY" >/dev/null
        cd ..
## REPREPRO
# need to make reprepro command
        rm -f $BASEDIR/FinalCD/pool/main/u/usplash/usplash*deb
	reprepro -V -b $BASEDIR/FinalCD -C main includedeb precise ./usplash*.deb
        ##-mv usplash*.deb $BASEDIR/FinalCD/pool/main/u/usplash/
fi

echo "Creating apt package list.."


if [ ! -f '$BASEDIR/apt' ] ; then
mkdir -p $BASEDIR/apt
cd $BASEDIR/apt
# uncomment the following if the default package_list is out of date
#dpkg -l | grep ii | awk -F' ' '{print $2}' > $BASEDIR/package_list.txt
for name in `cat $BASEDIR/package_list.txt` ; do apt-get download $name ; done
fi

reprepro -V -b $BASEDIR/FinalCD/mirror includedeb precise ./*.deb

cd $BASEDIR/FinalCD
echo -n "Updating md5 checksums.. "
chmod 666 md5sum.txt
rm -f md5sum.txt
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
echo "OK"


cd $BASEDIR

echo "Creating and ISO image..."
mkisofs -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -hide-rr-moved -o $CDDIR/$CDNAME -R $BASEDIR/FinalCD/

echo "CD Available in $BASEDIR/$CDNAME"
echo "You can now remove all files in:"
echo " - $BASEDIR/FinalCD"

# Unmount the old CD
umount $CDSOURCEDIR
