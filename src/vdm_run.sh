#!/usr/bin/env bash
set -e

echo -e '[ VIGO DOCKER MANAGER >>>> run ]'
REMOVE_HEADER="tail -n +2"

print_usage (){
echo -e 'usage = \n'$0' [-do_restart] -name APPNAME -version VERSION -runParam RUNPARAM -timeout TIMEOUT -path DOCKERFILEPATH\n\nExample:\n'$0' -name myapp -version 1.12 -runParam "-p 443:443 -p 80:80 -p 5922:22 -d" -timeout 10 -path="/opt/apptest/"' >&2
}

if [ "5" -gt $# ] ; then
    echo -e 'failing because not enougth params \n' >&2
    print_usage
    exit -1
fi


# DEFAULTS
STOP_CONTAINER_TIMEOUT_SECONDS=3600
VDM_RUN_SCRIPT_VERSION=1
DRY_RUN=0
DO_RESTART=0
DO_START=0
RUN_MODE=""
TMP_DIR="/tmp/"

# ./vmd_run.sh -name "dumbscript1" -version "v1.6" -runParam "-d -P" -timeout 10
# PARSE ARGS
while [[ $# > 0 ]]
do
key="$1"

case $key in
    -name|--name)
    APP_NAME="$2"
    shift
    ;;
    -path|--path)
    DOCKER_IMAGE_PATH="$2"
    shift
    ;;
    -version|--version)
    APP_VERSION="$2"
    shift
    ;;
    -runParam|--runParam)
    DOCKER_RUN_PARAMS="$2"
    shift
    ;;
    -timeout|--timeout)
    STOP_CONTAINER_TIMEOUT_SECONDS="$2"
    shift
    ;;
    -mode|--mode)
    RUN_MODE="$2"
    shift
    ;;
    -do-restart|--do-restart)
    DO_RESTART=1
    ;;
    --default)
    DEFAULT=YES
    ;;
    --dry-run)
    DRY_RUN=1
    ;;
    *)
            # unknown option
    ;;
esac
shift
done

CONTAINER_HISTORY_PRESERVE_COUNT=4
DOCKER_IMAGE_NAME=${APP_NAME}":"${APP_VERSION}

CUR_EPOCH=$(date +%s)








echo 'APP_NAME='${APP_NAME}\
', APP_VERSION = '${APP_VERSION}\
' , DOCKER_RUN_PARAMS = '${DOCKER_RUN_PARAMS}\
' , STOP_CONTAINER_TIMEOUT_SECONDS = '${STOP_CONTAINER_TIMEOUT_SECONDS}\
' , DOCKER_CONTAINER_INSTANCE_NAME = '${DOCKER_CONTAINER_INSTANCE_NAME}\
' , CUR_EPOCH = '${CUR_EPOCH} >&2
# ps -a  | grep ${APP_NAME} | awk '{print $1}' | tail -2 | while read -r id; do docker rm $id ; done

if [ -z "$APP_NAME" ] || ! [[ "$APP_NAME" =~ ^(.+)$ ]]; then
 echo -e 'invalid APP_NAME :'$APP_NAME')' >&2
     print_usage
    exit -1
fi

if [ -z "$APP_VERSION" ] || ! [[ "$APP_VERSION" =~ ^([0-9\.]+)$ ]]; then
 echo -e 'invalid APP_VERSION :'$APP_VERSION')' >&2
    print_usage
    exit -1
fi

if [ -z "$DOCKER_IMAGE_PATH" ] || ! [[ "$DOCKER_IMAGE_PATH" =~ ^/(.+)/$ ]]; then
    echo -e 'invalid DOCKER_IMAGE_PATH :'$DOCKER_IMAGE_PATH' , required string between slashes' >&2
    print_usage
    exit -1
fi

if [ ! -d "$DOCKER_IMAGE_PATH" ]; then
 echo -e 'DOCKER_IMAGE_PATH :'$DOCKER_IMAGE_PATH' , do not exists' >&2
    print_usage
    exit -1
fi



OUTPUT_LOG_PATH=$DOCKER_IMAGE_PATH'/log/'


##################  HEADER

rebuild_instance_name () {
CUR_EPOCH=$(date +%s)

DOCKER_CONTAINER_INSTANCE_NAME=$APP_NAME"_"$APP_VERSION"_"$CUR_EPOCH
}


containers_created () {
docker ps -a  | awk '$2 ~ "^'${APP_NAME}':(.*)$" {print $0}' | $REMOVE_HEADER
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
#docker ps -a  | grep ${APP_NAME} | awk '{print $1}' | tail -"${CONTAINERS_TO_REMOVE_COUNT}" | while read -r id; do docker rm $id ; done
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
vdm_run -name "'$APP_NAME'" -version "'$APP_VERSION'" -runParam "'$DOCKER_RUN_PARAMS'" -timeout "'$STOP_CONTAINER_TIMEOUT_SECONDS'" -path "'$DOCKER_IMAGE_PATH'" $@ \n
'
        echo -e $VDM_RESTARTER_SCRIPT_CONTENT > $VDM_RESTARTER_SCRIPT_FILENAME_AND_PATH
        chmod +x $VDM_RESTARTER_SCRIPT_FILENAME_AND_PATH
    fi
}

##################  BODY

echo '[START] VDM_RUN_SCRIPT_VERSION='$VDM_RUN_SCRIPT_VERSION >&2
echo '[CHDIR] '$DOCKER_IMAGE_PATH >&2
cd $DOCKER_IMAGE_PATH

build_vdm_run_version_script

ALREADY_RUNNING_CONTAINER=$(search_app_instances_running ${APP_NAME})
ALREADY_RUNNING_COUNTER=$(search_app_instances_running ${APP_NAME} |wc -l)
echo '$ALREADY_RUNNING_COUNTER = '$ALREADY_RUNNING_COUNTER' , $DO_RESTART='$DO_RESTART >&2
if [ "$ALREADY_RUNNING_COUNTER" -gt "0" ]; then
   if [ "$DO_RESTART" -gt "0" ]; then
    echo '[RESTART] app container already running =  '${APP_NAME}' '${APP_VERSION}', stopping instances ' >&2
    search_app_instances_running ${APP_NAME} | awk   '{print $1}' | xargs --no-run-if-empty docker stop -t $STOP_CONTAINER_TIMEOUT_SECONDS
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
#docker ps --filter "name="${APP_NAME} -q | xargs --no-run-if-empty docker stop -t $STOP_CONTAINER_TIMEOUT_SECONDS
#sleep 1
#sync
#sleep 1
#else
#echo -e '[DRY-RUN]\n docker ps --filter "name="'${APP_NAME}' -q | xargs --no-run-if-empty docker stop -t '$STOP_CONTAINER_TIMEOUT_SECONDS
#fi

echo '>>> Starting container docker run -d '$DOCKER_RUN_PARAMS' --name="'${DOCKER_CONTAINER_INSTANCE_NAME}'" '${DOCKER_IMAGE_NAME} >&2

if [ "$DRY_RUN" -eq "0" ]; then
docker ps --filter "name="${APP_NAME} -q | xargs --no-run-if-empty docker stop -t $STOP_CONTAINER_TIMEOUT_SECONDS
sync
else
echo -e '[DRY-RUN]\n docker ps --filter "name="'${APP_NAME}' -q | xargs --no-run-if-empty docker stop -t '$STOP_CONTAINER_TIMEOUT_SECONDS >&2
fi



if [ "$DRY_RUN" -eq "0" ]; then
    [ -d "${OUTPUT_LOG_PATH}" ] || mkdir "${OUTPUT_LOG_PATH}"
    RUN_LOG=$OUTPUT_LOG_PATH'vdm_run_'${APP_NAME}'_'${APP_VERSION}'.log'
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







