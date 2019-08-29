#!/bin/bash
#SOUSAGE
#
#NAME
#  CMD - © MapR Technologies, Inc., All Rights Reserved
#
#DESCRIPTION
#  MapR distribution initialization and setup
#
#SYNOPSIS
#  CMD [options] [docker|install|reload|remove|update]
#
#OPTIONS
#  -a|--archive <full_path_to_archive_file(s)>
#                            For installations of MapR 5.2 and above, specify a
#                              space delimited list of full paths to
#                              mapr-installer-v*.tgz, mapr-mep-v*.tgz, and
#                              mapr-v*.tgz.
#                            For installations of MapR 5.0, and 5.1,
#                              specify the full path to mapr-5.[0-1]*.tgz
#
#  -f|--force                Force re-prompts and do not test for upgrade
#
#  -h|--help                 Display this help message
#
#  -i|--install definitions-pkg installer-pkg
#                            Specify the full path to MapR installer and
#                            service definition packages
#
#  -n|--noinet               Indicate that there is no internet access
#
#  -p|--port [host:]port#    Set installer HTTPS port (9443) and optional
#                            internal network hostname
#
#  -r|--repo                 Specify the top repository URL for MapR installer,
#                            core and ecosystem package directories
#
#  -v|--verbose              Enable verbose output
#
#  -y|--yes                  Do not prompt and accept all default values
#
#EOUSAGE

# BURAK: CONTROL Global Variables
if [ $MAPR_CLUSTER == "None" ]
then
    echo "MAPR_CLUSTER can not set."
    exit
fi
if [ $MAPR_CLDB_HOSTS == "None" ]
then
    echo "MAPR_CLDB_HOSTS can not set."
    exit
fi
if [ $MAPR_CONTAINER_USER == "None" ]
then
    echo "MAPR_CONTAINER_USER can not set."
    exit
fi
if [ $MAPR_MOUNT_PATH == "None" ]
then
    echo "MAPR_MOUNT_PATH can not set."
    exit
fi
if [ $CONFIG_FILE_PATH == "None" ]
then
    echo "CONFIG_FILE_PATH can not set."
    exit
fi
# BURAK: END

# return Codes
NO=0
YES=1
INFO=0
WARN=-1
ERROR=1
BOOLSTR=("false" "true")
DISABLE=2
BOLD=10

# vars
CMD=${0##*/}
CONTINUE_MSG="Continue install anyway?"
DOMAIN=$(hostname -d 2>/dev/null)
ECHOE="echo -e"
[ "$(echo -e)" = "-e" ] && ECHOE="echo"
ID=$(id -u)
INSTALLER=$(cd $(dirname $0) 2>/dev/null && echo $(pwd)/$(basename $0))
ISUPDATE=$NO
NOINET=$NO
PAGER=${PAGER:-more}
PROMPT_FORCE=$NO
PROMPT_SILENT=$NO
SSHD=sshd
SSHD_PORT=22
TEST_CONNECT=$YES
USE_SYSTEMCTL=$NO
USER=$(id -n -u)
VERBOSE=$NO
VERSION=BUILD_VERSION_INTERNAL

MAPR_CLUSTER=${MAPR_CLUSTER:-my.cluster.com}
MAPR_ENVIRONMENT=
MAPR_UID=${MAPR_UID:-5000}
MAPR_GID=${MAPR_GID:-5000}
MAPR_USER=${MAPR_USER-mapr}
MAPR_USER_CREATE=${MAPR_USER_CREATE:-$NO}
MAPR_GROUP=${MAPR_GROUP:-mapr}
MAPR_GROUP_CREATE=${MAPR_GROUP_CREATE:-$NO}
MAPR_HOME=${MAPR_HOME:-/opt/mapr}
MAPR_PORT=${MAPR_PORT:-9443}
MAPR_DATA_DIR=${MAPR_DATA_DIR:-${MAPR_HOME}/installer/data}
MAPR_PROPERTIES_FILE="$MAPR_DATA_DIR/properties.json"
MAPR_PKG_URL=${MAPR_PKG_URL:-http://package.mapr.com/releases}
MAPR_FUSE_CONF="${MAPR_HOME}/conf/fuse.conf"
MAPR_TICKET_FILE=$(basename ${MAPR_TICKETFILE_LOCATION:-mapr_ticket})
# Pass this in the environment to start FUSE
# MAPR_MOUNT_PATH=${MAPR_MOUNT_PATH-/mapr}

MAPR_CORE_URL=${MAPR_CORE_URL:-$MAPR_PKG_URL}
MAPR_ECO_URL=${MAPR_ECO_URL:-$MAPR_PKG_URL}
MAPR_INSTALLER_URL=${MAPR_INSTALLER_URL:-$MAPR_PKG_URL/installer}
MAPR_INSTALLER_PACKAGES=
MAPR_ARCHIVE_DEB=${MAPR_ARCHIVE_DEB:-mapr-latest-*.deb.tar.gz}
MAPR_ARCHIVE_RPM=${MAPR_ARCHIVE_RPM:-mapr-latest-*.rpm.tar.gz}
MAPR_VERSION_CORE=${MAPR_VERSION_CORE:-5.2.0}
MAPR_VERSION_MEP=${MAPR_VERSION_MEP:-2.0}

DEPENDENCY_BASE_DEB="apt-utils curl dnsutils iputils-ping libssl1.0.0 \
nfs-common openssl sudo syslinux sysv-rc-conf wget"
DEPENDENCY_BASE_RPM="curl file openssl sudo syslinux wget which"
DEPENDENCY_BASE_SUSE="curl libopenssl1_0_0 net-tools netcat-openbsd \
nfs-client openssl sudo syslinux util-linux wget which"
DEPENDENCY_DEB="$DEPENDENCY_BASE_DEB debianutils libnss3 libsysfs2 netcat ntp \
ntpdate openssh-client openssh-server python-dev python-pycurl sdparm sshpass \
syslinux sysstat"
DEPENDENCY_RPM="$DEPENDENCY_BASE_RPM device-mapper initscripts iputils \
libsysfs lvm2 nc nfs-utils nss ntp openssh-clients openssh-server \
python-devel python-pycurl rpcbind sdparm sshpass sysstat"
DEPENDENCY_SUSE="$DEPENDENCY_BASE_SUSE device-mapper iputils lvm2 net-tools \
mozilla-nss ntp openssh sdparm sshpass sysfsutils sysstat util-linux" # python[py]curl

EPEL6_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-6.noarch.rpm"
EPEL7_URL="https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"
GPG_KEY_URL="http://package.mapr.com/releases/pub/maprgpg.key"

CONTAINER=$NO
CONTAINER_INITIALIZED=$NO
CONTAINER_PORTS=
CONTAINER_SCRIPT_DIR="$MAPR_HOME/installer/docker"
CONTAINER_SCRIPT="$CONTAINER_SCRIPT_DIR/$(basename $0)"
CONTAINER_CLUSTER_CONF="$MAPR_HOME/conf/mapr-clusters.conf"
CONTAINER_CONFIGURE_SCRIPT="$MAPR_HOME/server/configure.sh"
CONTAINER_SUDO=$YES
[ -f $CONTAINER_CLUSTER_CONF ] && CONTAINER_INITIALIZED=$YES

DOCKER_DIR=${DOCKER_DIR:-$(pwd)/docker_images}
DOCKER_BASE_DIR="$DOCKER_DIR/base"
DOCKER_CORE_DIR="$DOCKER_DIR/core"
DOCKER_CLIENT_DIR="$DOCKER_DIR/client"
DOCKER_FILE=Dockerfile
DOCKER_INSTALLER_DIR="$DOCKER_DIR/installer"
DOCKER_BASE_PACKAGES="mapr-core mapr-hadoop-core mapr-mapreduce2 mapr-zk-internal"
DOCKER_CLIENT_PACKAGES="mapr-client mapr-asynchbase mapr-hbase mapr-kafka"
DOCKER_POSIX_PACKAGE=${DOCKER_POSIX_PACKAGE:-mapr-posix-client-container}

HTTPD_DEB=${HTTPD_DEB:-apache2}
HTTPD_RPM=${HTTPD_RPM:-httpd}
HTTPD_REPO=${HTTPD_REPO:-/var/www/html/mapr}

OPENJDK_DEB=${OPENJDK_DEB:-openjdk-7-jdk}
OPENJDK_DEB_7=${OPENJDK_DEB_7:-openjdk-7-jdk}
OPENJDK_DEB_8=${OPENJDK_DEB_8:-openjdk-8-jdk}
OPENJDK_RPM=${OPENJDK_RPM:-java-1.8.0-openjdk-devel}
OPENJDK_RPM_7=${OPENJDK_RPM_7:-java-1.7.0-openjdk-devel}
OPENJDK_RPM_8=${OPENJDK_RPM_8:-java-1.8.0-openjdk-devel}
OPENJDK_SUSE=${OPENJDK_SUSE:-java-1_8_0-openjdk-devel}
OPENJDK_SUSE_7=${OPENJDK_SUSE_7:-java-1_7_0-openjdk-devel}
OPENJDK_SUSE_8=${OPENJDK_SUSE_8:-java-1_8_0-openjdk-devel}

# OS support matrix
declare -a SUPPORTED_RELEASES_RH=('6.1' '6.2' '6.3' '6.4' '6.5' '6.6' '6.7' \
'6.8' '7.0' '7.1' '7.2' '7.3')
declare -a SUPPORTED_RELEASES_SUSE=('11.3' '12' '12.0' '12.1')
declare -a SUPPORTED_RELEASES_UBUNTU=('12.04' '14.04' '16.04')

export JDK_QUIET_CHECK=$YES # don't want env.sh to exit
export JDK_REQUIRED=$YES    # ensure we have full JDK
JDK_VER=0
JDK_UPGRADE_JRE=$NO
JDK_UPDATE_ONLY=$NO
JAVA_HOME_OLD=

if hostname -A > /dev/null 2>&1; then
    HOST=$(hostname -A | cut -d' ' -f1)
fi
if [ -z "$HOST" ] && hostname --fqdn > /dev/null 2>&1; then
    HOST=$(hostname --fqdn 2>/dev/null)
fi
if [ -z "$HOST" ]; then
    HOST=$(hostname 2>/dev/null)
fi
if [ -z "$HOST" ] && hostname -I > /dev/null 2>&1; then
    HOST=$(hostname -I | cut -d' ' -f1)
fi
if [ -z "$HOST" ] && which ip > /dev/null 2>&1 && ip addr show > /dev/null 2>&1; then
    HOST=$(ip addr show | grep inet | grep -v 'scope host' | head -1 | \
        sed -e 's/^[^0-9]*//; s/\(\([0-9]\{1,3\}\.\)\{3\}[0-9]\{1,3\}\).*/\1/')
fi
if [ -z "$HOST" -a $(uname -s) = "Darwin" ]; then
    HOST=$(ipconfig getifaddr en0)
    [ -z "$HOST" ] && HOST=$(ipconfig getifaddr en1)
fi

HOST_INTERNAL=$HOST
MAPR_HOST=$HOST:$MAPR_PORT

# determine timezone
MAPR_TZ=${MAPR_TZ:-$TZ}
[ -z "$MAPR_TZ" ] && MAPR_TZ="$(cat /etc/timezone 2> /dev/null)"
[ -z "$MAPR_TZ" ] && MAPR_TZ="$(readlink /etc/localtime | sed -e 's|.*zoneinfo/||')"
[ -z "$MAPR_TZ" ] && MAPR_TZ="$(grep "ZONE=" /etc/sysconfig/clock 2> /dev/null | cut -d'"' -f 2)"
[ -z "$MAPR_TZ" ] && MAPR_TZ=US/Pacific

# check to see if we are running in a container env
RESULTS=$(cat /proc/1/sched 2>&1| head -n 1 | awk '{gsub("[(,]","",$2); print $2}')
[ $? -eq 0 ] && echo "$RESULTS" | grep -Eq '^[0-9]+$' && [ $RESULTS -ne 1 ] && \
   CONTAINER=$YES

# determine if we should use systemctl or service for process management
if [ $CONTAINER -eq $YES ]; then
    [ -x "/usr/bin/systemctl" ] && USE_SYSTEMCTL=$YES
else
    which systemctl >/dev/null 2>&1 && systemctl | fgrep -q '.mount' && \
        USE_SYSTEMCTL=$YES
fi

unset MAPR_ARCHIVE
unset MAPR_DEF_VERSION
unset MAPR_SERVER_VERSION
unset OS

##
## functions
##

catchTrap() {
    messenger $INFO ""
}

centerMsg() {
    local width=$(tput cols)
    $ECHOE "$1" | awk '{ spaces = ('$width' - length) / 2
        while (spaces-- >= 1) printf (" ")
        print
    }'
}

# Print each word according to the screen size
formatMsg() {
    WORDS=$1
    LENGTH=0
    local width=$(tput cols)
    width=${width:-80}
    for WORD in $WORDS; do
        LENGTH=$(($LENGTH + ${#WORD} + 1))
        if [ $LENGTH -gt $width ]; then
            $ECHOE "\n$WORD \c"
            LENGTH=$((${#WORD} + 1))
        else
            $ECHOE "$WORD \c"
        fi
    done
    [ -z "$2" ] && $ECHOE "\n"
}

getJsonField() {
    res=$(echo "$1" | grep -Po "$2"'.*?[^\\]",' | cut -d: -f2 | \
        sed -e 's/ *"/"/;s/",/"/')
    echo "$res"
}

# Output an error, warning or regular message
messenger() {
    case $1 in
    $BOLD)
        tput bold
        formatMsg "$2"
        tput sgr0
        ;;
    $ERROR)
        tput bold
        formatMsg "\nERROR: $2"
        tput sgr0
        [ $MAPR_USER_CREATE -eq $YES ] && userdel $MAPR_USER > /dev/null 2>&1
        [ $MAPR_GROUP_CREATE -eq $YES ] && groupdel $MAPR_GROUP > /dev/null 2>&1
        exit $ERROR
        ;;
    $INFO)
        formatMsg "$2"
        ;;
    $WARN)
        tput bold
        formatMsg "\nWARNING: $2"
        tput sgr0
        sleep 3
        ;;
    *)
        formatMsg "$1" $2
        ;;
    esac
}

prompt() {
    QUERY=$1
    DEFAULT=${2:-""}
    shift 2
    if [ $PROMPT_SILENT -eq $YES ]; then
        if [ -z "$DEFAULT" ]; then
            messenger $ERROR "no default value available"
        else
            messenger "$QUERY: $DEFAULT\n" "-"
            ANSWER=$DEFAULT
            return
        fi
    fi
    unset ANSWER
    # allow SIGINT to interrupt
    trap - SIGINT
    while [ -z "$ANSWER" ]; do
        if [ -z "$DEFAULT" ]; then
            messenger "$QUERY:" "-"
        else
            messenger "$QUERY [$DEFAULT]:" "-"
        fi
        if [ "$1" = "-s" -a -z "$BASH" ]; then
            trap 'stty echo' EXIT
            stty -echo
            read ANSWER
            stty echo
            trap - EXIT
        else
            read $* ANSWER
        fi
        if [ "$ANSWER" = "q!" ]; then
            exit 1
        elif [ -z "$ANSWER" -a -n "$DEFAULT" ]; then
            ANSWER=$DEFAULT
        fi
        [ "$1" = "-s" ] && echo
    done
    # don't allow SIGINT to interrupt
    if [ "$OS" = "ubuntu" ]; then
        trap catchTrap SIGINT
    else
        trap '' SIGINT
    fi
}

prompt_boolean() {
    unset ANSWER
    while [ -z "$ANSWER" ]; do
        prompt "$1 (y/n)" ${2:-y}
        case "$ANSWER" in
        n*|N*) ANSWER=$NO; break ;;
        y*|Y*) ANSWER=$YES; break ;;
        *) unset ANSWER ;;
        esac
    done
}

prompt_package() {
    prompt_boolean "Add $1 to image?" $4
    if [ $ANSWER -eq $YES ]; then
        PACKAGES="$PACKAGES $2"
        if [ -z "$TAG" ]; then
            TAG=$3
        else
            TAG="${TAG}_$3"
        fi
        shift 4
        if [ $# -gt 0 ]; then
            CONTAINER_PORTS="$CONTAINER_PORTS $*"
        fi
    fi
}

success() {
    local s="...Success"

    [ "$1" = "$YES" ] && s="\n$s"
    [ -n "$2" ] && s="$s - $2"
    messenger "$s"
}

# the /usr/bin/tput may not exist in docker container
tput() {
    [ -f /usr/bin/tput ] && /usr/bin/tput $*
}

usage() {
    code=${1-1}
    [ $code -ne 0 ] && messenger $WARN "invalid command-line arguments\c"
    head -50 $INSTALLER | sed -e '1,/^#SOUSAGE/d' -e '/^#EOUSAGE/,$d' \
        -e 's/^\#//' -e "s?CMD?$CMD?" | $PAGER
    exit $code
}

warnPromptContinue() {
    [ -n "$1" ] && messenger $WARN "$1"
    prompt_boolean "$2" "$3"
    return $ANSWER
}

# WARNING: The code from here to the next tag is included in env.sh.
#          any changes should be applied there too
check_java_home() {
    local found=0
    if [ -n "$JAVA_HOME" ]; then
        if [ $JDK_REQUIRED -eq 1 ]; then
            if [ -e "$JAVA_HOME"/bin/javac -a -e "$JAVA_HOME"/bin/java ]; then
                found=1
            fi
        elif [ -e "$JAVA_HOME"/bin/java ]; then
            found=1
        fi
        if [ $found -eq 1 ]; then
            java_version=$($JAVA_HOME/bin/java -version 2>&1 | fgrep version | \
                head -n1 | cut -d '.' -f 2)
            [ -z "$java_version" ] || echo $java_version | \
                fgrep -i Error > /dev/null 2>&1 || [ "$java_version" -le 6 ] && \
                unset JAVA_HOME
        else
            unset JAVA_HOME
        fi
    fi
}

# WARNING:  You must replicate any changes here in env.sh
verifyJavaEnv() {
    # We use this flag to force checks for full JDK
    JDK_QUIET_CHECK=${JDK_QUIET_CHECK:-0}
    JDK_REQUIRED=${JDK_REQUIRED:-0}

    # Handle special case of bogus setting in some virtual machines
    [ "${JAVA_HOME:-}" = "/usr" ] && JAVA_HOME=""

    # Look for installed JDK
    if [ -z "$JAVA_HOME" ]; then
        sys_java="/usr/bin/java"
        if [ -e $sys_java ]; then
            jcmd=$(readlink -f $sys_java)
            if [ $JDK_REQUIRED -eq 1 ]; then
                if [ -x ${jcmd%/jre/bin/java}/bin/javac ]; then
                    JAVA_HOME=${jcmd%/jre/bin/java}
                elif [ -x ${jcmd%/java}/javac ]; then
                    JAVA_HOME=${jcmd%/bin/java}
                fi
            else
                if [ -x ${jcmd} ]; then
                    JAVA_HOME=${jcmd%/bin/java}
                fi
            fi
            [ -n "$JAVA_HOME" ] && export JAVA_HOME
        fi
    fi

    check_java_home

    # MARKER - DO NOT DELETE THIS LINE
    # attempt to find java if JAVA_HOME not set
    if [ -z "$JAVA_HOME" ]; then
        for candidate in \
            /Library/Java/Home \
            /usr/java/default \
            /usr/lib/jvm/default-java \
            /usr/lib*/jvm/java-8-openjdk* \
            /usr/lib*/jvm/java-8-oracle* \
            /usr/lib*/jvm/java-8-sun* \
            /usr/lib*/jvm/java-1.8.* \
            /usr/lib*/jvm/java-7-openjdk* \
            /usr/lib*/jvm/java-7-oracle* \
            /usr/lib*/jvm/java-7-sun* \
            /usr/lib*/jvm/java-1.7.* ; do
            if [ -e $candidate/bin/java ]; then
                export JAVA_HOME=$candidate
                check_java_home
                if [ -n "$JAVA_HOME" ]; then
                    break
                fi
            fi
        done
        # if we didn't set it
        if [ -z "$JAVA_HOME" -a $JDK_QUIET_CHECK -eq $NO ]; then
            cat 1>&2 <<EOF
+======================================================================+
|      Error: JAVA_HOME is not set and Java could not be found         |
+----------------------------------------------------------------------+
| MapR requires Java 1.7 or later.                                     |
| NOTE: This script will find Oracle or Open JDK Java whether you      |
|       install using the binary or the RPM based installer.           |
+======================================================================+
EOF
            exit 1
        fi
    fi

    if [ -n "${JAVA_HOME}" ]; then
        # export JAVA_HOME to PATH
        export PATH=$JAVA_HOME/bin:$PATH
    fi
}

# WARNING: The code above is also in env.sh

prologue() {
    tput clear
    tput bold
    centerMsg "\nMapR Distribution Initialization and Update\n"
    centerMsg "Copyright $(date +%Y) MapR Technologies, Inc., All Rights Reserved"
    centerMsg "http://www.mapr.com\n"
    tput sgr0
    checkOS
    warnPromptContinue "" "$1?"
    [ $? -eq $NO ] && exit 1
}

epilogue() {
    tput bold
    centerMsg "To continue installing MapR software, open the following URL in a web browser"
    centerMsg ""
    if [ "$HOST_INTERNAL" = "$HOST" ]; then
        centerMsg "If the address '$HOST' is internal and not accessible"
        centerMsg "from your browser, use the external address mapped to it instead"
        centerMsg ""
    fi
    centerMsg "https://$HOST:$MAPR_PORT"
    centerMsg ""
    tput sgr0
}

setPort() {
    local port
    local host
    local first_time
    first_time=1

    while [ -z "$port" ]; do
        if [ $first_time -eq 1 ]; then
            # we loop through once to make sure MAPR_HOST contains both
            # a hostname and port number before we use it in the prompt
            ANSWER=$MAPR_HOST
        else
            prompt "Enter [host:]port that cluster nodes connect to this host on" "$MAPR_HOST"
        fi
        host=$(echo $ANSWER | cut -d: -f1)
        port=$(echo $ANSWER | cut -s -d: -f2)
        if [ -z "$port" ]; then
            case $host in
            ''|*[!0-9]*) port=$MAPR_PORT ;;
            *) port=$host && host=$HOST ;;
            esac
        else
            case $port in
            ''|*[!0-9]*)
                messenger $WARN "Port must be numeric ($port)"
                # make sure we don't loop forever
                [ $PROMPT_SILENT -eq $YES ] && exit $ERROR
                unset port ;;
            esac
        fi
        if [ $first_time -eq 1 ]; then
            if [ -z $port ]; then
                MAPR_HOST=$host:$MAPR_PORT
            else
                MAPR_HOST=$host:$port
                unset port
            fi
            first_time=0
        fi
    done
    HOST=$host
    MAPR_HOST=$host
    MAPR_PORT=$port
}

# Refresh package manager and install package dependencies
fetchDependencies() {
    messenger "\nInstalling package dependencies ($DEPENDENCY)"
    case $OS in
    redhat)
        # remove it in case it has bad info in it, will get recreated
        rm -f /etc/yum.repos.d/mapr_installer.repo
        if [ "$MAPR_CORE_URL" = "$MAPR_ECO_URL" ]; then
            yum -q clean expire-cache
        else
            yum -q clean all
        fi
        if ! rpm -qa | grep -q epel-release; then
            yum -q -y install epel-release
            if [ $? -ne 0 ]; then
                if [ $NOINET -eq $YES ]; then
                    messenger $ERROR "Unable to install epel-release package - set up local repo"
                else
                    if grep -q " 7." /etc/redhat-release; then
                        yum -q -y install $EPEL7_URL
                    elif grep -q " 6." /etc/redhat-release; then
                        yum -q -y install $EPEL6_URL
                    fi
                    if [ $? -ne 0 ]; then
                        messenger $ERROR "Unable to install epel-release package"
                    fi
                fi
            fi
        fi
        yum --disablerepo=epel -q -y update ca-certificates
        yum -q -y install $DEPENDENCY
        ;;
    suse)
        rm -f /etc/zypp/repos.d/mapr_installer.repo
        zypper --non-interactive -q refresh
        if zypper --non-interactive -q install -n $DEPENDENCY; then
            if [ -e /usr/lib64/libcrypto.so.1.0.0 ]; then
                ln -f -s /usr/lib64/libcrypto.so.1.0.0 /usr/lib64/libcrypto.so.10
            elif [ -e /lib64/libcrypto.so.1.0.0 ]; then
                ln -f -s /lib64/libcrypto.so.1.0.0 /lib64/libcrypto.so.10
            fi
            if [ -e /usr/lib64/libssl.so.1.0.0 ]; then
                ln -f -s /usr/lib64/libssl.so.1.0.0 /usr/lib64/libssl.so.10
            elif [ -e /lib64/libssl.so.1.0.0 ]; then
                ln -f -s /lib64/libssl.so.1.0.0 /lib64/libssl.so.10
            fi
        else
            false
        fi
        ;;
    ubuntu)
        rm -f /etc/apt/sources.list.d/mapr_installer.list
        apt-get update -qq
        apt-get install -qq -y $DEPENDENCY
        ;;
    esac
    if [ $? -ne 0 ]; then
        messenger $ERROR "Unable to install dependencies ($DEPENDENCY). Ensure that a core OS repo is enabled and retry $CMD"
    fi
    success $YES
    testJDK
}

# determine cloud environment and public hostnames if possible
fetchEnvironment() {
    # if host is in EC2 or GCE, find external IP address from metadata server
    RESULTS=$(wget -q -O - -T1 -t1 http://instance-data/latest/meta-data/public-hostname)
    if [ $? -eq 0 ] && ! echo $RESULTS | grep '[<>="/:\?\&\+\(\)\;]' > /dev/null 2>&1 ; then
        # we have a valid hostname, not some random webpage....
        HOST=$RESULTS
        MAPR_ENVIRONMENT=amazon
    else
        RESULTS=$(wget -q -O - -T1 -t1 --header "Metadata-Flavor: Google" \
            http://metadata.google.internal/computeMetadata/v1/instance/hostname)
        if [ $? -eq 0 ]; then
            HOST=$RESULTS
            MAPR_ENVIRONMENT=google
        else
            RESULTS=$(wget -q -O - -T1 http://ipinfo.io)
            if [ $? -eq 0 ]; then
                # not found a reliable way to find external hostname yet
                # azure is working on a REST interface similar to AWS'
                m_org=$(getJsonField "$RESULTS" '"org":')
                m_org=$(echo $m_org | fgrep -i "Microsoft Corporation")
                m_dns=$(grep 'cloudapp.net' /etc/resolv.conf)
                if [ -n "$m_org" -a -n "$m_dns" ]; then
                    MAPR_ENVIRONMENT=azure
                fi
                m_hn=$(getJsonField "$RESULTS" '"hostname":')
                m_hn=$(echo "$m_hn" | fgrep -vi "No Hostname")
                if [ -n "$m_hn" ]; then
                    echo "$m_hn" | fgrep -qi azure.com && HOST=$m_hn
                fi
            fi
        fi
    fi
}

# check for supported OS version
verifyOSVersion() {
    # $1 is os name
    # $2 is os version
    # $3-n is the supported os versions
    local supporedOSFound=0
    local osName=$1
    local osVer=$2
    shift 2


    for sv in ${@} ; do
        if [ "$sv" == "$osVer" ]; then
            supportedOSFound=1
            break
        fi
    done
    if [ ! ${supportedOSFound} ]; then
        warnPromptContinue "$osName release '$osVer' is not supported" "$CONTINUE_MSG"
        [ $? -eq $NO ] && exit 1
    fi
}

verifyPermsOnChkPwd() {
    case $OS in
    redhat|suse)
        CHKPWD_PERM="-4000"
        CHKPWD_ID="suid"
        ;;
    ubuntu)
        CHKPWD_PERM="-2000"
        CHKPWD_ID="sgid"
        ;;
    esac
    find -L /sbin -perm $CHKPWD_PERM  | fgrep unix_chkpwd > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        warnPromptContinue "unix_chkpwd does not have the $CHKPWD_ID bit set so local password authentication will fail" \
            "$CONTINUE_MSG"
        [ $? -eq $NO ] && exit 1
    fi
}

# validate current OS
checkOS() {
    if ! which ping > /dev/null 2>&1 ; then
        [ $CONTAINER -eq $NO ] && messenger $ERROR "ping command not found"
    elif [ -z "$HOST" ] || ! ping -c 1 -q "$HOST" > /dev/null 2>&1 ; then
        messenger $ERROR "Hostname ($HOST) cannot be resolved. Correct the problem and re-run $CMD"
    fi
    if [ -f /etc/redhat-release ]; then
        OS=redhat
        OSNAME=$(cut -d' ' -f1 < /etc/redhat-release)
        OSVER=$(grep -o -P '[0-9\.]+' /etc/redhat-release | cut -d. -f1,2)
        OSVER_MAJ=$(grep -o -P '[0-9\.]+' /etc/redhat-release | cut -d. -f1)
        OSVER_MIN=$(grep -o -P '[0-9\.]+' /etc/redhat-release | cut -d. -f2)
        verifyOSVersion "$OSNAME" "$OSVER" ${SUPPORTED_RELEASES_RH[@]}
    elif [ -d /etc/mach_init.d ]; then
        OS=darwin
        OSVER=$(uname -r)
        OSVER_MAJ=$(echo $OSVER | cut -d\. -f1)
        OSVER_MIN=$(echo $OSVER | cut -d\. -f2)
    elif [ -f /etc/SuSE-release ] || grep -q SUSE /etc/os-release ; then
        OS=suse
        if [ -f /etc/os-release ]; then
            OSVER=$(grep VERSION_ID /etc/os-release | cut -d\" -f2)
            OSVER_MAJ=$(echo $OSVER | cut -d\. -f1)
            OSVER_MIN=$(echo $OSVER | cut -d\. -f2)
        else
            OSVER=$(grep VERSION /etc/SuSE-release | cut -d= -f2 | tr -d '[:space:]')
            OSVER_MAJ=$OSVER
            OSPATCHLVL=$(grep PATCHLEVEL /etc/SuSE-release | cut -d= -f2 | tr -d '[:space:]')
            if [ -n "$OSPATCHLVL" ]; then
                OSVER=$OSVER.$OSPATCHLVL
                OSVER_MIN=$OSPATCHLVL
            fi
        fi
        verifyOSVersion "$OS" "$OSVER" ${SUPPORTED_RELEASES_SUSE[@]}
    elif [ -f /etc/lsb-release ] && grep -q DISTRIB_ID=Ubuntu /etc/lsb-release; then
        OS=ubuntu
        OSVER=$(grep DISTRIB_RELEASE /etc/lsb-release | cut -d= -f2)
        OSVER_MAJ=$(echo $OSVER | cut -d\. -f1)
        OSVER_MIN=$(echo $OSVER | cut -d\. -f2)
        SSHD=ssh
        verifyOSVersion "$OS" "$OSVER" ${SUPPORTED_RELEASES_UBUNTU[@]}
    else
        messenger $ERROR "$CMD must be run on RedHat, CentOS, SUSE, or Ubuntu Linux"
    fi
    if [ $(uname -m) != "x86_64" ]; then
        messenger $ERROR "$CMD must be run on a 64 bit version of Linux"
    fi
    [ $OS != "darwin" ] && verifyPermsOnChkPwd
    case $OS in
    redhat)
        DEPENDENCY=$DEPENDENCY_RPM
        DEPENDENCY_BASE=$DEPENDENCY_BASE_RPM
        HTTPD=$HTTPD_RPM
        MAPR_ARCHIVE=${MAPR_ARCHIVE:-$MAPR_ARCHIVE_RPM}
        OPENJDK=$OPENJDK_RPM
        ;;
    suse)
        DEPENDENCY=$DEPENDENCY_SUSE
        if [ $OSVER_MAJ -ge 12 ]; then
            DEPENDENCY="python-pycurl $DEPENDENCY"
        else
            DEPENDENCY="python-curl $DEPENDENCY"
        fi
        DEPENDENCY_BASE=$DEPENDENCY_BASE_SUSE
        HTTPD=$HTTPD_RPM
        MAPR_ARCHIVE=${MAPR_ARCHIVE:-$MAPR_ARCHIVE_RPM}
        OPENJDK=$OPENJDK_SUSE
        ;;
    ubuntu)
        DEPENDENCY=$DEPENDENCY_DEB
        DEPENDENCY_BASE=$DEPENDENCY_BASE_DEB
        HTTPD=$HTTPD_DEB
        MAPR_ARCHIVE=${MAPR_ARCHIVE:-$MAPR_ARCHIVE_DEB}
        OPENJDK=$OPENJDK_DEB
        ;;
    esac
}

# Set the corresponding devel JDK version
# $1 is JRE version number (7, 8 ...)
forceJDKVersion() {
    local pkg

    case $OS in
    redhat) pkg="OPENJDK_RPM_$1" ;;
    suse) pkg="OPENJDK_SUSE_$1" ;;
    ubuntu) pkg="OPENJDK_DEB_$1" ;;
    esac
    OPENJDK=${!pkg}
}

# Test if JDK 7 or higher is installed
testJDK() {
    # if javac exists, then JDK-devel has been installed
    messenger "Testing for JDK 7 or higher ..."
    [ -n "$JAVA_HOME" ] && JAVA_HOME_OLD=$JAVA_HOME

    # determine what kind of Java env we have
    verifyJavaEnv
    if [ -z "$JAVA_HOME" ]; then
        # try again to see if we have a valid JRE
        JDK_REQUIRED=0
        verifyJavaEnv
        if [ -n "$JAVA_HOME" ]; then
            JAVA=${JAVA_HOME}/bin/java
            JDK_UPGRADE_JRE=1
        fi
    else
        JAVA=${JAVA_HOME}/bin/java
    fi

    if [ -n "$JAVA" -a -e "$JAVA" ]; then
        JDK_VER=$($JAVA_HOME/bin/java -version 2>&1 | head -n1 | cut -d. -f2)
    fi

    # check if javac is actually valid and exists
    if [ -n "$JAVA_HOME" -a $JDK_UPGRADE_JRE -eq $YES ]; then
        # we found a jre that we can upgrade
        FETCH_MSG="Upgrading JRE to JDK 1.$JDK_VER"
        forceJDKVersion $JDK_VER
    elif [ -z "${JAVA_HOME}" ]; then
        # install the latest jdk-devel
        FETCH_MSG="JDK not found - installing $OPENJDK..."
    else
        FETCH_MSG="Ensuring existing JDK 1.$JDK_VER is up to date"
    fi
    fetchJDK
    success
}

# install OpenJDK if no version found that can be upgraded to JDK
fetchJDK() {
    local warn_msg=""

    if [ -n "$JAVA_HOME" -a $JDK_UPGRADE_JRE -eq $NO ]; then
        # We are only going to make sure we have the latest one of the installed jdk package
        JDK_UPDATE_ONLY=$YES
    elif [ -n "$JAVA_HOME" ]; then
        if [ -n "$JAVA_HOME_OLD" ]; then
            if [ "$JAVA_HOME" = "$JAVA_HOME_OLD" -a $JDK_UPGRADE_JRE -eq $YES ]; then
                warn_msg="JAVA_HOME is set to a JRE which is not sufficient. $CMD can upgrade it to a full JDK"
            else
                warn_msg="JAVA_HOME is set to a JDK that is missing or too old. $CMD can install a more current version"
            fi
        else
            warn_msg="JAVA_HOME is not set, but found a JRE, which is not sufficient. $CMD can upgrade it to a full JDK"
        fi
        warnPromptContinue "$warn_msg" \
            "Continue and upgrade JDK 1.$JDK_VER? If no, either manually install a JDK or remove JAVA_HOME from /etc/profile or login scripts and re-run mapr-setup.sh"
        [ $? -eq $NO ] && exit 1
    fi
    messenger "$FETCH_MSG"
    case $OS in
    redhat)
        if [ $JDK_UPDATE_ONLY -eq $YES ]; then
            JDK_PKG=$(rpm -q --whatprovides $JAVA_HOME/bin/javac 2> /dev/null)
            if [ -n "$JDK_PKG" ]; then
                OPENJDK=$JDK_PKG
                yum -q -y upgrade $OPENJDK
            fi
        else
            yum -q -y install $OPENJDK
        fi
        ;;
    suse)
        if [ $JDK_UPDATE_ONLY -eq $YES ]; then
            JDK_PKG=$(rpm -q --whatprovides $JAVA_HOME/bin/javac 2> /dev/null)
            if [ -n "$JDK_PKG" ]; then
                OPENJDK=$JDK_PKG
            fi
        fi
        zypper --non-interactive -q install -n $OPENJDK
        ;;
    ubuntu)
        if [ $JDK_UPDATE_ONLY -eq $YES ]; then
            JDK_PKG=$(dpkg-query -S $JAVA_HOME/bin/javac 2> /dev/null | cut -d: -f1)
            if [ -n "$JDK_PKG" ]; then
                OPENJDK=$JDK_PKG
            fi
        fi
        apt-get install -qq -y --force-yes $OPENJDK
        ;;
    esac
    if [ $? -ne 0 ]; then
        messenger $ERROR "Unable to install JDK $JDK_VER ($OPENJDK). Install manually and retry $CMD"
    fi
}

# Is there a webserver and is it listening on port 80.
# If port 80 is not listening, assume there's no web service.
# Prompt the user on whether to install apache2/httpd or continue
testPort80() {
    local rc=$YES

    # If nothing is returned, then port 80 is not active
    if $(ss -lnt "( sport = :80 or sport = :443 )" | grep -q LISTEN); then
        messenger "Existing web server will be used to serve packages from this system"
    else
        messenger "No web server detected, but is required to serve packages from this system"

        warnPromptContinue "" "Would you like to install a webserver on this system?"
        rc=$?
        [ $rc -eq $YES ] && fetchWebServer
    fi
    return $rc
}

# If no web server was found, install and start apache2/httpd
fetchWebServer() {
    messenger "Installing web server..."
    case $OS in
    redhat) yum -q -y install $HTTPD ;;
    suse) zypper --non-interactive -q install -n $HTTPD ;;
    ubuntu) apt-get install -qq -y $HTTPD ;;
    esac

    if [ $? -ne 0 ]; then
        messenger $ERROR "Unable to install web server '$HTTPD'. Please correct the error and retry $CMD"
    fi

    # start newly installed web service
    if [ $USE_SYSTEMCTL -eq $YES ]; then
        systemctl start $HTTPD
    else
        service $HTTPD start
    fi
    if [ $? -ne 0 ]; then
        messenger $ERROR "Unable to start web server. Please correct the error and retry $CMD"
    fi
}

# Test the connection MapR Techonolgies, Inc. If a
# connection exists, then use the MapR URLs. Othewise,
# prompt the user for the location of the MapR archive tarball
testConnection() {
    # If a MapR package tarball has been given, use that as the default
    ISCONNECTED=$NO
    if [ $TEST_CONNECT -eq $YES ]; then
        messenger "Testing connection to $MAPR_INSTALLER_URL...\c"
        if which wget > /dev/null 2>&1 && wget -q --spider "$MAPR_INSTALLER_URL/" -O /dev/null || wget -q --spider "$MAPR_INSTALLER_URL/$CMD" -O /dev/null; then
            ISCONNECTED=$YES
            success
            return
        elif which curl > /dev/null 2>&1 && curl -f -s -o /dev/null "$MAPR_INSTALLER_URL/" || curl -f -s -o /dev/null "$MAPR_INSTALLER_URL/$CMD"; then
            ISCONNECTED=$YES
            success
            return
        elif ping -c 1 -q $(echo "$MAPR_INSTALLER_URL/" | cut -d/ -f3) > /dev/null 2>&1; then
            ISCONNECTED=$YES
            success
            return
        elif [ -n "$MAPR_INSTALLER_PACKAGES" ]; then
            messenger $ERROR "Connectivity to $MAPR_INSTALLER_URL required"
        else
            messenger "...No connection found"
            messenger "Without connectivity to MapR Technologies ($MAPR_INSTALLER_URL),
                the complete MapR archive tarball is required to complete this setup"

            ARCHIVE_PROMPT="Enter the path to the MapR archive - one or 3 files (space separated)"
            prompt "$ARCHIVE_PROMPT" "$MAPR_ARCHIVE"
            VALID_FILES=0
            while [ "$VALID_FILES" -eq 0 ]; do
                file_cnt=0
                valid_file_cnt=0
                NEW_MAPR_ARCHIVE=""
                for af in $ANSWER ; do
                    let file_cnt=file_cnt+1
                    if [ -f "$af" ]; then
                        NEW_MAPR_ARCHIVE="$NEW_MAPR_ARCHIVE $(cd $(dirname $af); pwd)/$(basename $af)"
                        let valid_file_cnt=valid_file_cnt+1
                    else
                        messenger $WARN "$af: no such file"
                    fi
                done
                if [ $file_cnt -ne $valid_file_cnt ]; then
                    prompt "$ARCHIVE_PROMPT" "$MAPR_ARCHIVE"
                elif [ $file_cnt -ne 1 -a $file_cnt -ne 3 ]; then
                    messenger $WARN "Need 1 or 3 archive files - not $file_cnt"
                    prompt "$ARCHIVE_PROMPT" "$MAPR_ARCHIVE"
                else
                    VALID_FILES=1
                fi
            done
            MAPR_ARCHIVE="$NEW_MAPR_ARCHIVE"
        fi
    fi

    messenger "\nCreating local repo from $MAPR_ARCHIVE...\c"
    testPort80

    prompt "Enter the web server filesystem directory to extract the MapR archive to" "$HTTPD_REPO"
    HTTPD_REPO="$ANSWER"

    prompt "\nEnter web server url for this path" "http://$HOST_INTERNAL/$(basename $HTTPD_REPO)"
    MAPR_ECO_URL="$ANSWER"
    MAPR_CORE_URL="$ANSWER"

    messenger "\nExtracting packages from $MAPR_ARCHIVE...\c"
    [ -d "$HTTPD_REPO/installer" ] && rm -rf "$HTTPD_REPO"
    mkdir -p "$HTTPD_REPO"
    for af in $MAPR_ARCHIVE ; do
        if ! tar -xvzf $af -C "$HTTPD_REPO"; then
            messenger $ERROR "Unable to extract archive file"
        fi
    done
    success $YES
}

# ensure that root and admin users have correct permissions
checkSudo() {
    if ! su $MAPR_USER -c "id $MAPR_USER" > /dev/null 2>&1 ; then
        messenger $ERROR "User 'root' is unable to run services as user '$MAPR_USER'. Correct the problem and re-run $CMD"
    fi
    dir=$(getent passwd $MAPR_USER | cut -d: -f6)
    if [ -d "$dir" ] && ! su $MAPR_USER -c "test -O $dir -a -w $dir" ; then
        messenger $ERROR "User '$MAPR_USER' does not own and have permissions to write to '$dir'. Correct the problem and re-run $CMD"
    fi
    gid=$(stat -c '%G' /etc/shadow)
    if [ $MAPR_USER_CREATE -eq $NO ] && ! id -Gn $MAPR_USER | grep -q $gid ; then
        messenger $WARN "User '$MAPR_USER' must be in group '$gid' to allow UNIX authentication"
    fi
    success
}

# If a 'mapr' user account does not exist or a user
# defined account does not exist, create a 'mapr' user account
createUser() {
    local acct_type=${1:-admin}

    messenger "\nTesting for cluster $acct_type account..."
    tput sgr0
    prompt "Enter MapR cluster $acct_type name" "$MAPR_USER"
    TMP_USER=$ANSWER
    while [ "$TMP_USER" = root -a -z "$DOCKER_CMD" ]; do
        messenger $WARN "Cluster $acct_type cannot be root user"
        prompt "Enter MapR cluster $acct_type name" "$MAPR_USER"
        TMP_USER=$ANSWER
    done
    MAPR_USER=$TMP_USER

    set -- $(getent passwd $MAPR_USER | tr ':' ' ')
    TMP_UID=$3
    TMP_GID=$4

    # If the given/default user name is valid, set the
    # returned uid and gid as the mapr user
    if [ -n "$TMP_UID" -a -n "$TMP_GID" ]; then
        MAPR_UID=$TMP_UID
        MAPR_GID=$TMP_GID
        MAPR_GROUP=$(getent group $MAPR_GID | cut -d: -f1)
        checkSudo
        return
    fi

    messenger "\nUser '$MAPR_USER' does not exist. Creating new cluster $acct_type account..."

    # ensure that the given/default uid doesn't already exist
    if getent passwd $MAPR_UID > /dev/null 2>&1 ; then
        MAPR_UID=""
    fi
    prompt "Enter '$MAPR_USER' uid" "$MAPR_UID"
    TMP_UID=$ANSWER
    while getent passwd $TMP_UID > /dev/null 2>&1 ; do
        messenger $WARN "uid $TMP_UID already exists"
        prompt "Enter '$MAPR_USER' uid" "$MAPR_UID"
        TMP_UID=$ANSWER
    done
    MAPR_UID=$TMP_UID
    # prompt the user for the mapr user's group
    prompt "Enter '$MAPR_USER' group name" "$MAPR_GROUP"
    MAPR_GROUP=$ANSWER

    set -- $(getent group $MAPR_GROUP | tr ':' ' ')
    TMP_GID=$3

    # if the group id does not exist, then this is a new group
    if [ -z "$TMP_GID" ]; then
        # ensure that the default gid does not already exist
        if getent group $MAPR_GID > /dev/null 2>&1 ; then
            MAPR_GID=""
        fi

        # prompt the user for a group id
        prompt "Enter '$MAPR_GROUP' gid" "$MAPR_GID"
        TMP_GID=$ANSWER

        # verify that the given group id doesn't already exist
        while getent group $TMP_GID > /dev/null 2>&1 ; do
            messenger $WARN "gid $TMP_GID already exists"
            prompt "Enter '$MAPR_GROUP' gid" "$MAPR_GID"
            TMP_GID=$ANSWER
        done

        # create the new group with the given group id
        RESULTS=$(groupadd -g $TMP_GID $MAPR_GROUP 2>&1)
        if [ $? -ne 0 ]; then
            messenger $ERROR "Unable to create group $MAPR_GROUP: $RESULTS"
        fi
        MAPR_GROUP_CREATE=$YES
    fi
    MAPR_GID=$TMP_GID

    # prompt for password
    [ -z "$MAPR_PASSWORD" -a $PROMPT_SILENT -eq $YES ] && MAPR_PASSWORD=$MAPR_USER
    prompt "Enter '$MAPR_USER' password" "$MAPR_PASSWORD" -s
    MAPR_PASSWORD=$ANSWER
    if [ $PROMPT_SILENT -eq $YES ]; then
        TMP_PASSWORD=$ANSWER
    else
        prompt "Confirm '$MAPR_USER' password" "" -s
        TMP_PASSWORD=$ANSWER
    fi
    while [ "$MAPR_PASSWORD" != "$TMP_PASSWORD" ]; do
        messenger $WARN "Password for '$MAPR_USER' does not match"
        prompt "Enter '$MAPR_USER' password" "" -s
        MAPR_PASSWORD=$ANSWER
        prompt "Confirm '$MAPR_USER' password" "" -s
        TMP_PASSWORD=$ANSWER
    done

    # create the new user with the default/given uid and gid
    # requires group read access to /etc/shadow for PAM auth
    RESULTS=$(useradd -m -u $MAPR_UID -g $MAPR_GID -G $(stat -c '%G' /etc/shadow) $MAPR_USER 2>&1)
    if [ $? -ne 0 ]; then
        messenger $ERROR "Unable to create user $MAPR_USER: $RESULTS"
    fi

    passwd $MAPR_USER > /dev/null 2>&1 << EOM
$MAPR_PASSWORD
$MAPR_PASSWORD
EOM
    MAPR_USER_CREATE=$YES
    checkSudo
}

# Install the RedHat/CentOS version of the MapR installer
fetchInstaller_redhat() {
    messenger "\nInstalling packages..."
    setenforce 0 > /dev/null 2>&1
    if [ -n "$MAPR_INSTALLER_PACKAGES" ]; then
        yum -q -y install $MAPR_INSTALLER_PACKAGES
    elif [ "$ISCONNECTED" = "$YES" ]; then
        # Create the mapr-installer repository information file
        [ "$MAPR_CORE_URL" = "$MAPR_ECO_URL" ] && subdir="/redhat"
        cat > /etc/yum.repos.d/mapr_installer.repo << EOM
[MapR_Installer]
name=MapR Installer
baseurl=$MAPR_INSTALLER_URL$subdir
gpgcheck=0
EOM
        yum -q clean expire-cache
        yum -q -y makecache fast 2>&1 | fgrep 'Not using' > /dev/null
        [ $? -eq 0 ] && yum clean all --disablerepo="*" --enablerepo=MapR_Installer
        yum --disablerepo=* --enablerepo=epel,MapR_Installer -q -y install mapr-installer-definitions mapr-installer
    else
        (cd "$HTTPD_REPO/installer/redhat"; yum -q -y --nogpgcheck localinstall mapr-installer*)
    fi
    if [ $? -ne 0 ]; then
        messenger $ERROR "Unable to install packages. Please correct the error and retry $CMD"
    fi

    # disable firewall on initial install
    if [ $USE_SYSTEMCTL -eq $YES ]; then
        systemctl disable firewalld > /dev/null 2>&1
        systemctl --no-ask-password stop firewalld > /dev/null 2>&1
        systemctl disable iptables > /dev/null 2>&1
        systemctl --no-ask-password stop iptables > /dev/null 2>&1
    else
        service iptables stop > /dev/null 2>&1 && chkconfig iptables off > /dev/null 2>&1
    fi
    success $YES
}

# Install the SuSE version of the MapR installer
fetchInstaller_suse() {
    messenger "Installing packages..."
    if [ -n "$MAPR_INSTALLER_PACKAGES" ]; then
        zypper --non-interactive -q install -n $MAPR_INSTALLER_PACKAGES
    elif [ $ISCONNECTED -eq $YES ]; then
        # Create the mapr-installer repository information file
        [ "$MAPR_CORE_URL" = "$MAPR_ECO_URL" ] && subdir="/redhat"
        cat > /etc/zypp/repos.d/mapr_installer.repo << EOM
[MapR_Installer]
name=MapR Installer
baseurl=$MAPR_INSTALLER_URL$subdir
gpgcheck=0
EOM
        zypper --non-interactive -q install -n mapr-installer-definitions mapr-installer
    else
        (cd "$HTTPD_REPO/installer/suse"; zypper --non-interactive -q install -n ./mapr-installer*)
    fi

    if [ $? -ne 0 ]; then
        messenger $ERROR "Unable to install packages. Please correct the error and retry $CMD"
    fi
    success $YES
}

# Install the Ubuntu version of the MapR installer
fetchInstaller_ubuntu() {
    messenger "Installing packages..."
    aptsources="-o Dir::Etc::SourceList=/etc/apt/sources.list.d/mapr_installer.list"
    if [ -n "$MAPR_INSTALLER_PACKAGES" ]; then
        dpkg -i $MAPR_INSTALLER_PACKAGES
        apt-get update -qq
        apt-get install -f --force-yes -y
    elif [ "$ISCONNECTED" = "$YES" ]; then
        # Create the custom source list file
        mkdir -p /etc/apt/sources.list.d
        [ "$MAPR_CORE_URL" = "$MAPR_ECO_URL" ] && subdir="/ubuntu"
        cat > /etc/apt/sources.list.d/mapr_installer.list << EOM
deb $MAPR_INSTALLER_URL$subdir binary/
EOM
        # update repo info and install mapr-installer assuming old repo struct
        apt-get -qq $aptsources update 2> /dev/null
        if [ $? -ne 0 ]; then
            cat > /etc/apt/sources.list.d/mapr_installer.list << EOM
deb $MAPR_INSTALLER_URL$subdir binary trusty
EOM
            # update repo info and install mapr-installer assuming new repo struct
            apt-get -qq $aptsources update 2> /dev/null
        fi
        apt-get $aptsources -qq install -y --force-yes mapr-installer-definitions mapr-installer
    else
        if [ -d "$HTTPD_REPO/installer/ubuntu/dists/binary/trusty" ]; then
            (cd "$HTTPD_REPO/installer/ubuntu/dists/"; dpkg -i mapr-installer*)
        else
            (cd "$HTTPD_REPO/installer/ubuntu/dists/binary"; dpkg -i mapr-installer*)
        fi
    fi
    if [ $? -ne 0 ]; then
        messenger $ERROR "Unable to install packages. Please correct the error and retry $CMD"
    fi
    success $YES
}

fetchVersions_redhat() {
    MAPR_DEF_VERSION=$(rpm -q --queryformat '%{VERSION}\n' mapr-installer-definitions | tail -n1)
    MAPR_SERVER_VERSION=$(rpm -q --queryformat '%{VERSION}\n' mapr-installer | tail -n1)
}

fetchVersions_suse() {
    MAPR_DEF_VERSION=$(rpm -q --queryformat '%{VERSION}\n' mapr-installer-definitions | tail -n1)
    MAPR_SERVER_VERSION=$(rpm -q --queryformat '%{VERSION}\n' mapr-installer | tail -n1)
}

fetchVersions_ubuntu() {
    MAPR_DEF_VERSION=$(dpkg -s mapr-installer-definitions | grep -i version | head -1 | awk '{print $NF}')
    MAPR_SERVER_VERSION=$(dpkg -s mapr-installer | grep -i version | head -1 | awk '{print $NF}')
}

createPropertiesFile() {
    if [ $ISUPDATE -eq $YES -a -f "$MAPR_PROPERTIES_FILE" ]; then
        updatePropertiesFile
    else
        mkdir -m 700 -p $MAPR_DATA_DIR
        if [ $ISCONNECTED -eq $NO ]; then
            NOINET=$YES
        fi
        cat > "$MAPR_PROPERTIES_FILE" << EOM
{
    "cluster_admin_create": ${BOOLSTR[$MAPR_USER_CREATE]},
    "cluster_admin_gid": $MAPR_GID,
    "cluster_admin_group": "$MAPR_GROUP",
    "cluster_admin_id": "$MAPR_USER",
    "cluster_admin_uid": $MAPR_UID,
    "installer_admin_group": "$MAPR_GROUP",
    "installer_admin_id": "$MAPR_USER",
    "log_rotate_cnt": 5,
    "os_version": "${OS}_${OSVER}",
    "no_internet": ${BOOLSTR[$NOINET]},
    "debug": false,
    "environment": "$MAPR_ENVIRONMENT",
    "container": ${BOOLSTR[$CONTAINER]},
    "host": "$MAPR_HOST",
    "port": $MAPR_PORT,
    "repo_core_url": "$MAPR_CORE_URL",
    "repo_eco_url": "$MAPR_ECO_URL",
    "installer_version": "$MAPR_SERVER_VERSION",
    "services_version": "$MAPR_DEF_VERSION"
}
EOM
    fi
}

reloadPropertiesFile() {
    if [ -f /etc/init.d/mapr-installer -o -f /etc/systemd/system/mapr-installer.service ]; then
        if [ $USE_SYSTEMCTL -eq $YES ]; then
            RESULTS=$(systemctl --no-ask-password reload mapr-installer)
        else
            RESULTS=$(service mapr-installer condreload)
        fi
        [ $? -ne 0 ] && messenger $ERROR "Reload failed: $RESULTS"
    fi
}

setupServiceCmd() {
    if [ $USE_SYSTEMCTL -eq $YES ]; then
        systemctl $1 $2
    elif which service > /dev/null 2>&1; then
        local cmd=chkconfig

        type sysv-rc-conf > /dev/null 2>&1 && cmd=sysv-rc-conf
        case "$2" in
        disable) $cmd $2 off ;;
        enable) $cmd $2 on ;;
        *) service $2 $1 ;;
        esac
    else
        [ $1 = "enable" -o $1 = "disable" ] && return
        /etc/init.d/$2 $1
    fi
}

setupServiceFuse() {
    [ ! -f $MAPR_FUSE_CONF ] && return
    sed -i -e "s|^source|export MAPR_TICKETFILE_LOCATION=/tmp/$MAPR_TICKET_FILE\n&|" "$MAPR_HOME/initscripts/$DOCKER_POSIX_PACKAGE"
    # FUSE start script requires flock which brings in 250mb RH OS update
    if ! which flock >/dev/null 2>&1; then
        ln -s $(which true) /usr/local/bin/flock
    fi
    setupService $DOCKER_POSIX_PACKAGE $NO
    chmod u+s "$MAPR_HOME/bin/fusermount"
    success $YES
}

setupService() {
    local enabled=$NO

    if [ $USE_SYSTEMCTL -eq $YES ]; then
        systemctl is-enabled $1 >/dev/null 2>&1 && enabled=$YES
    else
        local cmd="chkconfig"

        type sysv-rc-conf > /dev/null 2>&1 && cmd="sysv-rc-conf"
        $cmd --list 2> /dev/null | grep $1 | grep -q 3:on && enabled=$YES
    fi
    if [ ${2:-$YES} -eq $YES ]; then
        [ $enabled -eq $NO ] || setupServiceCmd enable $1 || \
            messenger $WARN "Could not enable service $1"
        # RC scripts fail if service already running
        setupServiceCmd start $1 || \
            messenger $ERROR "Could not start service $1"
        messenger "Started service $1"
    else
        [ $enabled -eq $YES ] || setupServiceCmd disable $1 || \
            messenger $WARN "Could not disable service $1"
        setupServiceCmd stop $1 >/dev/null 2>&1 && messenger "Stopped service $1"
    fi
}

setupServiceSshd() {
    if [ -z "$MAPR_DOCKER_NETWORK" -o "$MAPR_DOCKER_NETWORK" = "bridge" ]; then
        setupService $1
    else
        setupService $1 $NO
    fi
}

startServer() {
    if [ $USE_SYSTEMCTL -eq $YES ]; then
        RESULTS=$(systemctl --no-ask-password start mapr-installer)
    else
        RESULTS=$(service mapr-installer condstart)
    fi
    [ $? -ne 0 ] && messenger $ERROR "mapr-installer start failed: $RESULTS"
}

updatePropertiesFile() {
    sed -i -e "s/\"installer_version.*/\"installer_version\": \"$MAPR_SERVER_VERSION\",/" -e "s/\"services_version.*/\"services_version\": \"$MAPR_DEF_VERSION\"/" "$MAPR_PROPERTIES_FILE"
    if ! grep -q installer_admin_group "$MAPR_PROPERTIES_FILE"; then
       sed -i -e "/cluster_admin_uid/a\
\ \ \ \ \"installer_admin_group\": \"$MAPR_GROUP\","  "$MAPR_PROPERTIES_FILE"
    fi
    if ! grep -q installer_admin_id "$MAPR_PROPERTIES_FILE"; then
       sed -i -e "/installer_admin_group/a\
\ \ \ \ \"installer_admin_id\": \"$MAPR_USER\","  "$MAPR_PROPERTIES_FILE"
    fi
    if ! grep -q log_rotate_cnt "$MAPR_PROPERTIES_FILE"; then
       sed -i -e "/installer_admin_id/a\
\ \ \ \ \"log_rotate_cnt\": 5,"  "$MAPR_PROPERTIES_FILE"
    fi
    if ! grep -q os_version "$MAPR_PROPERTIES_FILE"; then
       sed -i -e "/log_rotate_cnt/a\
\ \ \ \ \"os_version\": \"${OS}_${OSVER}\"," "$MAPR_PROPERTIES_FILE"
    fi
    if ! grep -q no_internet "$MAPR_PROPERTIES_FILE"; then
       sed -i -e "/os_version/a\
\ \ \ \ \"no_internet\": ${BOOLSTR[$NOINET]}," "$MAPR_PROPERTIES_FILE"
    fi
    if ! grep -q container "$MAPR_PROPERTIES_FILE"; then
       sed -i -e "/environment/a\
\ \ \ \ \"container\": ${BOOLSTR[$CONTAINER]}," "$MAPR_PROPERTIES_FILE"
    fi
}

# this is an update if mapr-installer package exists
isUpdate() {
    local defs_installed=$NO

    case $OS in
    redhat|suse)
        rpm -qa | grep -q mapr-installer-definitions 2>&1 && defs_installed=$YES
        rpm -qa | grep -q mapr-installer-\[1-9\] 2>&1 && ISUPDATE=$YES
        ;;
    ubuntu)
        dpkg -l | grep "^ii" | grep -q mapr-installer-definitions 2>&1 && defs_installed=$YES
        dpkg -l | grep "^ii" | grep -q mapr-installer-\[1-9\] 2>&1 && ISUPDATE=$YES
        ;;
    esac
    # remove the definitions too if the installer is gone
    [ $ISUPDATE -eq $NO -a $defs_installed -eq $YES ] && remove "silent"
    if [ $ISUPDATE -eq $NO ] && $(ss -lnt "( sport = :$MAPR_PORT )" | grep -q LISTEN); then
        messenger $ERROR "Port $MAPR_PORT is in use. Correct the problem and re-run $CMD"
    fi
}

# cleanup remnants from previous install if any
cleanup() {
    rm -rf $MAPR_HOME/installer
}

# Remove all packages
remove() {
    local pkgs="mapr-installer mapr-installer-definitions"
    prologue "Remove packages"

    [ -z "$1" ] && messenger "\nUninstalling packages ($pkgs)..."
    if [ $USE_SYSTEMCTL -eq $YES ]; then
       systemctl --no-ask-password stop mapr-installer > /dev/null
    else
       service mapr-installer condstop > /dev/null
    fi
    case $OS in
    redhat)
        rm -f /etc/yum.repos.d/mapr_installer.repo
        yum -q -y remove $pkgs 2> /dev/null
        yum -q clean all 2> /dev/null
        ;;
    suse)
        rm -f etc/zypp/repos.d/mapr_installer.repo
        zypper --non-interactive -q remove $pkgs 2> /dev/null
        ;;
    ubuntu)
        rm -f /etc/apt/sources.list.d/mapr_installer.list
        apt-get purge -q -y $pkgs 2> /dev/null
        apt-get clean -q 2> /dev/null
        ;;
    esac
    [ $? -ne 0 ] && messenger $ERROR "Unable to remove packages ($pkgs)"
    cleanup
    [ -z "$1" ] && success $YES
}

container_add_repo_redhat() {
    cat > $1 << EOM
[MapR_$3]
name=MapR $3 Components
baseurl=$2
gpgcheck=1
enabled=1
protected=1
EOM
}

container_add_repo_suse() {
    cat > $1 << EOM
[MapR_$3]
name=MapR $3 Components
baseurl=$2
gpgcheck=1
enabled=1
autorefresh=1
type=rpm-md
EOM
}

container_add_repo_ubuntu() {
    cat > $1 << EOM
deb $2 mapr optional
EOM
}

container_add_repos() {
    local dir
    local ext=repo

    messenger "Configuring MapR repositories..."
    case $OS in
    redhat)
        dir=/etc/yum.repos.d
        rpm --import $GPG_KEY_URL
        ;;
    suse)
        dir=/etc/zypp/repos.d
        rpm --import $GPG_KEY_URL
        ;;
    ubuntu)
        dir=/etc/apt/sources.list.d && ext="list"
        apt-key adv --fetch-keys $GPG_KEY_URL
        ;;
    esac
    [ $? -eq 0 ] || messenger $ERROR "Could not import repo key $GPG_KEY_URL"
    container_add_repo_$OS "$dir/mapr_core.$ext" "$MAPR_CORE_URL/v$1/$OS" Core
    if [ -n "$2" ]; then
        local eco_url="$MAPR_ECO_URL/MEP/MEP-$2/$OS"
        [ $OS = "ubuntu" ] && eco_url="$eco_url binary trusty"
        container_add_repo_$OS "$dir/mapr_eco.$ext" "$eco_url" Ecosystem
    fi
    success
}

container_install_redhat() {
    yum -y install $* || messenger $ERROR "Could not install packages ($*)"
    yum clean all -q
}

container_install_suse() {
    zypper --non-interactive install -n $* || \
        messenger $ERROR "Could not install packages ($*)"
    zypper clean -a
}

container_install_ubuntu() {
    apt-get update -qq
    apt-get install -q -y $* || \
        messenger $ERROR "Could not install packages ($*)"
    apt-get clean -q
}

container_install() {
    messenger "Installing packages ($*)..."
    container_install_$OS $*
    success $YES
}

container_install_thin() {
    # choose last (most recent) file from HTML index
    formatMsg "Resolving client package url for core v$1..."
    local url="$MAPR_CORE_URL/v$1/$OS"
    [ $OS = "suse" ] && local url="$MAPR_CORE_URL/v$1/redhat"
    local file=$(wget --no-verbose --timeout=10 -qO- $url | \
        grep 'mapr-thin-client' | grep 'tar.gz<' | cut -d'"' -f 2 | tail -n1)

    [ -z "$file" ] && messenger $ERROR "Could not determine file name from $url"
    success
    url="$url/$file"
    file="/tmp/$file"
    formatMsg "Downloading and installing container client..."
    wget --no-verbose --tries=3 --waitretry=5 --timeout=10 -O $file $url || \
        messenger $ERROR "Could not wget thin client from $url"
    tar -xf $file --directory=/opt/ || messenger $ERROR "Could not untar $file"
    rm -f $file
    ln -s $MAPR_HOME/initscripts/mapr-fuse /etc/init.d
    ln -s $MAPR_HOME/initscripts/$DOCKER_POSIX_PACKAGE /etc/init.d
    success $YES
}

container_security() {
    if [ -f /etc/ssh/sshd_config ]; then
        sed -i 's/^ChallengeResponseAuthentication no$/ChallengeResponseAuthentication yes/g' /etc/ssh/sshd_config || \
            messenger $ERROR "Could not enable ChallengeResponseAuthentication"
        messenger "ChallengeResponseAuthentication enabled"
    fi
}

container_user() {
    [ -z "$MAPR_CONTAINER_USER" ] && messenger $ERROR "Must specify MAPR_CONTAINER_USER"
    MAPR_USER=$MAPR_CONTAINER_USER
    if [ "$1" = "user" ]; then
        MAPR_UID=${MAPR_CONTAINER_UID:-1000}
        MAPR_GROUP=${MAPR_CONTAINER_GROUP:-users}
        MAPR_GID=${MAPR_CONTAINER_GID:-100}
    else
        MAPR_UID=${MAPR_CONTAINER_UID:-$MAP_UID}
        MAPR_GROUP=${MAPR_CONTAINER_GROUP:-$MAP_GROUP}
        MAPR_GID=${MAPR_CONTAINER_GID:-$MAP_GID}
    fi
    createUser $1
    [ $CONTAINER_SUDO -eq $YES ] && echo "$MAPR_USER	ALL=(ALL)	NOPASSWD:ALL" >> /etc/sudoers
    container_user_profile "MAPR_CLUSTER=\"$MAPR_CLUSTER\""
    container_user_profile "MAPR_HOME=\"$MAPR_HOME\""
    container_user_profile "MAPR_CLASSPATH=\"\$($MAPR_HOME/bin/mapr classpath)\""
    [ -n "$MAPR_MOUNT_PATH" ] && container_user_profile "MAPR_MOUNT_PATH=\"$MAPR_MOUNT_PATH\""
    if [ -n "$MAPR_TICKETFILE_LOCATION" ]; then
        local ticket="MAPR_TICKETFILE_LOCATION=/tmp/$MAPR_TICKET_FILE"

        echo "$ticket" >> /etc/environment
        container_user_profile "$ticket"
	sed -i -e "s|MAPR_TICKETFILE_LOCATION=.*|MAPR_TICKETFILE_LOCATION=/tmp/$MAPR_TICKET_FILE|" "$MAPR_HOME/initscripts/$DOCKER_POSIX_PACKAGE"
    fi
    container_user_profile "PATH=\"\$PATH:\$MAPR_HOME/bin\""
}

container_user_profile() {
    local env_file=/etc/profile.d/mapr.sh

    [ ! -f $env_file ] && echo "#!/bin/bash" > $env_file
    echo "export $1" >> $env_file
}

container_usage() {
    cat << EOM
base                    finalize base image
client                  finalize client image
core                    finalize core services image
installer               finalize installer image
EOM
}

container_process() {
    [ $# -eq 0 -o "$1" = "-h" ] && container_usage
    CONTAINER_CMD=$1
    checkOS
    case "$1" in
    base)
        [ $# -ne 3 ] && usage
        fetchDependencies
        container_security
        container_add_repos $2 $3
        container_install $DOCKER_BASE_PACKAGES
        setupService mapr-warden $NO
        ;;
    client)
        local core_version=$2

        DEPENDENCY=$DEPENDENCY_BASE
        fetchDependencies
        container_security
        container_add_repos $core_version $3
        shift 3
        if [ $# -gt 0 ]; then
            container_install $*
        else
            container_install_thin $core_version
        fi
        setupServiceFuse
        ;;
    core)
        shift
        container_install $*
        ;;
    installer)
        fetchDependencies
        container_security
        testConnection
        fetchEnvironment
        fetchInstaller_$OS
        fetchVersions_$OS
        createPropertiesFile
        ;;
    *) usage ;;
    esac
}

docker_dockerfile() {
    local dockerfile_file="$1/$DOCKER_FILE"

    cat > "$dockerfile_file" << EOM
FROM $DOCKER_FROM

ENV container docker

EOM
    case $CONTAINER_OS in
    centos6) docker_dockerfile_redhat6 "$dockerfile_file" ;;
    centos7) docker_dockerfile_redhat7 "$dockerfile_file" ;;
    ubuntu14|ubuntu16) docker_dockerfile_ubuntu "$dockerfile_file" ;;
    suse) docker_dockerfile_suse "$dockerfile_file" ;;
    *) messenger $ERROR "Invalid container OS $CONTAINER_OS" ;;
    esac
    if [ -n "$2" ]; then
        cat >> "$dockerfile_file" << EOM

LABEL mapr.os=$CONTAINER_OS mapr.version=$2 mapr.mep_version=$3
EOM
    else
        cat >> "$dockerfile_file" << EOM

LABEL mapr.os=$CONTAINER_OS
EOM
    fi
    cat >> "$dockerfile_file" << EOM

COPY tmp/mapr-setup.sh $CONTAINER_SCRIPT_DIR/

EOM
}

docker_dockerfile_redhat_common() {
    cat >> "$1" << EOM
RUN yum -y upgrade && yum install -y $DEPENDENCY_INIT && yum -q clean all
EOM
}

docker_dockerfile_redhat6() {
    docker_dockerfile_redhat_common $1
}

docker_dockerfile_redhat7() {
    docker_dockerfile_redhat_common $1
    cat >> "$1" << EOM
VOLUME [ "/sys/fs/cgroup" ]

# enable systemd support
RUN (cd /lib/systemd/system/sysinit.target.wants/ || return; for i in *; do [ \$i == systemd-tmpfiles-setup.service ] || rm -f \$i; done); \
rm -f /lib/systemd/system/multi-user.target.wants/*; \
rm -f /etc/systemd/system/*.wants/*; \
rm -f /lib/systemd/system/local-fs.target.wants/*; \
rm -f /lib/systemd/system/sockets.target.wants/*udev*; \
rm -f /lib/systemd/system/sockets.target.wants/*initctl*; \
rm -f /lib/systemd/system/basic.target.wants/*; \
rm -f /lib/systemd/system/anaconda.target.wants/*;
EOM
}

docker_dockerfile_suse() {
    cat >> "$1" << EOM
VOLUME [ "/sys/fs/cgroup" ]

RUN zypper --non-interactive up && zypper --non-interactive install -n $DEPENDENCY_INIT && zypper clean -a
EOM
}

docker_dockerfile_ubuntu() {
    cat >> "$1" << EOM
RUN apt-get update -qq && apt-get upgrade -q -y && apt-get install -q -y $DEPENDENCY_INIT && apt-get autoremove -y && apt-get clean -q
EOM
}

docker_init() {
    local docker_dir="$DOCKER_BASE_DIR"
    local dockerfile_file="$docker_dir/$DOCKER_FILE"
    local docker_tmp_dir="$docker_dir/tmp"
    local docker_base_file="$docker_tmp_dir/tagname"

    prologue "Initialize Docker configuration"
    docker_init_dirs $docker_dir
    [ $? -eq $NO ] && return
    docker_prompt_os
    prompt "MapR core version" "$MAPR_VERSION_CORE"
    local mapr_version=$ANSWER
    prompt "MEP version" $MAPR_VERSION_MEP
    local mep_version=$ANSWER
    prompt "MapR base image tag name" "maprtech/server:${mapr_version}_${mep_version}_$CONTAINER_OS"
    local image_tag=$ANSWER
    docker_dockerfile $docker_dir $mapr_version $mep_version
    cat >> $dockerfile_file << EOM
RUN $CONTAINER_SCRIPT -r $MAPR_CORE_URL -f container base $mapr_version $mep_version
EOM
    echo "$image_tag" > $docker_base_file
    messenger $BOLD "\nCustomize $dockerfile_file and then run '$CMD docker base'"
}

docker_build_finish() {
    cat >> "$1/$DOCKER_FILE" << EOM

ENTRYPOINT ["$CONTAINER_SCRIPT", "docker"]
CMD ["start"]
EOM
    docker_create_run $1 $2 $3 $4
    docker build --force-rm -t $3 $1 || messenger $ERROR "Unable to build $3"
}

docker_check_environment() {
    [ $USE_SYSTEMCTL -eq $YES ] && sleep 5
    # MAPR_SECURITY, MAPR_OT_HOSTS, MAPR_HS_HOST optional
    [ -z "$MAPR_CLUSTER" ] && messenger $ERROR "MAPR_CLUSTER must be set"
    [ -z "$MAPR_DISKS" ] && messenger $ERROR "MAPR_DISKS must be set"
    if [ -z "$MAPR_CLDB_HOSTS" ]; then
        messenger "MAPR_CLDB_HOSTS not set - using $HOST"
        MAPR_CLDB_HOSTS=$HOST
    fi
    if [ -z "$MAPR_ZK_HOSTS" ]; then
        messenger "MAPR_ZK_HOSTS not set - using $HOST"
        MAPR_ZK_HOSTS=$HOST
    fi
}

docker_create_run() {
    local create_dockerrun_file=$YES
    local docker_args docker_network docker_security

    if [ -d "$1" -a -f "$2" ]; then
        prompt_boolean "$2 exists - overwrite?" n
        create_dockerrun_file=$ANSWER
    fi
    [ $create_dockerrun_file -eq $NO ] && return
    while [ -z "$docker_network" ]; do
        prompt "Container network mode (bridge|host)" "bridge"
        case $ANSWER in
        bridge|host) docker_network=$ANSWER ;;
        *) messenger "Invalid network mode: $ANSWER" ;;
        esac
    done
    while [ -z "$user_memory" ]; do
        prompt "Container memory: specify host XX[kmg] or 0 for no limit" 0

        local mem_number=$(echo "$ANSWER" | grep -o -E '[0-9]+')
        local mem_char=$(echo "$ANSWER" | grep -o -E '[kmgKMG]')

        [ ${#mem_number} -eq 0 ] && continue
        if [ ${#mem_char} -gt 1 ]; then
            messenger $WARN "Invalid memory allocation: $mem_char must be [kmg]"
            continue
        fi
        if [ ${#mem_char} -eq 0 -a $mem_number != "0" ]; then
            messenger $WARN "Memory allocation unit must be specified"
            continue
        fi
        local user_memory=$ANSWER
    done
    cat > $2 << EOM
#!/bin/sh

# The environment variables in this file are for example only. These variables
# must be altered to match your docker container deployment needs

EOM
    case "$4" in
    client)
        docker_security="--cap-add SYS_ADMIN --cap-add SYS_RESOURCE \
            --device /dev/fuse"
        cat >> "$2" << EOM
MAPR_CLUSTER=$MAPR_CLUSTER
MAPR_CLDB_HOSTS=

# MapR POSIX client mount path to enable direct MapR-FS access
# MAPR_MOUNT_PATH=/mapr

# MapR secure cluster ticket file path
MAPR_TICKETFILE_LOCATION=

# MapR client user / group
MAPR_CONTAINER_USER=\$(id -u -n)
MAPR_CONTAINER_UID=\$(id -u)
MAPR_CONTAINER_GROUP=$([ $(uname -s) = "Darwin" ] && echo users || echo '$(id -g -n)')
MAPR_CONTAINER_GID=$([ $(uname -s) = "Darwin" ] && echo 100 || echo '$(id -g)')
MAPR_PASSWORD=
EOM
        ;;
    installer)
        cat >> "$2" << EOM
# MapR installer admin user / group
MAPR_CONTAINER_USER=$MAPR_USER
MAPR_CONTAINER_UID=$MAPR_UID
MAPR_CONTAINER_GROUP=$MAPR_GROUP
MAPR_CONTAINER_GID=$MAPR_GID
MAPR_PASSWORD=
EOM
        ;;
    server)
        docker_args="--ipc=host"
        docker_security="--privileged --device \$MAPR_DISKS"
        cat >> "$2" << EOM
MAPR_CLUSTER=$MAPR_CLUSTER
MAPR_DISKS=/dev/sd?,...
MAPR_LICENSE_MODULES=DATABASE,HADOOP,STREAMS
MAPR_CLDB_HOSTS=
MAPR_ZK_HOSTS=
MAPR_HS_HOST=
MAPR_OT_HOSTS=

# MapR cluster admin user / group
MAPR_CONTAINER_USER=$MAPR_USER
MAPR_CONTAINER_UID=$MAPR_UID
MAPR_CONTAINER_GROUP=$MAPR_GROUP
MAPR_CONTAINER_GID=$MAPR_GID
MAPR_PASSWORD=

# MapR cluster security: [disabled|enabled|master]
MAPR_SECURITY=disabled
EOM
        ;;
    esac
    cat >> "$2" << EOM

# Container memory: specify host XX[kmg] or 0 for no limit. Ex: 8192m, 12g
MAPR_MEMORY=$user_memory

# Container timezone: filename from /usr/share/zoneinfo
MAPR_TZ=\${TZ:-"$MAPR_TZ"}

# Container network mode: "host" causes the container's sshd service to conflict
# with the host's sshd port (22) and so it will not be enabled in that case
MAPR_DOCKER_NETWORK=$docker_network

# Container security: --privileged or --cap-add SYS_ADMIN /dev/<device>
MAPR_DOCKER_SECURITY="$docker_security"

# Other Docker run args:
MAPR_DOCKER_ARGS="$docker_args"

### do not edit below this line ###
MAPR_DOCKER_ARGS="\$MAPR_DOCKER_SECURITY \\
  --memory \$MAPR_MEMORY \\
  --network=\$MAPR_DOCKER_NETWORK \\
  -e MAPR_DISKS=\$MAPR_DISKS \\
  -e MAPR_CLUSTER=\$MAPR_CLUSTER \\
  -e MAPR_LICENSE_MODULES=\$MAPR_LICENSE_MODULES \\
  -e MAPR_MEMORY=\$MAPR_MEMORY \\
  -e MAPR_MOUNT_PATH=\$MAPR_MOUNT_PATH \\
  -e MAPR_SECURITY=\$MAPR_SECURITY \\
  -e MAPR_TZ=\$MAPR_TZ \\
  -e MAPR_USER=\$MAPR_USER \\
  -e MAPR_CONTAINER_USER=\$MAPR_CONTAINER_USER \\
  -e MAPR_CONTAINER_UID=\$MAPR_CONTAINER_UID \\
  -e MAPR_CONTAINER_GROUP=\$MAPR_CONTAINER_GROUP \\
  -e MAPR_CONTAINER_GID=\$MAPR_CONTAINER_GID \\
  -e MAPR_PASSWORD=\$MAPR_PASSWORD \\
  -e MAPR_CLDB_HOSTS=\$MAPR_CLDB_HOSTS \\
  -e MAPR_HS_HOST=\$MAPR_HS_HOST \\
  -e MAPR_OT_HOSTS=\$MAPR_OT_HOSTS \\
  -e MAPR_ZK_HOSTS=\$MAPR_ZK_HOSTS \\
  \$MAPR_DOCKER_ARGS"

[ -f "\$MAPR_TICKETFILE_LOCATION" ] && MAPR_DOCKER_ARGS="\$MAPR_DOCKER_ARGS \\
  -e MAPR_TICKETFILE_LOCATION=/tmp/$MAPR_TICKET_FILE \\
  -v \$MAPR_TICKETFILE_LOCATION:/tmp/$MAPR_TICKET_FILE:ro"
[ -d /sys/fs/cgroup ] && MAPR_DOCKER_ARGS="\$MAPR_DOCKER_ARGS -v /sys/fs/cgroup:/sys/fs/cgroup:ro"

docker run -it \$MAPR_DOCKER_ARGS $3 \$*
EOM
    chmod +x $2
}

# keep image running to prevent container shutdown
docker_keep_alive() {
    if [ -z "$1" ]; then
        exec tail -f /dev/null
    else
        exec $*
    fi
}

docker_prologue() {
    prologue "Building MapR Docker sandbox containers are for development and test purposes only!
        MapR does not support production containers. DO YOU AGREE"
    [ $ANSWER = $YES ] || exit 1
    prompt_boolean "$1"
}

docker_prompt_from() {
    CONTAINER_OS=$1
    prompt "Docker FROM base image name:tag" $2
    DOCKER_FROM=$ANSWER
}

docker_prompt_os() {
    case $OS in
    darwin) CONTAINER_OS=centos6 ;;
    redhat) CONTAINER_OS="centos$OSVER_MAJ" ;;
    ubuntu) CONTAINER_OS="ubuntu$OSVER_MAJ" ;;
    *) CONTAINER_OS=$OS ;;
    esac
    unset ANSWER
    while [ -z "$ANSWER" ]; do
        prompt "Image OS class (centos6, centos7, suse, ubuntu14, ubuntu16)" \
            $CONTAINER_OS
        case $ANSWER in
        centos6)
            DEPENDENCY_INIT="$DEPENDENCY_BASE_RPM $OPENJDK_RPM_8"
            docker_prompt_from $ANSWER "centos:centos6"
            ;;
        centos7)
            DEPENDENCY_INIT="$DEPENDENCY_BASE_RPM $OPENJDK_RPM_8"
            docker_prompt_from $ANSWER "centos:centos7"
            ;;
        suse)
            DEPENDENCY_INIT="$DEPENDENCY_BASE_SUSE $OPENJDK_SUSE_8"
            docker_prompt_from $ANSWER "opensuse:13.2"
            ;;
        ubuntu14)
            DEPENDENCY_INIT="$DEPENDENCY_BASE_DEB $OPENJDK_DEB_7"
            docker_prompt_from $ANSWER "ubuntu:14.04"
            ;;
        ubuntu16)
            DEPENDENCY_INIT="$DEPENDENCY_BASE_DEB $OPENJDK_DEB_8"
            docker_prompt_from $ANSWER "ubuntu:16.04"
            ;;
        *) unset ANSWER ;;
        esac
    done
}

docker_allocate() {
    messenger $INFO "Allocating data file $2 ($3)..."
    if [ $OS = "darwin" ]; then
        mkfile -n $3 $2 && success
    else
        fallocate -l $3 $2 && success
    fi
}

docker_base() {
    local create_dockerbuild_file=$YES
    local docker_dir="$DOCKER_BASE_DIR"
    local dockerbuild_file="$docker_dir/docker_build_base.sh"
    local docker_tmp_dir="$docker_dir/tmp"
    local docker_base_file="$docker_tmp_dir/tagname"

    docker_prologue "Build MapR base image"
    mkdir -p -m 770 $docker_dir
    if [ -f $dockerbuild_file ]; then
        prompt_boolean "$dockerbuild_file exists - overwrite?"
        create_dockerbuild_file=$ANSWER
    fi
    if [ $create_dockerbuild_file -eq $YES ]; then
        local tag_name="mapr:base"

        [ -f $docker_base_file ] && tag_name=$(cat $docker_base_file)
        prompt "MapR base image tag name" $tag_name
        cat > $dockerbuild_file << EOM
#!/bin/sh
docker build --force-rm -t $ANSWER $docker_dir
EOM
        messenger "\nBase image build script written to $dockerbuild_file. Executing..."
        chmod +x $dockerbuild_file
    fi
    $dockerbuild_file
    if [ $? -eq 0 ]; then
        success
        messenger $BOLD "MapR base image $tag_name now built. Run '$CMD docker core' to build server images"
    else
        messenger $ERROR "Unable to create base image"
    fi
}

docker_client() {
    local docker_dir="$DOCKER_CLIENT_DIR"
    local docker_file="$docker_dir/$DOCKER_FILE"
    local dockerrun_file="$docker_dir/mapr-docker-client.sh"

    prologue "Build MapR client image"
    docker_init_dirs $docker_dir
    [ $? -eq $NO ] && return
    docker_prompt_os
    prompt "MapR core version" $MAPR_VERSION_CORE
    local mapr_version=$ANSWER
    prompt "MapR MEP version" $MAPR_VERSION_MEP
    local mep_version=$ANSWER
    prompt_boolean "Install Hadoop YARN client" "y"
    local hadoop_client=$ANSWER
    if [ $hadoop_client -eq $YES ]; then
        TAG=_yarn
        PACKAGES="$DOCKER_CLIENT_PACKAGES"
        prompt_package "POSIX client (FUSE)" $DOCKER_POSIX_PACKAGE fuse y
    fi
    local image_tag="maprtech/pacc:${mapr_version}_${mep_version}_${CONTAINER_OS}$TAG"
    prompt "MapR client image tag name" $image_tag
    image_tag=$ANSWER
    docker_dockerfile $docker_dir $mapr_version $mep_version
    cat >> "$docker_file" << EOM
RUN $CONTAINER_SCRIPT -r $MAPR_CORE_URL container client $mapr_version $mep_version $PACKAGES
EOM
    docker_build_finish $docker_dir $dockerrun_file "$image_tag" client
    messenger $BOLD "\nEdit '$dockerrun_file' to set MAPR_CLUSTER and MAPR_CLDB_HOSTS and then execute it to start the container"
}

docker_core() {
    local base_tag="mapr:base"
    local image_tag="mapr:core"
    local create_dockerbuild_file=$YES
    local create_dockerfile=$YES
    local docker_base_dir="$DOCKER_BASE_DIR"
    local docker_core_dir="$DOCKER_CORE_DIR"
    local docker_tmp_dir="$docker_base_dir/tmp"
    local docker_base_file="$docker_tmp_dir/tagname"
    local dockerfile_file="$docker_core_dir/$DOCKER_FILE"
    local dockerbuild_file="$docker_core_dir/mapr-build-core.sh"
    local dockerrun_file="$docker_core_dir/mapr-docker.sh"

    docker_prologue "Build MapR core image"
    docker_init_dirs $docker_core_dir
    create_dockerfile=$?
    if [ -d $docker_core_dir ]; then
        if [ -f $dockerbuild_file ]; then
            prompt_boolean "$dockerbuild_file exists - overwrite?"
            create_dockerbuild_file=$ANSWER
        fi
    else
        mkdir -p -m 770 $docker_core_dir
    fi
    if [ $create_dockerfile -eq $YES ]; then
        [ -f $docker_base_file ] && base_tag=$(cat $docker_base_file)
        CONTAINER_PORTS="$SSHD_PORT 5660"
        unset PACKAGES
        unset TAG
        prompt "MapR base image tag name" $base_tag
        base_tag=$ANSWER
        prompt_package "Zookeeper" mapr-zookeeper zk y 5181 2888 3888
        prompt_package "MapR-FS CLDB" mapr-cldb cldb y 7222 7221
        prompt_package "MapR-FS Gateway" mapr-gateway gw n 7660
        prompt_package "NFS Server" mapr-nfs nfs n 111 2049 9997 9998
        prompt_package "UI Administration Server" mapr-webserver mcs y 8443
        prompt_package "YARN Resource Manager" mapr-resourcemanager rm y 8032 8033 8088 8090
        prompt_package "YARN Node Manager" mapr-nodemanager nm y 8041 8042 8044
        prompt_package "YARN History Server" mapr-historyserver hs n 10020 19888 19890
        TAG="${base_tag}_${TAG}"

        cat > $dockerfile_file << EOM
FROM $base_tag

EXPOSE $CONTAINER_PORTS

# create default MapR admin user and group
RUN groupadd -g $MAPR_GID $MAPR_GROUP && \
useradd -m -u $MAPR_UID -g $MAPR_GID -G \$(stat -c '%G' /etc/shadow) $MAPR_USER

COPY tmp/mapr-setup.sh $CONTAINER_SCRIPT_DIR/
RUN $CONTAINER_SCRIPT -f container core $PACKAGES

ENTRYPOINT ["$CONTAINER_SCRIPT", "-f", "-y", "docker"]
CMD ["start"]
EOM
    fi
    if [ $create_dockerbuild_file -eq $YES ]; then
        prompt "MapR core image tag name" $TAG
        image_tag="$ANSWER"
        cat > $dockerbuild_file << EOM
#!/bin/sh

docker build --force-rm -t $image_tag $docker_core_dir
EOM
        chmod +x $dockerbuild_file
    fi
    docker_create_run $docker_core_dir $dockerrun_file $image_tag server
    $dockerbuild_file
    if [ $? -eq 0 ]; then
        success
        messenger $BOLD "\nMapR core image $image_tag built successfully. If this image will be shared across nodes, publish it to an appropriate repository"
    else
        messenger $ERROR "Unable to create core image"
    fi
}

docker_installer() {
    local docker_dir="$DOCKER_INSTALLER_DIR"
    local docker_file="$docker_dir/$DOCKER_FILE"
    local dockerrun_file="$docker_dir/mapr-docker-installer.sh"

    prologue "Build MapR UI Installer image"
    docker_init_dirs $docker_dir
    [ $? -eq $NO ] && return
    docker_prompt_os
    docker_dockerfile $docker_dir
    cat >> "$docker_file" << EOM
EXPOSE $SSHD_PORT 9443

RUN $CONTAINER_SCRIPT -r $MAPR_CORE_URL container installer

EOM
    docker_build_finish $docker_dir $dockerrun_file "mapr:installer" installer
    messenger $BOLD "\nExecute '$dockerrun_file' to start the container and complete installation"
}

docker_configure_client() {
    local args

    if [ $CONTAINER_INITIALIZED -eq $YES ]; then
        messenger "Container already initialized"
        return
    fi
    [ -z "$MAPR_CLUSTER" ] && messenger $ERROR "MAPR_CLUSTER must be set"
    [ -z "$MAPR_CLDB_HOSTS" ] && messenger $ERROR "MAPR_CLDB_HOSTS must be set"
    . $MAPR_HOME/conf/env.sh
    args="$args -c -C $MAPR_CLDB_HOSTS -N $MAPR_CLUSTER"
    [ -n "$MAPR_TICKETFILE_LOCATION" ] && args="$args -secure"
    [ $VERBOSE -eq $YES ] && args="$args -v"
    messenger "Configuring MapR client ($args)..."
    docker_configure_output $args
    chown -R $MAPR_USER:$MAPR_GROUP "$MAPR_HOME"
}

docker_configure_output() {
    if $CONTAINER_CONFIGURE_SCRIPT $* 2>&1; then
        CONTAINER_INITIALIZED=$YES
        success $YES
    else
        rm -f $CONTAINER_CLUSTER_CONF
        messenger $ERROR "CONTAINER_CONFIGURE_SCRIPT failed with code $1"
    fi
}

docker_configure_server() {
    local LICENSE_MODULES="${MAPR_LICENSE_MODULES:-DATABASE,HADOOP}"
    local CLDB_HOSTS="${MAPR_CLDB_HOSTS:-$HOST}"
    local ZK_HOSTS="${MAPR_ZK_HOSTS:-$HOST}"
    local args

    if [ -f "$CONTAINER_CLUSTER_CONF" ]; then
        messenger "Re-configuring MapR services ($args)..."
        docker_configure_output -R $args
        return
    fi
    . $MAPR_HOME/conf/env.sh
    [ -n "$MAPR_HS_HOST" ] && args="$args -HS $MAPR_HS_HOST"
    [ -n "$MAPR_OT_HOSTS" ] && args="$args -OT $MAPR_OT_HOSTS"
    if [ -n "$CLDB_HOSTS" ]; then
        args="$args -f -no-autostart -on-prompt-cont y -N $MAPR_CLUSTER -C $CLDB_HOSTS -Z $ZK_HOSTS -u $MAPR_USER -g $MAPR_GROUP"
        if [ "$MAPR_SECURITY" = "master" ]; then
            args="$args -secure -genkeys"
        elif [ "$MAPR_SECURITY" = "enabled" ]; then
            args="$args -secure"
        else
            args="$args -unsecure"
        fi
        [ -n "${LICENSE_MODULES##*DATABASE*}" -a -n "${LICENSE_MODULES##*STREAMS*}" ] && args="$args -noDB"
    else
        args="-R $args"
    fi
    [ $VERBOSE -eq $YES ] && args="$args -v"
    messenger "Configuring MapR services ($args)..."
    docker_configure_output $args
}

docker_disk_setup() {
    local DISK_FILE="$MAPR_HOME/conf/disks.txt"
    local DISKSETUP="$MAPR_HOME/server/disksetup"
    local DISKTAB_FILE="$MAPR_HOME/conf/disktab"
    local FORCE_FORMAT=${FORCE_FORMAT:-$YES}
    local STRIPE_WIDTH=${STRIPE_WIDTH:-3}

    messenger "Configuring disks..."
    if [ -f "$DISKTAB_FILE" ]; then
        messenger "MapR disktab file $DISKTAB_FILE already exists. Skipping disk setup"
        return
    fi
    IFS=',' read -r -a disk_list_array <<< "$MAPR_DISKS"
    for disk in "${disk_list_array[@]}"; do
        echo "$disk" >> $DISK_FILE
    done
    sed -i -e 's/mapr/#mapr/g' /etc/security/limits.conf
    sed -i -e 's/AddUdevRules(list(gdevices));/#AddUdevRules(list(gdevices));/g' $MAPR_HOME/server/disksetup
    [ -x "$DISKSETUP" ] || messenger $ERROR "MapR disksetup utility $DISKSETUP not found"
    [ $FORCE_FORMAT -eq $YES ] && ARGS="$ARGS -F"
    [ $STRIPE_WIDTH -eq 0 ] && ARGS="$ARGS -M" || ARGS="$ARGS -W $STRIPE_WIDTH"
    $DISKSETUP $ARGS $DISK_FILE
    if [ $? -eq 0 ]; then
        success $NO "Local disks formatted for MapR-FS"
    else
        rc=$?
        rm -f $DISK_FILE $DISKTAB_FILE
        messenger $ERROR "$DISKSETUP failed with error code $rc"
    fi
}

docker_init_dirs() {
    local create_dockerfile=$YES
    local dockerfile_file="$1/$DOCKER_FILE"
    local docker_tmp_dir="$1/tmp"

    if [ -d $1 ]; then
        if [ -f $dockerfile_file ]; then
            prompt_boolean "$dockerfile_file exists - overwrite?" n
            create_dockerfile=$ANSWER
        fi
    else
        mkdir -p -m 770 $1
    fi
    mkdir -p -m 770 $docker_tmp_dir
    cp -f $INSTALLER $docker_tmp_dir
    return $create_dockerfile
}

docker_post_redhat() {
    setupService ntpd
    setupService rpcbind
    if [ $OSVER_MAJ -ge 7 ]; then
        setupService nfs-lock
    else
        setupService nfslock
    fi
    setupServiceSshd $SSHD
}

docker_post_suse() {
    if [ $OSVER_MAJ -ge 12 ]; then
        setupService ntpd
    else
        setupService ntp
    fi
    setupService rpcbind
    setupServiceSshd $SSHD
}

docker_post_ubuntu() {
    setupService ntp
    setupServiceSshd $SSHD
}

docker_post() {
    # TODO need to un hardcode this and take as environment variable
    MAPR_PASSWORD="mapr"
    echo "$MAPR_USER:$MAPR_PASSWORD" | chpasswd

    docker_post_$OS
}

docker_set_memory() {
    local memfile="$MAPR_HOME/conf/container_meminfo"
    local mem_number=$(echo "$MAPR_MEMORY" | grep -o -E '[0-9]+')
    local mem_char=$(echo "$MAPR_MEMORY" | grep -o -E '[kmgKMG]')

    messenger "Seting MapR container memory limits..."
    [ ${#mem_number} -eq 0 ] && messenger $ERROR "Empty memory allocation"
    [ ${#mem_char} -gt 1 ] && messenger $ERROR "Invalid memory allocation: $mem_char must be [kmg]"
    [ $mem_number == "0" ] && return
    case "$mem_char" in
    g|G) local mem_total=$(($mem_number * 1024 * 1024)) ;;
    m|M) local mem_total=$(($mem_number * 1024)) ;;
    k|K) local mem_total=$(($mem_number)) ;;
    esac
    cp -f -v /proc/meminfo $memfile
    sed -i "s!/proc/meminfo!${memfile}!" "$MAPR_HOME/server/initscripts-common.sh" || \
        messenger $ERROR "Could not edit initscripts-common.sh"
    sed -i "/^MemTotal/ s/^.*$/MemTotal:     ${mem_total} kB/" "$memfile" || \
        messenger $ERROR "Could not edit meminfo MemTotal"
    sed -i "/^MemFree/ s/^.*$/MemFree:     ${mem_total} kB/" "$memfile" || \
        messenger $ERROR "Could not edit meminfo MemFree"
    sed -i "/^MemAvailable/ s/^.*$/MemAvailable:     ${mem_total} kB/" "$memfile" || \
        messenger $ERROR "Could not edit meminfo MemAvailable"
    success $YES
}

docker_set_timezone() {
    local file=/usr/share/zoneinfo/$MAPR_TZ

    [ ! -f $file ] && messenger $ERROR "Invalid MAPR_TZ timezone ($MAPR_TZ)"
    ln -f -s "$file" /etc/localtime
}

docker_start() {
    # allow non-root users to log into the system
    rm -f /run/nologin
    if [ $USE_SYSTEMCTL -eq $YES -a -x "/usr/sbin/init" ]; then
        $CONTAINER_SCRIPT docker $* &
        exec /usr/sbin/init
    else
        docker_process $*
    fi
}

docker_start_fuse() {
    if [ -n "$MAPR_MOUNT_PATH" -a -f $MAPR_HOME"/conf/fuse.conf" ]; then
        sed -i "s|^fuse.mount.point.*$|fuse.mount.point=$MAPR_MOUNT_PATH|g" $MAPR_FUSE_CONF || \
            messenger $ERROR "Could not set FUSE mount path"
        mkdir -p -m 755 "${MAPR_MOUNT_PATH}"
        docker_start_services $DOCKER_POSIX_PACKAGE
    fi
}

docker_start_services() {
    messenger "Starting services ($*)..."
    [ $USE_SYSTEMCTL -eq $YES ] && systemctl daemon-reload
    for service in $*; do
        setupService $service
    done
    success
}

docker_usage() {
    cat << EOM
allocate diskfile size  allocate disk file for MapR-FS
base                    create base image
client                  create client image
core                    create core services image
init                    create iniitial $DOCKER_FILE
installer               create installer image
bash|sh                 start shell within image
start                   start image
EOM
}

BEAR_configure_tsdb() {
    if [ -f /home/CONFIG_OK ]
    then
        messenger "OpenTSDB Already configured."
    else
        # Configure OpenTSDB
        rm -rf /etc/opentsdb/opentsdb.conf
        cp $OPENTSDB_CONFIG_FILE_PATH /etc/opentsdb/opentsdb.conf
        messenger "OpenTSDB Configuration OK"
        
        # Configure Kafka2OpenTSDB
        rm -rf /home/Kafka2OpenTSDB/conf/application.properties
        cp $KAFKA2OPENTSDB_CONFIG_FILE_PATH /home/Kafka2OpenTSDB/conf/application.properties
        messenger "Kafka2OpenTSDB Configuration OK"

        touch /home/CONFIG_OK
    fi
}

BEAR_start_opentsdb() {
    sh tsdb tsd > /dev/null 2>&1 &
    messenger "OpenTSDB started"
}


BEAR_start_kafka2opentsdb() {
    chown mapr /etc/opentsdb/opentsdb.conf
    chmod 755 /etc/opentsdb/opentsdb.conf
    chown -R mapr /home/Kafka2OpenTSDB
    chmod 755 /home/Kafka2OpenTSDB
    su mapr -c "cd /home/Kafka2OpenTSDB/ && nohup java -classpath lib/ -jar kafka-opentsdb-basari-1.0.jar &"   
    messenger "Kafka2OpenTSDB started"
}

docker_process() {
    [ $# -eq 0 -o "$1" = "-h" ] && docker_usage
    checkOS
    [ "$1" = "-f" ] && shift && PROMPT_FORCE=$YES
    [ "$1" = "-y" ] && shift && PROMPT_SILENT=$YES
    DOCKER_CMD=$1
    shift
    case "$DOCKER_CMD" in
    allocate) docker_allocate ;;
    base) docker_base ;;
    client) docker_client ;;
    core) docker_core ;;
    init) docker_init ;;
    installer) docker_installer ;;
    post_client)
        docker_set_timezone
        docker_configure_client
        docker_start_fuse
        if [ $MAPR_USER = root ]; then
            [ $# -ne 0 ] && local cmd=-c
            docker_keep_alive $SHELL -l $cmd $*
        else
            BEAR_configure_tsdb
            if [ $START_OPENTSDB -eq 1 ]
            then
                BEAR_start_opentsdb
            fi

            if [ $START_KAFKA2OPENTSDB -eq 1 ]
            then
                BEAR_start_kafka2opentsdb
            fi 
            docker_keep_alive sudo -i -n -u $MAPR_USER $*
        fi
        ;;
    post_installer)
        chown -R $MAPR_USER:$MAPR_GROUP "$MAPR_HOME/installer"
        docker_set_timezone
        docker_start_services $SSHD mapr-installer
        epilogue
        docker_keep_alive
        ;;
    post_server)
        docker_set_timezone
        docker_check_environment
        container_user
        docker_set_memory
        docker_post
        docker_configure_server
        docker_disk_setup
        docker_start_services $SSHD mapr-zookeeper mapr-warden
        docker_keep_alive
        ;;
    bash|csh|ksh|sh|zsh) docker_keep_alive $* ;;
    start)
        # enable user auto-creation during initial run
        [ -n "$MAPR_CONTAINER_USER" ] && PROMPT_SILENT=$YES
        if [ -f "$MAPR_HOME/conf/warden.conf" ]; then
            docker_start post_server $*
        elif [ -d "$MAPR_HOME/installer/bin" ]; then
            setPort
            container_user
            fetchVersions_$OS
            updatePropertiesFile
            reloadPropertiesFile
            docker_start post_installer $*
        else
            USE_SYSTEMCTL=$NO
            [ $CONTAINER_INITIALIZED -eq $NO ] && container_user user
            docker_start post_client $*
        fi
        ;;
    *) docker_usage ;;
    esac
}

##
## MAIN
##
export TERM=${TERM:-ansi}
tput init

# Parse command line and set globals
while [ $# -gt 0 -a -z "${1##-*}" ]; do
    case "$1" in
    -a|--archive)
        [ $# -gt 1 ] || usage
        if [ $# -gt 3 ]; then
            if [ -n "${2##-*}" -a -n "${3##-*}" -a -n "${4##-*}" ]; then
                MAPR_ARCHIVE="$2 $3 $4"
                shift 3
            fi
        else
            MAPR_ARCHIVE=$2
            shift
        fi
        TEST_CONNECT=$NO
        ;;
    -f|--force) PROMPT_FORCE=$YES ;;
    -h|-\?|--help) usage 0 ;;
    -i|--install)
        [ $# -gt 2 ] || usage
        MAPR_INSTALLER_PACKAGES="$2 $3"
        shift 2
        ;;
    -n|--noinet) NOINET=$YES ;;
    -p|--port)
        [ $# -gt 1 ] || usage
        tport=$(echo $2| cut -s -d: -f2)
        if [ -z "$tport" ]; then
            tport=$2
            thost=$(echo $MAPR_HOST | cut -d: -f1)
        else
            thost=$(echo $2| cut -s -d: -f1)
        fi
        case $tport in
        ''|*[!0-9]*)
            messenger $WARN "Port must be numeric: $port"
            usage
            ;;
        esac
        MAPR_HOST=$thost:$tport
        shift
        ;;
    -r|--repo)
        [ $# -gt 1 ] || usage
        MAPR_INSTALLER_URL=$2/installer
        MAPR_CORE_URL=$2
        MAPR_ECO_URL=$2
        shift
        ;;
    -v|--verbose) VERBOSE=$YES ;;
    -y|--yes) PROMPT_SILENT=$YES ;;
    *) usage ;;
    esac
    shift
done

# Set traps so the installation script always exits cleanly
# Ubuntu seems to behave much better when we catch the signals. Even though
# sub-commands do get intterrupted, it seems they handle it better than when we
# ignore the signals and the sub-command receive it anyway - seems like a bug..
if [ -f /etc/lsb-release ] && grep -q DISTRIB_ID=Ubuntu /etc/lsb-release; then
    trap catchTrap SIGHUP SIGINT SIGQUIT SIGUSR1 SIGTERM
else
    trap '' SIGHUP SIGINT SIGQUIT SIGUSR1 SIGTERM
fi

[ "$1" != "docker" -a $ID -ne 0 ] && messenger $ERROR "$CMD must be run as 'root'"
[ -z "$HOST" ] && messenger $ERROR "Unable to determine hostname"

case "$1" in
container)
    shift
    container_process $*
    ;;
docker)
    shift
    docker_process $*
    ;;
""|install)
    # If mapr-installer has been installed, then do an update.
    # Otherwise, prepare the system for MapR installation
    prologue "Install required packages"
    [ $PROMPT_FORCE -eq $NO ] && isUpdate
    fetchDependencies
    testConnection
    setPort
    [ $ISUPDATE -eq $NO ] && cleanup && createUser
    fetchEnvironment
    fetchInstaller_$OS
    fetchVersions_$OS
    createPropertiesFile
    startServer
    epilogue
    ;;
reload)
    # avoid questions asked during package upgrade
    PROMPT_SILENT=$YES
    checkOS
    fetchVersions_$OS
    updatePropertiesFile
    reloadPropertiesFile
    ;;
remove) remove ;;
update)
    prologue "Update packages"
    testConnection
    ISUPDATE=$YES
    fetchInstaller_$OS
    fetchVersions_$OS
    updatePropertiesFile
    reloadPropertiesFile
    startServer
    epilogue
    ;;
*) usage ;;
esac

exit 0

