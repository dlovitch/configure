#!/bin/bash

# get_: echo requested data
# set_: change/add data, previous data/comments/whitespace not guaranteed 
# update_: change/add data, previous data/comments/whitespace should not be affected

# Get a sane screen width
[ -z "${COLUMNS:-}" ] && COLUMNS=80

RES_COL=60
MOVE_TO_COL="echo -en \\033[${RES_COL}G"
SETCOLOR_SUCCESS="echo -en \\033[1;32m"
SETCOLOR_FAILURE="echo -en \\033[1;31m"
SETCOLOR_WARNING="echo -en \\033[1;33m"
SETCOLOR_NORMAL="echo -en \\033[0;39m"


DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

. $DIR/general_functions.sh
. $DIR/network_functions.sh