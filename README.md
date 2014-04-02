VBox-SVR2IPS
============

Purpose
========

The goal of these scripts is to allow the conversion from SVR package provided by VirtualBox to be stored into an IPS
repository, allowing the sysadmin to easily push the packages to a set of machines.

Also, you can package the extension pack into an IPS package that will take care of installing that extension pack
on the currently used VirtualBox.

Config
======

Open the two scripts and set the 'IREPO' variable to point to your Operating System's IPS repository, so the
virtualbox's dependancies can be resolved inside this repo.

Also, if you are going to convert multiple package at once, you might as well create a temporary lint-cache
directory and pass it in parameter to each run of the script, see below for more informations on how
to use the script.

Usage
======

$ ./svr2ips_vbox.sh
./svr2ips_vbox.sh <SVR4> <IPS repo> [cache]

 * SVR4 is the .pkg file extracted from the VirtualBox's downloaded package.
 * IPS repo, is where you want the generated IPS package to be sent to.
 * cache, optionnal lint-cache directory, to speedup package resolution if you're going to run the script multiple times.


$ ./svr2ips_xtp.sh 
./svr2ips_xtp.sh <XTP> <IPS repo> [cache]

 * SVR4 is the .extpack file as downloaded from VirtualBox.
 * IPS repo, is where you want the generated IPS package to be sent to.
 * cache, optionnal lint-cache directory, to speedup package resolution if you're going to run the script multiple times.

WARNING: the version of VirtualBox is generated from the providen package's file name, so don't rename
the .pkg or .extpack file!!

Example
=======

```
$ pkgrepo -s /mgmt/ips/vbox info
PUBLISHER PACKAGES STATUS           UPDATED
solaris   2        online           2014-03-30T03:47:26.227324Z
$ ls -l VirtualBox-4.3.8-SunOS-amd64-r92456.pkg 
-rw-r--r--   1 101      staff    217334784 Feb 25 19:06 VirtualBox-4.3.8-SunOS-amd64-r92456.pkg
$ /mgmt/bin/svr2ips_vbox.sh ./VirtualBox-4.3.8-SunOS-amd64-r92456.pkg /mgmt/ips/vbox /mgmt/tmp/lint-cache
[-] using specified cachedir: /mgmt/tmp/lint-cache
[-] Will try to build IPS package pkg://solaris/system/virtualbox@0.5.11,5.11-4.3.8.92456:
         * pkgtrans: [DONE]
         * generating manifest: [DONE]
         * copy hack-script: [DONE]
         * generating metadata: [DONE]
         * generating dependancies: [DONE]
         * resolving dependancies: [DONE]
         * cleaning dependancies: [DONE]
         * checking package: [DONE]
         * publishing package: [DONE]
         * cleaning the mess: [DONE]
```

```
$ ls -ld Oracle_VM_VirtualBox_Extension_Pack-4.3.8-92456.vbox-extpack 
-rw-r-----   1 wildcat  staff    10432725 Feb 25 19:05 Oracle_VM_VirtualBox_Extension_Pack-4.3.8-92456.vbox-extpack
$ /mgmt/bin/svr2ips_xtp.sh ./Oracle_VM_VirtualBox_Extension_Pack-4.3.8-92456.vbox-extpack /mgmt/ips/vbox /mgmt/tmp/lint-cache
[-] using specified cachedir: /mgmt/tmp/lint-cache
[-] Will try to build IPS package pkg://solaris/system/virtualbox-extpack@0.5.11,5.11-4.3.8.92456:
         * building directory structure: [DONE]
         * copying extpack: [DONE]
         * copy hack-script: [DONE]
         * generating metadata: [DONE]
         * adding dependancies: [DONE]
         * resolving dependancies: [DONE]
         * checking package: [DONE]
         * publishing package: [DONE]
         * cleaning the mess: [DONE]
```



Installation
============

To install the latest version, run:

```
# pkg install virtualbox virtualbox-extpack
```

To install a specific version, use:

```
# pkg install pkg:/system/virtualbox@0.5.11-4.1.12.77245 pkg:/system/virtualbox-extpack@0.5.11-4.1.12.77245
```
Upgrade
=======

The upgrade procedure imply one single manual step, as you need to restart the virtualbox-run-once SMF service.
This service will take care of upgrading kernel modules for new version of the package.
  
```
$  modinfo|awk '$6 ~ /vbox/'
267 fffffffff7cbf000  2e510 279   1  vboxdrv (VirtualBox HostDrv 4.1.12r77245)
268 fffffffff7947540    d50 280   1  vboxnet (VirtualBox NetAdp 4.1.12r77245)
270 fffffffff81e7000   3bb0 281   1  vboxbow (VirtualBox NetBow 4.1.12r77245)
271 fffffffff7bf2000   4a18 282   1  vboxusbmon (VirtualBox USBMon 4.1.12r77245)
272 fffffffff7bf7000   75f8 283   1  vboxusb (VirtualBox USB 4.1.12r77245)
$ pkg info virtualbox|grep Branch
        Branch: 4.1.12.77245
```

Let's upgrade to 4.3.8. Note: we only specify the upgrade of virtualbox-extpack here as we're using the Extention pack and this extpack
has a dependancy over the regular virtualbox package.

```
$ pkg update --accept pkg:/system/virtualbox-extpack@0.5.11-4.3.8
            Packages to update:   2
       Create boot environment:  No
Create backup boot environment: Yes

DOWNLOAD                                PKGS         FILES    XFER (MB)   SPEED
Completed                                2/2       156/156  105.7/105.7 23.3M/s

PHASE                                          ITEMS
Removing old actions                         115/115
Installing new actions                         24/24
Updating modified actions                    148/148
Updating package state database                 Done 
Updating package cache                           2/2 
Updating image state                            Done 
Creating fast lookup database                   Done 

$ svcs -a|grep virtualbox
disabled        1:04:32 svc:/application/virtualbox/balloonctrl:default
disabled        1:04:33 svc:/application/virtualbox/webservice:default
online          1:04:48 svc:/application/virtualbox/zoneaccess:default
online          1:04:50 svc:/application/virtualbox/run-once:default
online          1:04:54 svc:/application/virtualbox/run-once-extpack:default
$ svcadm restart virtualbox/run-once:default
$  modinfo|awk '$6 ~ /vbox/'
267 fffffffff7cbf000  380d8 279   1  vboxdrv (VirtualBox HostDrv 4.3.8r92456)
268 fffffffffbdb43f0    ce0 280   1  vboxnet (VirtualBox NetAdp 4.3.8r92456)
270 fffffffff81e7000   3838 281   1  vboxbow (VirtualBox NetBow 4.3.8r92456)
271 fffffffff7bf2000   45b0 282   1  vboxusbmon (VirtualBox USBMon 4.3.8r92456)
272 fffffffff7bf7000   7528 283   1  vboxusb (VirtualBox USB 4.3.8r92456)
$ svcadm restart virtualbox/run-once-extpack:default
```



Supported Platforms
====================

This script was first developped for OpenIndiana, but the latest release has only been tested on Solaris 11.1.

Contact
=======

If you want to file a bug or have a question, you can contact me:

  * Mail: thomas@espix.net
  * Skype: espixnetwork


Thanks
======

Prominic, to have funded the creation of these scripts.
