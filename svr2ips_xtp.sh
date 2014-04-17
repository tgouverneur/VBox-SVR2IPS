#!/bin/bash
#################################################################################################
## 
##  svr2ips_xtp.sh is a bash script to pack VirtualBox's extension package into an
## IPS packages.
##
## Copyright (C) 2013 Prominic - Thomas Gouverneur <thomas@espix.net>
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
## Usage: svr2ips_xtp.sh <XTP> <IPS> [cache]
##
## where:
##	 * XTP is an extention pack file 
##	   of virtualbox release with the
##	   original file name.
##	 * IPS is an IPS repository location
## 	   where the solaris publisher is
##	   present. Converted package
##	   will be sent to this repository.
##       * cache dir is optional but recommended
##         when you have multiple package to treat.
##
#################################################################################################

IREPO=http://pkg.oracle.com/solaris/release
PUBLISHER=solaris

if [ $# -lt 2 -o $# -gt 3 ]; then
  echo "$0 <XTP> <IPS repo> [cache]";
  exit 1;
fi

if [ ! -f "${1}" ]; then
  echo "[!] Extention pack not found";
  exit 2;
fi

cleanup() {
  tmpdir=$1
  echo -n "\t* cleaning the mess: "
  popd > /dev/null 2>&1
  rm -rf ${tmpdir};
  echo "[DONE]";
}

extpack=$1;

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


filename=$(basename ${extpack} | sed 's/.pkg$//g');
major=$(echo $filename|cut -f 2 -d'-'|sed -e 's/_.*//g;s/\.vbox.extpack//g');
minor=$(echo $filename|cut -f 3 -d'-'|sed 's/\..*//g');
if [ "${minor}" = "" ]; then
  minor=0;
fi
vboxfmri="pkg://${PUBLISHER}/system/virtualbox-extpack@0.5.11,5.11-${major}.${minor}";
tmpdir=$(mktemp -d);
echo "[-] Will try to build IPS package ${vboxfmri}:";


echo -n "\t* building directory structure: ";
mkdir -p ${tmpdir}/proto_install/opt/VirtualBox/extpack
mkdir -p ${tmpdir}/proto_install/var/svc/manifest/application/virtualbox/
echo "[DONE]";

echo -n "\t* copying extpack: ";
cp ${extpack} ${tmpdir}/proto_install/opt/VirtualBox/extpack
echo "[DONE]";

pushd ${PWD} > /dev/null 2>&1
cd ${tmpdir};
echo -n "\t* copy hack-script: ";
echo "${major}.${minor}" > VERSION_XTP
cat > run-once-extpack.sh << "EOF"
#!/usr/bin/sh
. /lib/svc/share/smf_include.sh
lver=$(/usr/bin/svcprop -p config/version $SMF_FMRI)
if [ -f /opt/VirtualBox/VERSION_XTP ]; then
  cver=$(cat /opt/VirtualBox/VERSION_XTP)
else
  cver=""
fi
if [ "$lver" != "$cver" ]; then
  svccfg -s $SMF_FMRI setprop config/assembled = false
  svccfg -s $SMF_FMRI setprop config/version = astring: $cver
  svccfg -s $SMF_FMRI refresh
  echo "--UPDATE virtualbox/run-once-extpack"
fi

assembled=$(/usr/bin/svcprop -p config/assembled $SMF_FMRI)
if [ "$assembled" == "true" ] ; then
    exit $SMF_EXIT_OK
fi
EOF

cat >> run-once-extpack.sh << EOF
/opt/VirtualBox/VBoxManage extpack install --replace /opt/VirtualBox/extpack/${filename}
EOF

cat >> run-once-extpack.sh << "EOF"
svccfg -s $SMF_FMRI setprop config/assembled = true
svccfg -s $SMF_FMRI refresh
echo "--DONE virtualbox/run-once-extpack"
EOF

cat > virtualbox-run-once-extpack.xml << "EOF"
<?xml version="1.0"?>
<!DOCTYPE service_bundle SYSTEM "/usr/share/lib/xml/dtd/service_bundle.dtd.1">
<service_bundle type='manifest' name='VirtualBox:run-once-extpack'>
<service
    name='application/virtualbox/run-once-extpack'
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
    <dependency name='virtualbox-run-once' grouping='require_all' restart_on='none' type='service'>
      <service_fmri value='svc:/application/virtualbox/run-once'/>
    </dependency>
    <dependent
        name='virtualbox-extpack-assembly-complete'
        grouping='optional_all'
        restart_on='none'>
        <service_fmri value='svc:/milestone/self-assembly-complete' />
    </dependent>
    <instance enabled='true' name='default'>
        <exec_method
            type='method'
            name='start'
            exec='/opt/VirtualBox/run-once-extpack.sh'
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
            <propval name='version' type='astring' value='' />
        </property_group>
    </instance>
</service>
</service_bundle>
EOF

cp ./run-once-extpack.sh proto_install/opt/VirtualBox/
cp ./VERSION_XTP proto_install/opt/VirtualBox/
cp ./virtualbox-run-once-extpack.xml proto_install/var/svc/manifest/application/virtualbox/
echo "[DONE]";

echo -n "\t* generating metadata: ";
cat > ${filename}.manifest << EOF
dir  path=var/svc/manifest/application/virtualbox owner=root group=root mode=0755
dir  path=opt/VirtualBox owner=root group=bin mode=0755
dir  path=opt/VirtualBox/extpack owner=root group=bin mode=0755
file opt/VirtualBox/extpack/${filename} \\
	path=/opt/VirtualBox/extpack/${filename} owner=root group=sys mode=0755
file var/svc/manifest/application/virtualbox/virtualbox-run-once-extpack.xml \\
	path=/var/svc/manifest/application/virtualbox/virtualbox-run-once-extpack.xml owner=root group=sys \\
	mode=0644 restart_fmri=svc:/system/manifest-import:default
file opt/VirtualBox/run-once-extpack.sh \\
	path=/opt/VirtualBox/run-once-extpack.sh owner=root group=sys mode=0755
file opt/VirtualBox/VERSION_XTP \\
	path=/opt/VirtualBox/VERSION_XTP owner=root group=sys mode=0644
EOF

cat > ${filename}.meta << EOF
set name=pkg.fmri value="${vboxfmri}"
set name=info.classification \
	value="org.opensolaris.category.2008:Applications/System Utilities"
set name=org.opensolaris.consolidation value=SUNWvbext
set name=variant.opensolaris.zone value=global
set name=pkg.summary value="Oracle VM VirtualBox Extension Pack"
set name=pkg.description value="A powerful PC virtualization solution"
set name=pkg.send.convert.email value=info@virtualbox.org
EOF

cp ${filename}.meta ${filename}.p5m
cat ${filename}.manifest >> ${filename}.p5m
echo "[DONE]";

echo -n "\t* adding dependancies: ";
cat >> ${filename}.p5m << EOF
depend type=require \\
	fmri=pkg:/system/virtualbox@0.5.11-${major}.${minor}
depend type=incorporate \\
	fmri=pkg:/system/virtualbox@0.5.11-${major}.${minor}
EOF
echo "[DONE]";

echo -n "\t* resolving dependancies: ";
pkgdepend resolve -m ${filename}.p5m > /dev/null 2>&1
rc=$?
if [ $rc -gt 1 -o ! -f ./${filename}.p5m.res ]; then
  echo "[FAILED]";
  cleanup ${tmpdir}
  exit 5;
fi
echo "[DONE]";

echo -n "\t* checking package: ";
if [ -z "${cachedir}" ]; then
  mkdir -p ./cache
  cachedir=./cache
fi
pkglint -c ${cachedir} -r ${IREPO} ./${filename}.p5m.res > /dev/null 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "[FAILED]";
  cleanup ${tmpdir}
  exit 5;
fi
echo "[DONE]";

echo -n "\t* publishing package: ";
pkgsend publish -d proto_install -s ${ipsrepo} ./${filename}.p5m.res > /dev/null 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  echo "[FAILED]";
  cleanup ${tmpdir}
  exit 5;
fi
echo "[DONE]";

cleanup ${tmpdir}

#EOF
