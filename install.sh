#!/bin/bash

set -x

install_vigo_docker_manager(){
local SRC_PATH=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )'/src'
local DST_PATH='/opt/vdm/'
local check_file_name_existence=${SRC_PATH}'/vdm_run.sh'




# ensure source directory exists
[[ -d $SRC_PATH ]] || {
    echo 'invalid source path '$SRC_PATH >&2
    exit 1
}

# ensure destination directory DO NOT EXISTS
[[ -d $DST_PATH ]] && {
    echo 'installation destination already exist, please cleanup directory '$DST_PATH >&2
    exit 2
}

# validate source path checking an expected file presence
[[ -f "${check_file_name_existence}" ]] || {
    echo 'program not found  in source directory > '$check_file_name_existence >&2
    exit 1
}

echo 'creating installation dir: '$DST_PATH >&2
mkdir -p $DST_PATH

echo 'copying sources on installation dir: '$DST_PATH >&2
cp -Rp ${SRC_PATH}/* "${DST_PATH}/"


for fileItem in ${DST_PATH}/*.sh; do


    # extract filename
    local fileName=$(basename $fileItem)


    #remove ".sh" from filename
    fileName=${fileName/\.sh/}
    dest_link_name="/bin/${fileName}"

    # if destination link exist already, unlink
    [[ -h $dest_link_name ]] && {
        echo ' destination is already a link, unlinking.. > '$fileName >&2
        unlink $dest_link_name
    }

    echo 'make program file executable '$fileItem
    chmod +x $fileItem ;

    echo 'linking program file to /bin path: '$fileItem' => '$dest_link_name
	ln -s "${fileItem}" $dest_link_name

done

} # end main

uninstall_vigo_docker_manager() {
    echo 'uninstall not implemented yet, unlink manually'
}


install_vigo_docker_manager $0
