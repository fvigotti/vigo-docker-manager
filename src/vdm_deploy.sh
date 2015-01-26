#!/usr/bin/env bash
set -e

echo -e '[ VIGO DOCKER MANAGER >>>> deploy ]'  >&2

TAIL_DOCKERPS_HEADER="tail -n +2"

BASE_VDM_IMAGES_PATH="/opt/docker_images/"

print_usage ()
{
echo -e 'usage = \n'$0' [--do-rebuild]  -name APPNAME -version VERSION -path DOCKERFILEPATH\n\nExample:\n'$0' -name myapp -version 1.12 -runParam "-p 443:443 -p 80:80 -p 5922:22 -d" -timeout 10 -path="/opt/apptest/"'  >&2
}


#DOCKER_IMG_NAME="t1_app1"
#DOCKER_IMG_VERSION="v1.3"
#
#DOCKER_IMG_NAME=$1
#DOCKER_IMG_VERSION=$2
#DOCKER_BUILD_PARAMS=$3
# return image-sources-path ie: /opt/docker_images/testbashloop/1.1/src
get_vdm_images_src_path (){
local IMAGE_BASE_NAME=$1
local IMAGE_TAG=$2
echo ${BASE_VDM_IMAGES_PATH}''${IMAGE_BASE_NAME}'/'${IMAGE_TAG}'/src/'
}

clean_special_chars() {
    local a=${1//[^[:alnum:]]/}
    echo "${a,,}"
}

# DEFAULTS
VDM_DEPLOY_SCRIPT_VERSION=1
BUILD_RETRY_ATTEMPT=10 #this is necessary because devicemapper occasionally fails to mount images during build process
STOP_CONTAINER_TIMEOUT_SECONDS=10
CLEAN_GARBAGE=0
DO_START=1
IMAGES_HISTORY_PRESERVE_COUNT=3

# vmd_deploy -name "dumbscript1" -version "v1.6" -runParam "-d -P" -timeout 10 -path "/opt/docker_dumbscr1/"
# PARSE ARGS
while [[ $# > 0 ]]
do
key="$1"

case $key in
    --img-name)
    DOCKER_IMG_NAME="$2"
    shift
    ;;
    --img-version)
    DOCKER_IMG_VERSION="$2"
    shift
    ;;
    -path|--path)
    DOCKER_IMAGE_PATH="$2"
    shift
    ;;
    --build-params) #optional
    DOCKER_BUILD_PARAMS="$2"
    shift
    ;;
    -timeout|--timeout) #optional
    STOP_CONTAINER_TIMEOUT_SECONDS="$2"
    shift
    ;;
    --history-images-preserve-count) #optional
    IMAGES_HISTORY_PRESERVE_COUNT="$2"
    shift
    ;;
    --clean-garbage) #optional
    CLEAN_GARBAGE=1
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

DOCKER_IMAGE_NAME_AND_VERSION=${DOCKER_IMG_NAME}":"${DOCKER_IMG_VERSION}

CURPATH=$(pwd)
CUR_EPOCH=$(date +%s)

echo 'CURPATH = '${CURPATH}\
' , DOCKER_IMAGE_PATH='${DOCKER_IMAGE_PATH}\
' , DOCKER_IMG_NAME='${DOCKER_IMG_NAME}\
', DOCKER_IMG_VERSION = '${DOCKER_IMG_VERSION}\
' , DOCKER_BUILD_PARAMS = '${DOCKER_BUILD_PARAMS}\
' , STOP_CONTAINER_TIMEOUT_SECONDS = '${STOP_CONTAINER_TIMEOUT_SECONDS}\
' , CUR_EPOCH = '${CUR_EPOCH}  >&2

if [ -z "$DOCKER_IMG_NAME" ] || ! [[ "$DOCKER_IMG_NAME" =~ ^(.+)$ ]]; then
 echo -e 'invalid DOCKER_IMG_NAME : '$DOCKER_IMG_NAME'' >&2
     print_usage
    exit -1
fi

if [ -z "$DOCKER_IMG_VERSION" ] || ! [[ "$DOCKER_IMG_VERSION" =~ ^([0-9\.]+)$ ]]; then
 echo -e 'invalid DOCKER_IMG_VERSION :'$DOCKER_IMG_VERSION'' >&2
    print_usage
    exit -1
fi



[ -z "$DOCKER_IMAGE_PATH" ] && {
    DOCKER_IMAGE_PATH=$( get_vdm_images_src_path $DOCKER_IMG_NAME $DOCKER_IMG_VERSION )
    echo 'docker-image-soruces path defaulted to :'${DOCKER_IMAGE_PATH} >&2
}

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
 docker images  | awk '$1 ~ "'${DOCKER_IMG_NAME}'" {print $0}' | sort --ignore-leading-blanks --version-sort -k2 -r
}

get_stopped_containers_ids_for_image_id () {
if [ -z "$1" ] || ! [[ "$1" =~ ^[0-9a-f]+$ ]]; then
 echo -e 'invalid image id : '$1' ' >&2
 exit -1
fi
docker ps -a --filter "status=exited" \
| $TAIL_DOCKERPS_HEADER \
| awk '$2 ~ "'$1'" {print $1}'

}

get_stopped_containers_for_image_name () {
if [ -z "$1" ] || ! [[ "$1" =~ ^(.+):(.+)$ ]]; then
 echo -e 'param missing image NAME:TAG is required, with the colon to separate tag name! given : '$1' ' >&2
 exit -1
fi
docker ps -a --filter "status=exited" \
| $TAIL_DOCKERPS_HEADER \
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

    get_sorted_images | $TAIL_DOCKERPS_HEADER | tail -n +"${ROLLBACK_IMAGES_TO_KEEP}" | awk '{print $1":"$2}'
}

remove_oldest_images () {
    local PRESERVE_COUNT=$1
    sync
    echo -e '>>> deleting stopped container for deprecated images  preserving '${PRESERVE_COUNT}' images in history'  >&2
    #docker ps -a | awk '$2 ~ "a:3" {print $0}'
    get_deprecated_oldest_images_name_and_tag ${PRESERVE_COUNT} \
    | while read -r imageIdToRemove; do

        local IMAGE_TO_REMOVE_IS_CURRENTLY_RUNNING_count=$(get_running_containers_for_image ${imageIdToRemove} "0" |wc -l)
        echo '$IMAGE_TO_REMOVE_IS_CURRENTLY_RUNNING_count = '$IMAGE_TO_REMOVE_IS_CURRENTLY_RUNNING_count  >&2

        # if image container currently running
        if [ "$IMAGE_TO_REMOVE_IS_CURRENTLY_RUNNING_count" -gt "0" ]; then

            echo '$IMAGE_TO_REMOVE_IS_CURRENTLY_RUNNING_count (list version)= '$(get_running_containers_for_image ${imageIdToRemove} "0" )  >&2

            # if restart has been requested, stop the running container
            echo '[WARNING] skip deletion of deprecated image: '${imageIdToRemove} ' because running'  >&2
            continue #skip this image
            echo '[FATAL ERROR ] POST CONTINNUE MESSAGE'  >&2
        fi

        echo -e 'remove_stopped_containers_for_image '$imageIdToRemove ;  >&2
        remove_stopped_containers_for_image $imageIdToRemove ;
        echo -e '[DELETE-DEPRECATED-IMAGE] deleting '$imageIdToRemove' image'  >&2;
        docker rmi $imageIdToRemove ;
        done

    sync
}

# deletes docker-images that have "<none>" as assigned name (usually interrupted build processes or cached intermediate containers )
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
echo 'building image, MAX_RETRY_COUNT='$MAX_RETRY_COUNT >&2
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
remove_oldest_images $IMAGES_HISTORY_PRESERVE_COUNT
sync


local BUILD_LOG_FILENAME='vdm_build_'${DOCKER_IMG_NAME}':'${DOCKER_IMG_VERSION}'.log'

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
      echo '>>> Building new image docker build  '${DOCKER_BUILD_PARAMS}' -t="'${DOCKER_IMG_NAME}':'${DOCKER_IMG_VERSION}'" . >'$BUILD_LOG_FILENAME_AND_PATH' 2>&1'  >&2

      # Build image and capture possible errors
      # --no-cache
      docker build ${DOCKER_BUILD_PARAMS} -t="${DOCKER_IMG_NAME}:${DOCKER_IMG_VERSION}" . >$BUILD_LOG_FILENAME_AND_PATH 2>&1 || buildResults=$?

        if [[ "$buildResults" != "0" ]]; then # BUILD FAILED
            # if it's not the bug of devicemapper-mount-fail
           if ! grep -q "from driver devicemapper: open" $BUILD_LOG_FILENAME_AND_PATH  && ! grep -q "from driver devicemapper: Error mounting" $BUILD_LOG_FILENAME_AND_PATH ; then
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

} # build_image



############### BODY

echo '[START] VDM_DEPLOY_SCRIPT_VERSION='$VDM_DEPLOY_SCRIPT_VERSION  >&2
echo '[CHDIR] '$DOCKER_IMAGE_PATH  >&2
cd $DOCKER_IMAGE_PATH

ALREADY_BUILT_COUNTER=$( search_image_and_tag ${DOCKER_IMG_NAME} ${DOCKER_IMG_VERSION} | wc -l )
echo '$ALREADY_BUILT_COUNTER = '$ALREADY_BUILT_COUNTER  >&2
if [ "$ALREADY_BUILT_COUNTER" -gt "0" ]; then
   echo '[SKIP] image already exists for '${DOCKER_IMG_NAME}' '${DOCKER_IMG_VERSION}', skipping build'  >&2
else
    build_image $BUILD_RETRY_ATTEMPT
fi

