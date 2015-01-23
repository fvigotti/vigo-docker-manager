#!/usr/bin/env bash
set -e

echo -e '[ VIGO DOCKER MANAGER >>>> run ]'
REMOVE_HEADER="tail -n +2"

print_usage (){
#echo -e 'usage = \n'$0' [-do_restart] -name APPNAME -version VERSION -runParam RUNPARAM -timeout TIMEOUT -path DOCKERFILEPATH\n\nExample:\n'$0' -name myapp -version 1.12 -runParam "-p 443:443 -p 80:80 -p 5922:22 -d" -timeout 10 -path="/opt/apptest/"' >&2
echo -e 'TODO, usage print '
}


# DEFAULTS
STOP_CONTAINER_TIMEOUT_SECONDS=10
VDM_RUN_SCRIPT_VERSION=1
DOCKER_DETACHED_MODE="-d"
OPTIONS_DESTROY_PREVIOUS_CONTAINER=0
TMP_DIR="/tmp/"
DOCKER_RUN_LOG_COMMENT=""


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
    --container-name) #optional
    CONTAINER_NAME="$2"
    shift
    ;;
    --img-version) #optional
    DOCKER_IMAGE_VERSION="$2"
    shift
    ;;
    --run-params) #optional
    DOCKER_RUN_PARAMS="$2"
    shift
    ;;
    -timeout|--timeout) #optional
    STOP_CONTAINER_TIMEOUT_SECONDS="$2"
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
DOCKER_IMAGE_NAME=${DOCKER_IMAGE_NAME}":"${DOCKER_IMAGE_VERSION}

CUR_EPOCH=$(date +%s)








echo 'DOCKER_IMAGE_NAME='${DOCKER_IMAGE_NAME}\
', DOCKER_IMAGE_VERSION = '${DOCKER_IMAGE_VERSION}\
' , DOCKER_RUN_PARAMS = '${DOCKER_RUN_PARAMS}\
' , STOP_CONTAINER_TIMEOUT_SECONDS = '${STOP_CONTAINER_TIMEOUT_SECONDS}\
' , DOCKER_CONTAINER_INSTANCE_NAME = '${DOCKER_CONTAINER_INSTANCE_NAME}\
' , CUR_EPOCH = '${CUR_EPOCH} >&2
# ps -a  | grep ${DOCKER_IMAGE_NAME} | awk '{print $1}' | tail -2 | while read -r id; do docker rm $id ; done

if [ -z "$DOCKER_IMAGE_NAME" ] || ! [[ "$DOCKER_IMAGE_NAME" =~ ^(.+)$ ]]; then
 echo -e 'invalid DOCKER_IMAGE_NAME :'$DOCKER_IMAGE_NAME')' >&2
     print_usage
    exit -1
fi


OUTPUT_LOG_PATH=$DOCKER_IMAGE_PATH'/log/'

##################  HEADER

get_default_instance_name () {
s=0
}

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
    docker stop -t $stop_timeout container_id
    local stop_results=$?
    echo 'stopping container : '$container_id' , timeout='$stop_timeout' , end'$(date)', results = 'stop_results  >&2
    return stop_results
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

docker_start_container() {
   echo "todo"
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
build_vdm_run_version_script() {
local VDM_RESTARTER_SCRIPT_FILENAME='vdm_restart_'$DOCKER_IMAGE_NAME'.sh'
local VDM_RESTARTER_SCRIPT_FILENAME=${VDM_RESTARTER_SCRIPT_FILENAME//":"/"_"} #replace -> : <- with -> _ <- in filename

# build output log directory if not exists
[ -d "${OUTPUT_LOG_PATH}" ] || mkdir "${OUTPUT_LOG_PATH}"
local VDM_RESTARTER_SCRIPT_FILENAME_AND_PATH=$OUTPUT_LOG_PATH''$VDM_RESTARTER_SCRIPT_FILENAME


if [ ! -e "$VDM_RESTARTER_SCRIPT_FILENAME_AND_PATH" ]; then
        echo -e 'creating restarter script : '$VDM_RESTARTER_SCRIPT_FILENAME_AND_PATH >&2
VDM_RESTARTER_SCRIPT_CONTENT='
#!/usr/bin/env bash\n
set -e\n
vdm_run -name "'$DOCKER_IMAGE_NAME'" -version "'$DOCKER_IMAGE_VERSION'" -runParam "'$DOCKER_RUN_PARAMS'" -timeout "'$STOP_CONTAINER_TIMEOUT_SECONDS'" -path "'$DOCKER_IMAGE_PATH'" $@ \n
'
        echo -e $VDM_RESTARTER_SCRIPT_CONTENT > $VDM_RESTARTER_SCRIPT_FILENAME_AND_PATH
        chmod +x $VDM_RESTARTER_SCRIPT_FILENAME_AND_PATH
    fi
}

##################  BODY


echo '[START] VDM_RUN_SCRIPT_VERSION='$VDM_RUN_SCRIPT_VERSION >&2
echo '[CHDIR] '$DOCKER_IMAGE_PATH >&2
cd $DOCKER_IMAGE_PATH




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
fi


DOCKER_IMAGE_TO_RUN
# check existance of provided docker image
[[ -z "$(get_find_docker_images $DOCKER_IMAGE_NAME 3)" ]] && {
echo '[ERROR] '$DOCKER_IMAGE_NAME' not found, exiting '  >&2
exit 3
}


DOCKER_IMAGE_VERSION




build_vdm_run_version_script

ALREADY_RUNNING_CONTAINER=$(search_app_instances_running ${DOCKER_IMAGE_NAME})
ALREADY_RUNNING_COUNTER=$(search_app_instances_running ${DOCKER_IMAGE_NAME} |wc -l)
echo '$ALREADY_RUNNING_COUNTER = '$ALREADY_RUNNING_COUNTER' , $DO_RESTART='$DO_RESTART >&2
if [ "$ALREADY_RUNNING_COUNTER" -gt "0" ]; then
   if [ "$DO_RESTART" -gt "0" ]; then
    echo '[RESTART] app container already running =  '${DOCKER_IMAGE_NAME}' '${DOCKER_IMAGE_VERSION}', stopping instances ' >&2
    search_app_instances_running ${DOCKER_IMAGE_NAME} | awk   '{print $1}' | xargs --no-run-if-empty docker stop -t $STOP_CONTAINER_TIMEOUT_SECONDS
   else
    echo '[ALREADY RUNNING] app container already running =  '${ALREADY_RUNNING_CONTAINER} >&2
    exit 0
   fi
else
    echo '>>> no previous instances running' >&2
fi

echo ">>> purge old containers" >&2
CONTAINER_CREATED_COUNT=$(count_containers_created)
CONTAINERS_TO_REMOVE_COUNT=$((CONTAINER_CREATED_COUNT-CONTAINER_HISTORY_PRESERVE_COUNT))
echo 'containers created count : '${CONTAINER_CREATED_COUNT}' , to remove = '${CONTAINERS_TO_REMOVE_COUNT} >&2
if [ "$CONTAINERS_TO_REMOVE_COUNT" -gt "0" ]
then
 remove_oldest_n_containers $CONTAINERS_TO_REMOVE_COUNT
fi



#
#echo '>>> Stop previous version of this app'
#if [ "$DRY_RUN" -eq "0" ]; then
#sync
#docker ps --filter "name="${DOCKER_IMAGE_NAME} -q | xargs --no-run-if-empty docker stop -t $STOP_CONTAINER_TIMEOUT_SECONDS
#sleep 1
#sync
#sleep 1
#else
#echo -e '[DRY-RUN]\n docker ps --filter "name="'${DOCKER_IMAGE_NAME}' -q | xargs --no-run-if-empty docker stop -t '$STOP_CONTAINER_TIMEOUT_SECONDS
#fi

echo '>>> Starting container docker run -d '$DOCKER_RUN_PARAMS' --name="'${DOCKER_CONTAINER_INSTANCE_NAME}'" '${DOCKER_IMAGE_NAME} >&2

if [ "$DRY_RUN" -eq "0" ]; then
docker ps --filter "name="${DOCKER_IMAGE_NAME} -q | xargs --no-run-if-empty docker stop -t $STOP_CONTAINER_TIMEOUT_SECONDS
sync
else
echo -e '[DRY-RUN]\n docker ps --filter "name="'${DOCKER_IMAGE_NAME}' -q | xargs --no-run-if-empty docker stop -t '$STOP_CONTAINER_TIMEOUT_SECONDS >&2
fi



if [ "$DRY_RUN" -eq "0" ]; then
    [ -d "${OUTPUT_LOG_PATH}" ] || mkdir "${OUTPUT_LOG_PATH}"
    RUN_LOG=$OUTPUT_LOG_PATH'vdm_run_'${DOCKER_IMAGE_NAME}'_'${DOCKER_IMAGE_VERSION}'.log'
    # reset run log
    echo "" > $RUN_LOG

    n=0


    MAX_RETRY_COUNT=5
    set +e
    set -o pipefail
    until [ "$n" -ge "$MAX_RETRY_COUNT" ]
       do

           sync
           rebuild_instance_name
           echo -e '[EXECUTING]\ndocker run  -d '$DOCKER_RUN_PARAMS' --name="'${DOCKER_CONTAINER_INSTANCE_NAME}'" '${DOCKER_IMAGE_NAME} >&2
           docker run -d $DOCKER_RUN_PARAMS --name="${DOCKER_CONTAINER_INSTANCE_NAME}" ${DOCKER_IMAGE_NAME} 2>&1 | tee -a $RUN_LOG
           buildResults=$?

           sync

           if [[ "$buildResults" != "0" ]]; # RUN FAILED
           then
               n=$[$n+1]
               echo '>>> run attempt '${n}' failed, retrying'  >&2
               sleep 2
           else # BUILD SUCCESS
               echo '[SUCCESS]  program started successfully (attempt '${n}')!'  >&2
               tail -10 $RUN_LOG
               set -e
               exit 0
               break;
           fi
       done
    echo '[FATAL-ERROR] run failed after '$n' attempt' >&2
    set -e
    tail -40 $RUN_LOG
    set -e
    return 1

else
echo -e '[DRY-RUN]\ndocker run  -d '$DOCKER_RUN_PARAMS' --name="'${DOCKER_CONTAINER_INSTANCE_NAME}'" '${DOCKER_IMAGE_NAME} >&2
fi







