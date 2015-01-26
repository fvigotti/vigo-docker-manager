#!/usr/bin/env bash
set -e

echo -e '[ VIGO DOCKER MANAGER >>>> run ]'
REMOVE_HEADER="tail -n +2"

print_usage (){
echo -e 'usage = \n'$0' vdm_run --img-name testbash --container-name tb1 --run-params "" --timeout 10 --destroy-previous-container ' >&2
}


# DEFAULTS
STOP_CONTAINER_TIMEOUT_SECONDS=10
VDM_RUN_SCRIPT_VERSION=1
DOCKER_DETACHED_MODE="-d"
OPTIONS_DESTROY_PREVIOUS_CONTAINER=0
TMP_DIR="/tmp/"
DOCKER_RUN_LOGDIR="/var/log/docker/"
DOCKER_RUN_LOG_COMMENT=""
DOCKER_RUN_ADDITIONAL_PARAMS=''
DOCKER_IMAGE_VERSION=''
DOCKER_IMAGE_UNIQUE_ID_OR_NAMEANDVERSION=''
MAX_CONTAINER_RUN_ATTEMPT_COUNT=5
CUSTOM_DOCKER_RUN_CMD=''

clean_special_chars() {
    local a=${1//[^[:alnum:]]/}
    echo "${a,,}"
}


# ./vmd_run.sh -name "dumbscript1" -version "v1.6" -runParam "-d -P" -timeout 10
# PARSE ARGS
while [[ $# > 0 ]]
do
key="$1"

case $key in
    --img-name)
    DOCKER_IMAGE_NAME="$2"
    shift
    ;;
    --container-name)
    CONTAINER_NAME="$2"
    shift
    ;;
    --img-version) #optional
    DOCKER_IMAGE_VERSION="$2"
    shift
    ;;
    --run-params) #optional
    DOCKER_RUN_ADDITIONAL_PARAMS="$2"
    shift
    ;;
    -timeout|--timeout) #optional
    STOP_CONTAINER_TIMEOUT_SECONDS="$2"
    shift
    ;;
    --custom-cmd) #optional
    CUSTOM_DOCKER_RUN_CMD="$2"
    shift
    ;;
    --destroy-previous-container) #optional
    OPTIONS_DESTROY_PREVIOUS_CONTAINER=1
    ;;
    --no-log) #optional
    DO_RESTART=1
    ;;
    --no-detach) #optional
    DOCKER_DETACHED_MODE=''
    ;;
    --default) #optional
    DEFAULT=YES
    ;;
    *)
            # unknown option
    ;;
esac
shift
done

CONTAINER_HISTORY_PRESERVE_COUNT=4

[ -z "$CONTAINER_NAME" ] && {
    echo 'container name is mandatory' >&2
    exit 1
}

CUR_EPOCH=$(date +%s)

##################  HEADER


containers_created () {
docker ps -a  | awk '$2 ~ "^'${DOCKER_IMAGE_NAME}':(.*)$" {print $0}' | $REMOVE_HEADER
}

escape_regex_chars () {
    echo $1 | sed -e 's/[]\/$*.^|[]/\\&/g'
}


# available awk params are :
#       1                             2                    3             4............
# kayess/fost-builder                trusty              4ab2d2c5d0b9        4 weeks ago         781.9 MB
#
get_find_docker_images() {
    local image_name=$1
    local print_awk_param=$2
    docker images --no-trunc | awk '$1 ~ "^'$( escape_regex_chars $image_name )'$" {print $'$print_awk_param'}'
}

# given an image extract the latest
get_latest_image_id() {
    local image_name=$1
    echo $(get_sorted_images $image_name) | head -1 |awk '{print $3}'
}

# return running container for the given name
get_running_container_id_from_name() {
    local container_name=$1
    docker ps --filter='name='$container_name -q --no-trunc
}

get_stopped_or_started_container_id_from_name() {
    local container_name=$1
    docker ps -a --filter='name='$container_name -q --no-trunc
}

get_sorted_images () {
    local image_name=$1
    docker images  --no-trunc | awk '$1 ~ "^'$( escape_regex_chars $image_name )'$" {print $0}' | sort --ignore-leading-blanks --version-sort -k2 -r
}

stop_running_container(){
    local container_id=$1
    local stop_timeout=$2
    echo 'stopping container : '$container_id' , timeout='$stop_timeout' , start'`date`  >&2
    docker stop -t $stop_timeout $container_id
    local stop_results=$?
    echo 'stopping container : '$container_id' , timeout='$stop_timeout' , end'$(date)', results = '$stop_results  >&2
    return $stop_results
}

docker_remove_stopped_container () {
    local container_to_remove_name=$1
    echo 'removing container : '$container_to_remove_name' '`date`  >&2
    docker rm $container_to_remove_name
    echo 'removed container : '$container_to_remove_name' '`date`  >&2
    return $?
}

docker_restart_container () {
    local container_to_restart_name=$1
    echo 'restarting container : '$container_to_restart_name' '`date`  >&2
    docker start $container_to_restart_name
    local ret=$?
    echo 'restarting container : '$container_to_restart_name' , results = '$ret' , date='`date`  >&2
    return $ret
}

# return docker command to run the container
#
get_docker_start_container_CMD() {
   echo 'docker run '$DOCKER_DETACHED_MODE' '$DOCKER_RUN_ADDITIONAL_PARAMS' --name="'${CONTAINER_NAME}'" '${DOCKER_IMAGE_UNIQUE_ID_OR_NAMEANDVERSION} ${CUSTOM_DOCKER_RUN_CMD}
}

run_docker_cmd_multiple_attempt(){
    local retry_counter=0
    local docker_run_success=0

    DOCKER_CMD=$( get_docker_start_container_CMD )
    echo 'DOCKER_CMD = '$DOCKER_CMD  >&2



    MAX_CONTAINER_RUN_ATTEMPT_COUNT=5
    set +e
    set -o pipefail
    until [ "$retry_counter" -ge "$MAX_CONTAINER_RUN_ATTEMPT_COUNT" ]
       do
           sync
           echo -e '[EXECUTING]>'$DOCKER_CMD >&2
           echo $( date )' [EXECUTING] '$DOCKER_CMD >>  $DOCKER_RUN_LOG
           exec $DOCKER_CMD 2>&1 | tee -a $DOCKER_RUN_LOG
           docker_run_success=$?
           sync

           if [[ "$docker_run_success" != "0" ]]; # RUN FAILED
           then
               retry_counter=$[$retry_counter+1]
               echo '>>> run attempt '${retry_counter}' failed, retrying'  >&2
               sleep 2
           else # BUILD SUCCESS
               echo '[SUCCESS]  program started successfully (attempt number = '${retry_counter}')!'  >&2
               tail -10 $DOCKER_RUN_LOG
               set -e
               exit 0
               break;
           fi
       done
    echo '[FATAL-ERROR] run failed after '$retry_counter' attempt' >&2
    set -e
    tail -40 $DOCKER_RUN_LOG
    return 1
}

count_containers_created () {
    containers_created | wc -l
}

remove_oldest_n_containers () {
    if [ -z "$1" ]; then
     echo -e 'param missing' >&2
     exit -1
    fi
    local CONTAINERS_TO_REMOVE_COUNT=$1 # argv 1
    #docker ps -a  | grep ${DOCKER_IMAGE_NAME} | awk '{print $1}' | tail -"${CONTAINERS_TO_REMOVE_COUNT}" | while read -r id; do docker rm $id ; done
    # ( tail will strip out the header of the output)
    containers_created | tail -"${CONTAINERS_TO_REMOVE_COUNT}" | awk '{print $1}' | while read -r id; do docker rm $id ; done
}

search_app_instances_running () {
    local IMAGE_NAME=$1
    docker ps | awk '$2 ~ "^\\s*'${IMAGE_NAME}':.*$" {print $0}'
}

##################  BODY

echo '[START] VDM_RUN_SCRIPT_VERSION='$VDM_RUN_SCRIPT_VERSION >&2

echo 'DOCKER_IMAGE_NAME='${DOCKER_IMAGE_NAME}\
', DOCKER_IMAGE_VERSION = '${DOCKER_IMAGE_VERSION}\
' , DOCKER_RUN_PARAMS = '${DOCKER_RUN_ADDITIONAL_PARAMS}\
' , CUSTOM_DOCKER_RUN_CMD= '${CUSTOM_DOCKER_RUN_CMD}\
' , STOP_CONTAINER_TIMEOUT_SECONDS = '${STOP_CONTAINER_TIMEOUT_SECONDS}\
' , DOCKER_CONTAINER_INSTANCE_NAME = '${DOCKER_CONTAINER_INSTANCE_NAME}\
' , CUR_EPOCH = '${CUR_EPOCH} >&2
# ps -a  | grep ${DOCKER_IMAGE_NAME} | awk '{print $1}' | tail -2 | while read -r id; do docker rm $id ; done

if [ -z "$DOCKER_IMAGE_NAME" ] || ! [[ "$DOCKER_IMAGE_NAME" =~ ^(.+)$ ]]; then
    echo -e 'invalid DOCKER_IMAGE_NAME :'$DOCKER_IMAGE_NAME')' >&2
    print_usage
    exit -1
fi

# check existance of provided docker image
[[ -z "$(get_find_docker_images $DOCKER_IMAGE_NAME 3)" ]] && {
    echo '[ERROR] '$DOCKER_IMAGE_NAME' not found, exiting '  >&2
    exit 3
}

[ -d "$DOCKER_RUN_LOGDIR" ] || {
    echo 'docker log directory > '$DOCKER_RUN_LOGDIR' not found, creating it'  >&2
    mkdir -p $DOCKER_RUN_LOGDIR
}

if [ -z "$DOCKER_IMAGE_VERSION" ]; then
    echo 'DOCKER_IMAGE_VERSION not specified, searching for higher version number... ' >&2
    DOCKER_IMAGE_VERSION=$( get_sorted_images $DOCKER_IMAGE_NAME | head -1 |awk '{print $2}' )
    if [ -z "$DOCKER_IMAGE_VERSION" ]; then
        echo 'image version not found for image > '$(get_sorted_images $DOCKER_IMAGE_NAME) >&2
        exit 6
    fi
    echo 'DOCKER_IMAGE_VERSION found = '$DOCKER_IMAGE_VERSION >&2
fi
DOCKER_IMAGE_UNIQUE_ID_OR_NAMEANDVERSION=$DOCKER_IMAGE_NAME':'$DOCKER_IMAGE_VERSION
echo 'DOCKER_IMAGE_UNIQUE_ID_OR_NAMEANDVERSION = '$DOCKER_IMAGE_UNIQUE_ID_OR_NAMEANDVERSION >&2

DOCKER_RUN_LOG=$DOCKER_RUN_LOGDIR'/run_'${DOCKER_IMAGE_NAME}'.log'
echo 'DOCKER_RUN_LOG = '$DOCKER_RUN_LOG >&2

echo 'checking if container '$CONTAINER_NAME' is already running ' >&2
if ! [[ -z "$(get_running_container_id_from_name $CONTAINER_NAME )" ]]; then
    echo 'container '$CONTAINER_NAME' is already running, destroy it ? > '$OPTIONS_DESTROY_PREVIOUS_CONTAINER >&2
    if [[ "$OPTIONS_DESTROY_PREVIOUS_CONTAINER" == "1" ]]; then
        stop_running_container $CONTAINER_NAME $STOP_CONTAINER_TIMEOUT_SECONDS
        res=$?
        ! [[ -z "$(get_running_container_id_from_name )" ]] && {
            echo '[FATAL ERROR] container '$CONTAINER_NAME' has failed to stop ! return code='$res' , exiting' >&2
            exit 5
        }
        else
        echo 'container to start is already running, exit 0' >&2
        exit 0
    fi
fi

echo 'checking if container '$CONTAINER_NAME' is in stopped state ' >&2
if ! [[ -z "$(get_stopped_or_started_container_id_from_name $CONTAINER_NAME )" ]]; then
    echo 'container '$CONTAINER_NAME' is in stopped state, destroy it ? > '$OPTIONS_DESTROY_PREVIOUS_CONTAINER >&2
    if [[ "$OPTIONS_DESTROY_PREVIOUS_CONTAINER" == "1" ]]; then
        echo 'container '$CONTAINER_NAME' will now be deleted' >&2
        docker_remove_stopped_container $CONTAINER_NAME
    else
        echo 'container '$CONTAINER_NAME' should be started and NOT recreated' >&2
        docker_restart_container $CONTAINER_NAME
        exit $?
    fi
fi



echo 'checking if is not in started or stopped state before starting it ' >&2
if [[ -z "$(get_stopped_or_started_container_id_from_name $CONTAINER_NAME )" ]]; then
    echo 'container '$CONTAINER_NAME' will now be started ' >&2

    run_docker_cmd_multiple_attempt

fi


### closing parts
echo 'unsuccessfull end of the script, this row should never get printed'  >&2
echo 'unsuccessfull end of the script, this row should never get printed'





