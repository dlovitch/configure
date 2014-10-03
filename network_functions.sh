#!/bin/bash

. general_functions.sh

get_hwaddr() { # taken mostly from RedHat
    if [ -f /sys/class/net/${1}/address ]; then
        awk '{ print toupper($0) }' < /sys/class/net/${1}/address
    elif [ -d "/sys/class/net/${1}" ]; then
        LC_ALL= LANG= ip -o link show ${1} 2>/dev/null | \            awk '{ print toupper(gensub(/.*link\/[^ ]* ([[:alnum:]:]*).*/,
                                        "\\1", 1)); }'
        else # use minimal no gawk, etc
                ifconfig ${1} | grep -m1 'HWaddr' | sed -e 's/^.*HWaddr \([[:alnum
:]:]*\).*$/\1/' -e 'y/abcdef/ABCDEF/'
    fi
}

set_nameservers() {
    local etc_resolv_data=""
    until [ -z "$1" ]
    do
        etc_resolv_data="${etc_resolv_data}nameserver $1\n"
        shift
    done
    echo -e "$etc_resolv_data" >/etc/resolv.conf
}

set_hostname() {
    # Tested on Debian and Ubuntu.

    # $1 should be the hostname
    # $2 should be the domain
    # $3 should be the IP address that the hostname should be assigned to
    
    echo -n "Setting hostname to $1.$2..."
    $MOVE_TO_COL
    echo -n "["

    # This should only be the system hostname, 
    # not a FQDN (as per http://www.debian.org/doc/manuals/reference/ch-gateway.en.html)
    echo $1 >/etc/hostname
    /bin/hostname -F /etc/hostname
    echo -n " /etc/hostname"

    if grep -q "$3" /etc/hosts ; then 
        echo "exists"; sed -E -i -e "s/^$3.*$/$3    $1.$2    $1/" /etc/hosts
    else
        # if we haven't found it, add it after localhost
        sed -i -e "s/^127.0.0.1[[:space:]][[:space:]]*localhost[[:space:]]*$/&\n$3    $1.$2    $1/" /etc/hosts
        echo -n " /etc/hosts"
    fi
    echo -n "   ok   "
    echo " ]"
    #echo -ne "\r"
    return 0
}


update_debian_interfaces() {
# Initialize variables

    IFACE_SECTION=0 
    unset IFACE_SECTION_MATCH #integer corresponding to location of match
    AUTO_SECTION=0
    MAPPING_SECTION=0
    ALLOW_SECTION=0
    IN_SECTION=0 # generic non-implented section
    
    declare -a ARRAY # holds interfaces file line by line
    
    INTERFACE_FILE=$1
    CHANGE_SECTION=$2

    backup_config $1
        
# check parameters
    if [ "$CHANGE_SECTION" == "iface" ]; then
        if [ -z "$4" ]; then
            echo "Method not specified, nothing to change."
            exit 1
        fi
        if [ "$4" != "dhcp" ] && [ "$4" != "static" ]; then
            echo "Method not supported, only dhcp and static are supported."
            exit 1
        fi
        INTERFACE_NEW_NAME=$3
        debug "interface new name set to: ${INTERFACE_NEW_NAME}"
        INTERFACE_NEW_ADDRFAM="inet"
        INTERFACE_NEW_METHOD=$4
        if [ "$4" == "static" ]; then
            if [ -z "$3" ] || [ -z "$5" ] || [ -z "$6" ]; then
                echo "Missing necessary values to configure interface with static method."
                exit 1
            else
                INTERFACE_NEW_address=$5
                INTERFACE_NEW_netmask=$6
                INTERFACE_NEW_gateway=$7 #optional
                INTERFACE_NEW_broadcast=$8 #optional
                echo -n "Configuring $INTERFACE_NEW_NAME as $INTERFACE_NEW_METHOD..."
                $MOVE_TO_COL
                echo -n "["
            fi
        fi
    else
        echo "Unknown or no options specified, cannot change."
        echo "Syntax:"
        echo "  \$1 = filename (/etc/network/interfaces)"
        echo "  \$2 = change_section (iface)"
        echo "  if change_section is iface"
        echo "    \$3 = iface_name"
        echo "    \$4 = iface_method"
        echo "    if iface_method is dhcp"
        echo "      \$4 = dhcp"
        echo "    if iface_method is static"
        echo "      \$4 = static"
        echo "      \$5 = ip address"
        echo "      \$6 = netmask"
        echo "      \$7 = gateway (optional)"
        echo "      \$8 = broadcast (optional, but if specified, gateway is required)"
        echo "Examples:"
        echo "  /etc/network/interfaces iface eth0 dhcp"
        echo "  /etc/network/interfaces iface eth0 static 192.168.1.2 255.255.255.0 192.168.1.1 192.168.1.255"
        exit 1
    fi
    
# read in file
    oldifs="$IFS"
    IFS=" "
    count=0
    while read LINE; do
        ARRAY[((count++))]=$LINE
        debug "reading: ${ARRAY[$count-1]}"
    done <$INTERFACE_FILE
    IFS="$oldifs"

    if [ $DEBUG -eq 1 ]; then
        echo -e "----------\n\nPrinting original file: \n"
        ELEMENTS=${#ARRAY[@]}
        for (( i=0; i <$ELEMENTS; i++)); do
            echo "${i}: ${ARRAY[${i}]}"
        done
    fi

    
# update existing elements
    ELEMENTS=${#ARRAY[@]}
    for (( i=0; i <$ELEMENTS; i++)); do
        # ignore blank lines and comments
        if  [ $(expr match "${ARRAY[${i}]}" "^\(#\).*") ] ||
            [ "${ARRAY[${i}]}" == "" ]; then
            continue
        fi
        
        # found an interface section
        if  [ $(expr match "${ARRAY[${i}]}" "^iface.*") -ne 0 ]; then
            IFACE_SECTION=1
            AUTO_SECTION=0
            MAPPING_SECTION=0
            ALLOW_SECTION=0
            IN_SECTION=0
            debug "found iface section header -- ${ARRAY[${i}]}"
            INTERFACE_NAME=$(expr match "${ARRAY[${i}]}" "^iface[[:space:]][[:space:]]*\([[:alnum:]][[:alnum:]]*\)[[:space:]].*")
            # found the interface section we're looking for
            debug "matching ${INTERFACE_NAME} with ${INTERFACE_NEW_NAME}"
            if [ "$INTERFACE_NAME" == "$INTERFACE_NEW_NAME" ]; then
                debug "match found ${INTERFACE_NEW_NAME}"
                IFACE_SECTION_MATCH=$i
                # if the method hasn't changed, do nothing with that line, if it has, update that line
                INTERFACE_METHOD=$(expr match "${ARRAY[${i}]}" "^iface[[:space:]][[:space:]]*$INTERFACE_NAME[[:space:]][[:space:]]*inet[[:space:]][[:space:]]*\([[:alnum:]][[:alnum:]]*\).*")
                if [ "$INTERFACE_METHOD" == "$INTERFACE_NEW_METHOD" ]; then
                    debug "configuration method matches, no need to change"
                else
                    debug "different configuration method, changing..."
                    ARRAY[${i}]="iface $INTERFACE_NEW_NAME $INTERFACE_NEW_ADDRFAM $INTERFACE_NEW_METHOD"
                fi
            else
                unset IFACE_SECTION_MATCH
            fi
    
            continue
        fi
    
        # found a (non-iface) section
        if  [ $(expr match "${ARRAY[${i}]}" "^\(mapping\|auto\|allow-\).*") ]; then
            debug "found section ${ARRAY[${i}]}"
            IN_SECTION=1
            IFACE_SECTION=0
            continue
        fi
        
        # inside the matched iface section, update any options
        if [ -n "${IFACE_SECTION_MATCH}" ]; then
            if [ "$INTERFACE_NEW_METHOD" == "dhcp" ]; then
                debug "looking at ${ARRAY[${i}]}"
                if  [ $(expr match "${ARRAY[${i}]}" "^[[:space:]]*\(address\|netmask\|broadcast\|network\|metric\|gateway\|pointopoint\|media\|mtu\).*") ]; then # options not possible for dhcp (previously set for static, etc)
                    unset ARRAY[${i}]
                    # do we need to shift/resize the array after this?
                fi
            elif [ "$INTERFACE_NEW_METHOD" == "static" ]; then
                if  [ $(expr match "${ARRAY[${i}]}" "^[[:space:]]*\(address\|netmask\|broadcast\|network\|metric\|gateway\|pointopoint\|media\|mtu\).*") ]; then # possible options for static
                    IFACE_OPTION=$(expr match "${ARRAY[${i}]}" "^[[:space:]]*\([^[:space:]]*\).*")
                    debug "found $IFACE_OPTION at ${i}, updating"
                    eval FOUND_$IFACE_OPTION=1
                    INTERFACE_NEW_OPTION="INTERFACE_NEW_${IFACE_OPTION}"
                    ARRAY[${i}]=$(echo "${ARRAY[${i}]}" | sed -e "s/^\([[:space:]]*$IFACE_OPTION\).*/\1 ${!INTERFACE_NEW_OPTION}/")
                fi
            fi
        fi
    done
    
# Add any new elements on new lines that were not matched in the above update
    if [ "$INTERFACE_NEW_METHOD" == "static" ] && [ -n "${IFACE_SECTION_MATCH}" ]; then
        for interface_option in address netmask gateway broadcast; do
            FOUND_INTERFACE_OPTION="FOUND_${interface_option}"
            INTERFACE_NEW_OPTION="INTERFACE_NEW_${interface_option}"
            if [ "${!FOUND_INTERFACE_OPTION}" != "1" ] && [ -n "${!INTERFACE_NEW_OPTION}" ]; then # need to add the option
                debug "need to add ${interface_option} option"
                # ** $IFACE_SECTION_MATCH+1 is the line after the iface section header
                # temporarily store everything from the beginning of the iface section to the end of the file
                unset TEMPARRAY
                unset j
                for (( i=$IFACE_SECTION_MATCH+1; i <${#ARRAY[@]}; i++)); do
                    debug "storing ${i}: ${ARRAY[${i}]}"
                    TEMPARRAY[((j++))]="${ARRAY[${i}]}"
                done
                # add the new option
                ARRAY[$IFACE_SECTION_MATCH+1]=$(echo -e "\t$interface_option ${!INTERFACE_NEW_OPTION}")
                # ** $IFACE_SECTION_MATCH+2 is the line after the iface section header and the option just added above
                for (( j=0; j<${#TEMPARRAY[@]}; j++)); do
                    debug "setting $((${IFACE_SECTION_MATCH}+2+${j})): ${ARRAY[${IFACE_SECTION_MATCH}+2+${j}]} to ${TEMPARRAY[${j}]}"
                    ARRAY[$IFACE_SECTION_MATCH+2+$j]="${TEMPARRAY[${j}]}"
                done
            fi
        done
    fi
    
    if [ $DEBUG -eq 1 ]; then
        echo -e "----------\n\nPrinting updated file: \n"
        ELEMENTS=${#ARRAY[@]}
        for (( i=0; i <$ELEMENTS; i++)); do
            echo "${i}: ${ARRAY[${i}]}"
        done
    fi
    
    if [ -f "$INTERFACE_FILE" ]; then
        echo -n >"$INTERFACE_FILE";
    fi
    ELEMENTS=${#ARRAY[@]}
    for (( i=0; i <${#ARRAY[@]}; i++)); do
        echo "${ARRAY[${i}]}" >>"$INTERFACE_FILE"
    done
    
    echo -n "   ok   "
    echo " ]"

}
