#!/bin/bash
#################################################################################################
## 
##  svr2ips_vbox.sh is a bash script to convert VirtualBox's SunOS package stream into
## IPS packages.
##
## Copyright (C) 2013-2014 Prominic - Thomas Gouverneur <thomas@espix.net>
## This program is free software: you can redistribute it and/or modify it under the 
## terms of the GNU General Public License as published by the Free Software Foundation, 
## either version 3 of the License, or (at your option) any later version.
## 
## This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; 
## without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. 
## See the GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License along with this program. 
## If not, see http://www.gnu.org/licenses/.
##
## Usage: svr2ips_vbox.sh <SVR4> <IPS> [cache]
##
## where:
##	 * SVR4 is a package stream file
##	   of virtualbox release with the
##	   original file name.
##	 * IPS is an IPS repository location
## 	   where the solaris publisher is
##	   present. Converted package
##	   will be sent to this repository.
##	 * cache dir is optional but recommended
##	   when you have multiple package to treat.
##
#################################################################################################
DEBUG=0
IREPO=http://pkg.oracle.com/solaris/release

function debug() {
 msg=$1
 if [ ! -z "${DEBUG}" -a ${DEBUG} -eq 1 ]; then
   echo "[D] ${msg}";
 fi
}

if [ $# -lt 2 -o $# -gt 3 ]; then
  echo "$0 <SVR4> <IPS repo> [cache]";
  exit 1;
fi

if [ ! -f "${1}" ]; then
  echo "[!] SVR4 Package stream not found";
  exit 2;
fi

cleanup() {
  tmpdir=$1
  echo -n "\t* cleaning the mess: "
  popd > /dev/null 2>&1
  rm -rf ${tmpdir};
  echo "[DONE]";
}

pkgstream=$1;

if [ ! -d "${2}" ]; then
  echo "[!] IPS Repo directory not found";
  exit 3;
fi

ipsrepo=$2;

pkgrepo -s ${ipsrepo} info > /dev/null 2>&1
rc=$?

if [ $rc -ne 0 ]; then
  echo "[!] Invalid IPS repo $ipsrepo";
  exit 4;
fi

cachedir=
if [ $# -eq 3 ]; then
  cachedir=$3;
  if [ ! -d "${cachedir}" ]; then
    echo "[!] provided cachedir doesn't exist";
    exit 7;
  fi
  echo "[-] using specified cachedir: ${cachedir}";
fi


filename=$(basename ${pkgstream} | sed 's/.pkg$//g');
major=$(echo $filename|cut -f 2 -d'-'|sed 's/_.*//g');
minor=$(echo $filename|awk -F'-' '{print $NF}'|sed 's/^r//g');
if [ "${minor}" = "" ]; then
  minor=0;
fi
vboxfmri="pkg://solaris/system/virtualbox@0.5.11,5.11-${major}.${minor}";
tmpdir=$(mktemp -d);
echo "[-] Will try to build IPS package ${vboxfmri}:";

echo -n "\t* pkgtrans: "
pkgtrans ${pkgstream} ${tmpdir} SUNWvbox > /dev/null 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "[FAILED]";
  cleanup ${tmpdir}
  exit 5;
fi
echo "[DONE]";

pushd ${PWD} > /dev/null 2>&1
cd ${tmpdir};
pArch=$(grep ARCH= ./SUNWvbox/pkginfo | cut -f 2 -d'=')
echo -n "\t* generating manifest: ";
pkgsend generate ./SUNWvbox 2>/dev/null | pkgfmt > ${filename}.manifest
rc=$?
if [ $rc -ne 0 ]; then
  echo "[FAILED]";
  cleanup ${tmpdir}
  exit 5;
fi
echo "[DONE]";
echo -n "\t* copy hack-script: ";
echo "${major}.${minor}" >> VERSION
cat > run-once.sh << "EOF"
#!/usr/bin/sh
. /lib/svc/share/smf_include.sh
lver=$(/usr/bin/svcprop -p config/version $SMF_FMRI)
if [ -f /opt/VirtualBox/VERSION ]; then
  cver=$(cat /opt/VirtualBox/VERSION)
else
  cver=""
fi

infoprint()
{
    echo 1>&2 "$1"
}

errorprint()
{
    echo 1>&2 "## $1"
}

if [ "$lver" != "$cver" ]; then
  svccfg -s $SMF_FMRI setprop config/assembled = false
  svccfg -s $SMF_FMRI setprop config/version = astring: $cver
  svccfg -s $SMF_FMRI refresh
  echo "--UPDATE virtualbox/run-once"
  BIN_PKG=`which pkg 2> /dev/null`

  # Check if the Zone Access service is holding open vboxdrv, if so stop & remove it
  servicefound=`svcs -H "svc:/application/virtualbox/zoneaccess" 2> /dev/null | grep '^online'`
  if test ! -z "$servicefound"; then
      infoprint "VirtualBox's zone access service appears to still be running."
      infoprint "Halting & removing zone access service..."
      /usr/sbin/svcadm disable -s svc:/application/virtualbox/zoneaccess
      # Don't delete the service, handled by manifest class action
      # /usr/sbin/svccfg delete svc:/application/virtualbox/zoneaccess
  fi
  
  # Check if the Web service is running, if so stop & remove it
  servicefound=`svcs -H "svc:/application/virtualbox/webservice" 2> /dev/null | grep '^online'`
  if test ! -z "$servicefound"; then
      infoprint "VirtualBox web service appears to still be running."
      infoprint "Halting & removing webservice..."
      /usr/sbin/svcadm disable -s svc:/application/virtualbox/webservice
      # Don't delete the service, handled by manifest class action
      # /usr/sbin/svccfg delete svc:/application/virtualbox/webservice
  fi
  
  # Check if the autostart service is running, if so stop & remove it
  servicefound=`svcs -H "svc:/application/virtualbox/autostart" 2> /dev/null | grep '^online'`
  if test ! -z "$servicefound"; then
      infoprint "VirtualBox autostart service appears to still be running."
      infoprint "Halting & removing autostart service..."
      /usr/sbin/svcadm disable -s svc:/application/virtualbox/autostart
  fi
  
  # Check if VBoxSVC is currently running
  VBOXSVC_PID=`ps -eo pid,fname | grep VBoxSVC | grep -v grep | awk '{ print $1 }'`
  if test ! -z "$VBOXSVC_PID" && test "$VBOXSVC_PID" -ge 0; then
      errorprint "VirtualBox's VBoxSVC (pid $VBOXSVC_PID) still appears to be running."
      abort_error
  fi
  # Check if VBoxNetDHCP is currently running
  VBOXNETDHCP_PID=`ps -eo pid,fname | grep VBoxNetDHCP | grep -v grep | awk '{ print $1 }'`
  if test ! -z "$VBOXNETDHCP_PID" && test "$VBOXNETDHCP_PID" -ge 0; then
      errorprint "VirtualBox's VBoxNetDHCP (pid $VBOXNETDHCP_PID) still appears to be running."
      abort_error
  fi
  
  # Check if VBoxNetNAT is currently running
  VBOXNETNAT_PID=`ps -eo pid,fname | grep VBoxNetNAT | grep -v grep | awk '{ print $1 }'`
  if test ! -z "$VBOXNETNAT_PID" && test "$VBOXNETNAT_PID" -ge 0; then
      errorprint "VirtualBox's VBoxNetNAT (pid $VBOXNETNAT_PID) still appears to be running."
      abort_error
  fi
  # Check if vboxnet is still plumbed, if so try unplumb it
  BIN_IFCONFIG=`which ifconfig 2> /dev/null`
  if test -x "$BIN_IFCONFIG"; then
      vboxnetup=`$BIN_IFCONFIG vboxnet0 >/dev/null 2>&1`
      if test "$?" -eq 0; then
          infoprint "VirtualBox NetAdapter is still plumbed"
          infoprint "Trying to remove old NetAdapter..."
          $BIN_IFCONFIG vboxnet0 unplumb
          if test "$?" -ne 0; then
              errorprint "VirtualBox NetAdapter 'vboxnet0' couldn't be unplumbed (probably in use)."
              abort_error
          fi
      fi
      vboxnetup=`$BIN_IFCONFIG vboxnet0 inet6 >/dev/null 2>&1`
      if test "$?" -eq 0; then
          infoprint "VirtualBox NetAdapter (Ipv6) is still plumbed"
          infoprint "Trying to remove old NetAdapter..."
          $BIN_IFCONFIG vboxnet0 inet6 unplumb
          if test "$?" -ne 0; then
              errorprint "VirtualBox NetAdapter 'vboxnet0' IPv6 couldn't be unplumbed (probably in use)."
              abort_error
          fi
      fi
  fi
 
fi

assembled=$(/usr/bin/svcprop -p config/assembled $SMF_FMRI)
if [ "$assembled" == "true" ] ; then
    exit $SMF_EXIT_OK
fi

# Run the pkginstall.sh --ips
echo "--PKGINSTALL virtualbox/run-once"
/opt/VirtualBox/pkginstall.sh --ips
svccfg -s $SMF_FMRI setprop config/assembled = true
svccfg -s $SMF_FMRI refresh
echo "--DONE virtualbox/run-once"
EOF

cat > virtualbox-run-once.xml << "EOF"
<?xml version="1.0"?>
<!DOCTYPE service_bundle SYSTEM "/usr/share/lib/xml/dtd/service_bundle.dtd.1">
<service_bundle type='manifest' name='VirtualBox:run-once'>
<service
    name='application/virtualbox/run-once'
    type='service'
    version='1'>
    <single_instance />
    <dependency
        name='fs-local'
        grouping='require_all'
        restart_on='none'
        type='service'>
            <service_fmri value='svc:/system/filesystem/local:default' />
    </dependency>
    <dependent
        name='virtualbox-assembly-complete'
        grouping='optional_all'
        restart_on='none'>
        <service_fmri value='svc:/milestone/self-assembly-complete' />
    </dependent>
    <instance enabled='true' name='default'>
        <exec_method
            type='method'
            name='start'
            exec='/opt/VirtualBox/run-once.sh'
            timeout_seconds='0'/>
        <exec_method
            type='method'
            name='stop'
            exec=':true'
            timeout_seconds='0'/>
        <property_group name='startd' type='framework'>
            <propval name='duration' type='astring' value='transient' />
        </property_group>
        <property_group name='config' type='application'>
            <propval name='assembled' type='boolean' value='false' />
            <propval name='version' type='boolean' value='' />
        </property_group>
    </instance>
</service>
</service_bundle>
EOF

# find the root path
root=
if [ -d "./SUNWvbox/root" ]; then
  root=root;
elif [ -d "./SUNWvbox/reloc" ]; then
  root=reloc;
else
  echo "[FAILED]";
  cleanup ${tmpdir}
  exit 5;
fi

cp ./run-once.sh ./SUNWvbox/${root}/opt/VirtualBox/
cp ./VERSION ./SUNWvbox/${root}/opt/VirtualBox/
cp ./virtualbox-run-once.xml ./SUNWvbox/${root}/var/svc/manifest/application/virtualbox/
echo "file ${root}/opt/VirtualBox/run-once.sh \\" >> ${filename}.manifest
echo "\tpath=/opt/VirtualBox/run-once.sh owner=root group=sys mode=0755" >> ${filename}.manifest
echo "file ${root}/var/svc/manifest/application/virtualbox/virtualbox-run-once.xml \\" >> ${filename}.manifest
echo "\tpath=/var/svc/manifest/application/virtualbox/virtualbox-run-once.xml owner=root group=sys \\" >> ${filename}.manifest
echo "\tmode=0644 restart_fmri=svc:/system/manifest-import:default" >> ${filename}.manifest
echo "file ${root}/opt/VirtualBox/VERSION \\" >> ${filename}.manifest
echo "\tpath=/opt/VirtualBox/VERSION owner=root group=sys mode=0644" >> ${filename}.manifest
echo "[DONE]";

echo -n "\t* generating metadata: ";
echo "set name=pkg.fmri value=\"${vboxfmri}\"" > ${filename}.meta
echo "set name=info.classification \\" >> ${filename}.meta
echo "\tvalue=\"org.opensolaris.category.2008:Applications/System Utilities\"" >>  ${filename}.meta
echo "set name=org.opensolaris.consolidation value=SUNWvbox" >>  ${filename}.meta
echo "set name=variant.opensolaris.zone value=global" >> ${filename}.meta
echo "set name=variant.arch value=${pArch}" >> ${filename}.meta
cp ${filename}.meta ${filename}.p5m
cat ${filename}.manifest | awk 'BEGIN{f=1} /^legacy/ { f=0 } { if (f == 1) { print } else { if ($NF != "\\") { f=1 } } }' >> ${filename}.p5m
echo "[DONE]";

echo -n "\t* generating dependancies: ";
pkgdepend generate -md SUNWvbox ${filename}.p5m 2>/dev/null | pkgfmt > ${filename}.p5m.2
rc=$?
if [ $rc -ne 0 ]; then
  echo "[FAILED]";
  cleanup ${tmpdir}
  exit 5;
fi
echo "[DONE]";

echo -n "\t* resolving dependancies: ";
if [ ! -z "${DEBUG}" -a ${DEBUG} -eq 1 ]; then
  echo;
  pkgdepend resolve -m ${filename}.p5m.2
  rc=$?
else
  pkgdepend resolve -m ${filename}.p5m.2 > /dev/null 2>&1
  rc=$?
fi
if [ $rc -gt 1 -o ! -f ./${filename}.p5m.2.res ]; then
  echo "[FAILED]";
  cleanup ${tmpdir}
  exit 5;
fi
echo "[DONE]";

echo -n "\t* cleaning dependancies: ";
cp ${filename}.p5m.2.res ${filename}.p5m.2.res.bak
cat ${filename}.p5m.2.res.bak | awk '/^depend/ { printf $1 " "; for (i=2; i<=NF; i++) { if ($i ~ /@/) { split($i, x, "@"); printf x[1] " "; } else { printf $i " "; } } printf "\n"; continue; } {print}' > ${filename}.p5m.2.res
echo "[DONE]";

echo -n "\t* checking package: ";
if [ -z "${cachedir}" ]; then
  mkdir -p ./cache
  cachedir=./cache
fi
pkglint -c ${cachedir} -r ${IREPO} ./${filename}.p5m.2.res > /dev/null 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "[FAILED]";
  cleanup ${tmpdir}
  exit 5;
fi
echo "[DONE]";

echo -n "\t* publishing package: ";
pkgsend publish -d SUNWvbox -s ${ipsrepo} ./${filename}.p5m.2.res > /dev/null 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "[FAILED]";
  cleanup ${tmpdir}
  exit 5;
fi
echo "[DONE]";

cleanup ${tmpdir}

#EOF
