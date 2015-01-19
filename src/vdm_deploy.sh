#!/usr/bin/env bash
set -e

echo -e '[ VIGO DOCKER MANAGER >>>> deploy ]'  >&2

REMOVE_HEADER="tail -n +2"

print_usage ()
{
echo -e 'usage = \n'$0' [-do_restart , --do_rebuild]  -name APPNAME -version VERSION -runParam RUNPARAM -timeout TIMEOUT -path DOCKERFILEPATH\n\nExample:\n'$0' -name myapp -version 1.12 -runParam "-p 443:443 -p 80:80 -p 5922:22 -d" -timeout 10 -path="/opt/apptest/"'  >&2
}

if [ "5" -gt $# ] ; then
    #echo 'usage = '$0' APPNAME VERSION PARAMS / ie: '$0' myapp v1.12 "-p 443:443 -p 80:80 -p 5922:22 -d" '
    print_usage
    exit -1
fi

#APP_NAME="t1_app1"
#APP_VERSION="v1.3"
#
#APP_NAME=$1
#APP_VERSION=$2
#DOCKER_RUN_PARAMS=$3


# DEFAULTS
VDM_DEPLOY_SCRIPT_VERSION=1
DEFAULT_BUILD_RETRY_ATTEMPT=10 #this is necessary because devicemapper occasionally fails to mount images during build process
STOP_CONTAINER_TIMEOUT_SECONDS=3600
DO_RESTART=0
DO_REBUILD=0
CLEAN_GARBAGE=0
DO_START=1
# vmd_deploy -name "dumbscript1" -version "v1.6" -runParam "-d -P" -timeout 10 -path "/opt/docker_dumbscr1/"
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
    -do-restart|--do-restart)
    DO_RESTART=1
    ;;
    -do-rebuild|--do-rebuild)
    DO_REBUILD=1
    ;;
    --clean-garbage)
    CLEAN_GARBAGE=1
    ;;
    --build-only)
    DO_START=0
    ;;
    --default)
    DEFAULT=YES
    ;;
    *)
            # unknown option
    ;;
esac
shift
done

IMAGES_HISTORY_COUNT=3
DOCKER_IMAGE_NAME=${APP_NAME}":"${APP_VERSION}

CURPATH=$(pwd)
CUR_EPOCH=$(date +%s)

echo 'CURPATH = '${CURPATH}\
' , DOCKER_IMAGE_PATH='${DOCKER_IMAGE_PATH}\
' , APP_NAME='${APP_NAME}\
', APP_VERSION = '${APP_VERSION}\
' , DOCKER_RUN_PARAMS = '${DOCKER_RUN_PARAMS}\
' , STOP_CONTAINER_TIMEOUT_SECONDS = '${STOP_CONTAINER_TIMEOUT_SECONDS}\
' , CUR_EPOCH = '${CUR_EPOCH}  >&2
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


# remove the <none>-named images


#  untagged_containers 0 --> print full row for untagged containers
#  untagged_containers 1 --> print untagged containers ids
untagged_containers() {
  # Print containers using untagged images: $1 is used with awk's print: 0=line, 1=column 1.
  docker ps -a | awk '$2 ~ "[0-9a-f]{12}" {print $'$1'}'
}
untagged_running_containers() {
  # Print containers using untagged images: $1 is used with awk's print: 0=line, 1=column 1.
  docker ps | awk '$2 ~ "[0-9a-f]{12}" {print $'$1'}'
}


get_running_containers_for_image() { #$1 = ImageAndTagRegexp" $2 = fields to print
  echo ':run docker ps | awk ''$2 ~ "^\\s*'$1'\\s*$"  {print $'$2'}''' >&2
  docker ps | awk '$2 ~ "^\\s*'$1'\\s*$"  {print $'$2'}'
}

search_image_and_tag () {
    local IMAGE_NAME=$1
    local IMAGE_TAG=$2
    docker images  | awk '$1 ~ "^\\s*'${IMAGE_NAME}'\\s*$" && $2 ~ "^\\s*'${IMAGE_TAG}'\\s*$" {print $0}'
}

get_sorted_images () {
 docker images  | awk '$1 ~ "'${APP_NAME}'" {print $0}' | sort --ignore-leading-blanks --version-sort -k2 -r
}

 get_stopped_containers_ids_for_image_id () {
if [ -z "$1" ] || ! [[ "$1" =~ ^[0-9a-f]+$ ]]; then
 echo -e 'invalid image id : '$1' ' >&2
 exit -1
fi
docker ps -a --filter "status=exited" \
| $REMOVE_HEADER \
| awk '$2 ~ "'$1'" {print $1}'

}

get_stopped_containers_for_image_name () {
if [ -z "$1" ] || ! [[ "$1" =~ ^(.+):(.+)$ ]]; then
 echo -e 'param missing image NAME:TAG is required, with the colon to separate tag name! given : '$1' ' >&2
 exit -1
fi
docker ps -a --filter "status=exited" \
| $REMOVE_HEADER \
| awk '$2 ~ "'$1'" {print $0}'

}

remove_stopped_containers_for_image () {
#INSTANCE var
local IMAGE_NAME_AND_TAG=$1
sync
get_stopped_containers_for_image_name $IMAGE_NAME_AND_TAG | awk '{print $1}' | xargs --no-run-if-empty docker rm
sync
}

get_deprecated_oldest_images_name_and_tag () {
if [ -z "$1" ]; then
 echo -e 'param missing  amount of images to preserve on history is required ' >&2
 exit -1
fi
local ROLLBACK_IMAGES_TO_KEEP=$(($1)) #remember that tail -n strip the first row, and :latest image is also included (when ROLLBACK_IMAGES_TO_KEEP=7 , 5 real rollback images are kept )
get_sorted_images | $REMOVE_HEADER | tail -n +"${ROLLBACK_IMAGES_TO_KEEP}" | awk '{print $1":"$2}'
}

remove_oldest_images () {
    sync
    echo -e '>>> deleting stopped container for deprecated images  preserving '$1' images in history'  >&2
    #docker ps -a | awk '$2 ~ "a:3" {print $0}'
    get_deprecated_oldest_images_name_and_tag $1 \
    | while read -r imageIdToRemove; do

        local IMAGE_TO_REMOVE_CURRENTLY_RUNNING=$(get_running_containers_for_image ${imageIdToRemove} "0" |wc -l)
        echo '$IMAGE_TO_REMOVE_CURRENTLY_RUNNING = '$IMAGE_TO_REMOVE_CURRENTLY_RUNNING  >&2

        # if image container is not currently running
        if [ "$IMAGE_TO_REMOVE_CURRENTLY_RUNNING" -gt "0" ]; then
            echo '$IMAGE_TO_REMOVE_CURRENTLY_RUNNING (list version)= '$(get_running_containers_for_image ${imageIdToRemove} "0" )  >&2
            # if forcing restart OR
            if [[ $DO_RESTART = 1 ]]; then
               echo '[RESTART] force stop of running image because deprecated '${imageIdToRemove}  >&2
               get_running_containers_for_image ${imageIdToRemove} "1"  | xargs --no-run-if-empty docker stop -t $STOP_CONTAINER_TIMEOUT_SECONDS
               sync
            else
               echo '[WARNING] skip deletion of deprecated image: '${imageIdToRemove} ' because running'  >&2
               continue #skip this image
               echo '[FATAL ERROR ] POST CONTINNUE MESSAGE'  >&2
            fi
        fi

        echo -e 'remove_stopped_containers_for_image '$imageIdToRemove ;  >&2
        remove_stopped_containers_for_image $imageIdToRemove ;
        echo -e '[DELETE-DEPRECATED-IMAGE] deleting '$imageIdToRemove' image'  >&2;
        docker rmi $imageIdToRemove ;
        done

    sync
}
#
#remove_dangling_images ()
#{
##CONTAINERS_TO_REMOVE_COUNT=$1 # argv 1
##docker ps -a  | grep ${APP_NAME} | awk '{print $1}' | tail -"${CONTAINERS_TO_REMOVE_COUNT}" | while read -r id; do docker rm $id ; done
## ( tail will strip out the header of the output)
#docker images --filter "dangling=true" | awk '$3 ~ "[0-9a-f]{12}" {print $3}' | while read -r id; do
#echo -e 'deleting image "'$id'" stopped containers ';
#get_stopped_containers_ids_for_image_id $id | xargs --no-run-if-empty docker rm
#echo -e 'deleting image: '$id;
#docker rmi $id ;
#done
#}

remove_nonamed_images () {

sync
echo -e '>>> deleting <none> named images'  >&2
docker images | awk '$1 ~ "<none>" {print $3}' | while read -r id; do
 echo -e 'remove none-named image :'$id' stopped containers'  >&2 ;
 get_stopped_containers_ids_for_image_id $id | xargs --no-run-if-empty docker rm
 echo -e 'remove none-named image :'$id' image'  >&2;
 docker rmi $id ;
done

sync

}


build_image () {
local MAX_RETRY_COUNT=$1
# same thing? :)
#remove_dangling_images
sync
#TEMP DISABLED TO AVOID CHACHE PURGE
[[ $CLEAN_GARBAGE = 1 ]] && remove_nonamed_images

echo "Stop containers with untagged images:" >&2
untagged_running_containers 1 | xargs --no-run-if-empty docker stop -t $STOP_CONTAINER_TIMEOUT_SECONDS
sync

echo "Remove containers with untagged images:" >&2
untagged_containers 1 | xargs --no-run-if-empty docker rm --volumes=true
sync
## build image with cleanup of intermediate containers (  docker build -rm=true )

echo "Purge deprecated version images:" >&2
remove_oldest_images $IMAGES_HISTORY_COUNT
sync


local BUILD_LOG_FILENAME='vdm_build_'${APP_NAME}':'${APP_VERSION}'.log'

# build output log directory if not exists
[ -d "${OUTPUT_LOG_PATH}" ] || mkdir "${OUTPUT_LOG_PATH}"
local BUILD_LOG_FILENAME_AND_PATH=$OUTPUT_LOG_PATH''$BUILD_LOG_FILENAME

local n=0
echo -e '$n='$n' ,$MAX_RETRY_COUNT='$MAX_RETRY_COUNT >&2
echo -e '[out] $n='$n' ,$MAX_RETRY_COUNT='$MAX_RETRY_COUNT
   until [ "$n" -ge "$MAX_RETRY_COUNT" ]
   do
   echo -e '$n='$n' ,$MAX_RETRY_COUNT='$MAX_RETRY_COUNT >&2
   echo -e '[out] $n='$n' ,$MAX_RETRY_COUNT='$MAX_RETRY_COUNT
      local buildResults=0;
      echo '>>> Building new image docker build -t="'${APP_NAME}':'${APP_VERSION}'" . >'$BUILD_LOG_FILENAME_AND_PATH' 2>&1'  >&2

      # Build image and capture possible errors
      # --no-cache
      docker build -t="${APP_NAME}:${APP_VERSION}" . >$BUILD_LOG_FILENAME_AND_PATH 2>&1 || buildResults=$?

        if [[ "$buildResults" != "0" ]]; # BUILD FAILED
        then
           if ! grep -q "from driver devicemapper: open" $BUILD_LOG_FILENAME_AND_PATH  && ! grep -q "from driver devicemapper: Error mounting" $BUILD_LOG_FILENAME_AND_PATH ; then # KNOW COMMON ERROR
                echo '[FATAL ERROR] >>> build attempt '${n}' failed, but the error was not a mounting issue'  >&2
                cat $BUILD_LOG_FILENAME_AND_PATH

                exit 1
            else
              n=$[$n+1]
              echo '>>> build attempt '${n}' failed, retrying'  >&2
              sleep 2
           fi

        else # BUILD SUCCESS
         echo '[SUCCESS]  image built successfully !'  >&2
         cat $BUILD_LOG_FILENAME_AND_PATH
         break;
        fi
   done

}
############### BODY

echo '[START] VDM_DEPLOY_SCRIPT_VERSION='$VDM_DEPLOY_SCRIPT_VERSION  >&2
echo '[CHDIR] '$DOCKER_IMAGE_PATH  >&2
cd $DOCKER_IMAGE_PATH

ALREADY_BUILT_COUNTER=$(search_image_and_tag ${APP_NAME} ${APP_VERSION} |wc -l)
echo '$ALREADY_BUILT_COUNTER = '$ALREADY_BUILT_COUNTER  >&2
if [ "$ALREADY_BUILT_COUNTER" -gt "0" ]; then
   echo '[SKIP] image already exists for '${APP_NAME}' '${APP_VERSION}', skipping build'  >&2
else
    build_image $DEFAULT_BUILD_RETRY_ATTEMPT
fi





# build vdm_run command
OPTS_VDM_RUN=""
[[ $DO_RESTART = 1 ]] && OPTS_VDM_RUN=$OPTS_VDM_RUN" -do-restart" || a="$d"
[[ $DO_START -eq "1" ]] && {
echo '[EXECUTING] vdm_run '${OPTS_VDM_RUN}' -name "'${APP_NAME}'" -version "'${APP_VERSION}'" -runParam "'${DOCKER_RUN_PARAMS}'" -timeout "'${STOP_CONTAINER_TIMEOUT_SECONDS}'" -path "'${DOCKER_IMAGE_PATH}'"'  >&2
vdm_run $OPTS_VDM_RUN -name "${APP_NAME}" -version "${APP_VERSION}" -runParam "${DOCKER_RUN_PARAMS}" -timeout "${STOP_CONTAINER_TIMEOUT_SECONDS}" -path "${DOCKER_IMAGE_PATH}"
}
