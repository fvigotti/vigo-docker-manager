#!/bin/bash

install_vigo_docker_manager(){
local SRC_PATH=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
local check_file_name_existence=${SRC_PATH}'/vdm_run.sh'


# check directory
[[ -d $SRC_PATH ]] || {
    echo 'invalid source path '$SRC_PATH >&2
    exit 1
}

# check file

[[ -f "${check_file_name_existence}" ]] || {
    echo 'program not found  > '$check_file_name_existence >&2
    exit 1
}


for init in ${SRC_PATH}/*; do
    echo 'linking : '$init' /bin/'$init
    local dest_link_name=${init/\.sh/}
    # if destination link exist already, unlink
    [[ -h dest_link_name ]] && {
        echo ' destination is already a link, unlinking.. > '$dest_link_name >&2
        unlink $dest_link_name
    }
    chmod +x $init ;
	ln -s "${SRC_PATH}/${init}" "/bin/${dest_link_name}"

done
}

uninstall_vigo_docker_manager() {
    echo 'uninstall not implemented yet, unlink manually'
}

install_vigo_docker_manager $0
