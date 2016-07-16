#!/bin/bash

DEBUG=0
debug() {
    if [ "$DEBUG" -eq "1" ]; then
        echo -e "$1"
    fi
}

get_distro() {
    if [ -f /etc/debian_version ]; then
        echo 'DEBIAN'
    elif [ -f /etc/redhat-release ]; then
        if grep -qE 'CentOS.*4\..*' /etc/redhat-release; then
            echo 'RHEL4'
        elif grep -qE 'CentOS.*5\..*' /etc/redhat-release; then
            echo 'RHEL5'
        fi
    else
        echo 'UNKNOWN'
    fi
}

backup_config() {
    # backs up file $1 to backup/$1
    # only helps if the previous version is still sane
    #PATHPART=$(awk -F\/ 'BEGIN{$0="'"$1"'"; print substr($0,1,length($0)-length($NF)-1)}')
    if [ -z "$1" ]; then
        exit 1
    fi
    PATHPART="${1%/*}"
    mkdir -p "backup/$PATHPART"
    cp -a "$1" "backup/$1"
}

update_debian_system() {
    apt-get update
    apt-get -y dist-upgrade
    apt-get clean
}

update_redhat_system() {
    service yum-updatesd stop
    yum -y update
    yum clean all
    service yum-updatesd start
}

update_system() {
    DISTRO=$(get_distro)
    case "$DISTRO" in
        DEBIAN)
            update_debian_system
            ;;
        RHEL*)
            update_redhat_system
            ;;
        *)
            echo "Unknown system, can't update."
    esac
}


install_packages() {
    # expects variables in the form
    # conf_packages_{groupname}
    # like conf_packages_general, conf_packages_python
    # and a list of lists like conf_packagelists="general python"

    DISTRO=$(get_distro)
    case "$DISTRO" in
        DEBIAN)
            for packages_list in $conf_packagelists; do
                package_list="conf_packages_${packages_list}"
                aptitude install ${!package_list}
            done
            ;;
        RHEL*)
            echo "need to do something here"
            ;;
        *)
            echo "Unknown system, can't update."
    esac
}

clean_apt_cache() {
    #Fixes occasional apt cache errors 
    rm /var/cache/apt/*.bin
}
