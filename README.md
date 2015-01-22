# incomplete documentation... and very incomplete scripts (even if working on my current usecase)

# vigo-docker-manager
bash scripts to manage docker images and containers

# installation  
the provided `install.sh` script will only copy `./src/*` in
the default program destination `/opt/vdm/`, if it already exists
the program will exit with error, after copying the install script also try to link
app scripts to /bin directory , if destination already exists and are links they will be overridden


# vdm_deploy

build an image from a local path, and call vmd_run to start the container after the build 
the script also perform multiple (10) attempts if the docker-bug-mount-device-mapper occur
 

**--img-name $name**    
 name of the docker-image that is being built  

**--img-version $version**  
value must be a valid number (will be checked by a regexp)  
Version of the docker image that is being built (version will be used as docker image tag )  
ie: ` -version "1.12"  


**--build-params  "$params"**  *[optional]*  
  -> additional build params

**-timeout $seconds**  
 timeout value in seconds for docker stop (in case of docker stop command is used by restart action)  

**-path**  *[optional]*  
 path of the dockerfile to build image from (if not specified will default to : /opt/docker_images/$imagename/$version/src )  

**--build-only** *[optional]*  
 do not try to start the image after the build   

**--history-images-preserve-count** *[optional]*  
 amount of docker-images to preserve as history, those images can be usefull to start already previous compiled version  


### ie:
`
vdm_deploy -do-restart -name "{{ dumbscript1_appname }}" -version "{{ dumbscript1_version | mandatory }}" -runParam "-d -p 8080:2812 " -timeout "10" -path "{{ dumbscript1_docker_imagepath }}/"
`


# vdm_run    
stop previous version of the image-name running (if restart param is provided, else will fail to run) and execute docker run with given params using previously built image-name and version,
 generating app name, and saving the command execution param into an image-name-and-version script
 stored in `path/log` directory, this allow the re-execution of a specific version of the container with specific param used to run that version
 , perform multiple attempt to start the container and logs attempt results in `path/log/`  
 -d option for docker run is always implicit 

**--img-name $name**  
 the docker image name that must be run , this will be combined with version to provided the full image:tag name   

**--img-version $version** *[optional]*  
 -> if not provided will default to latest built image version (using sort params : "sort --ignore-leading-blanks --version-sort -k2 -r" )  
 
**--run-params "$params"**  *[optional]*  
  -> additional run params

**-timeout $seconds **  *[optional]*  
  -> timeout used in case of restart is required 

**--destroy-previous-container** *[optional]*  
 destroy previous container if exists (contrarily it will simply restart it using "docker start" )    

**--no-log** *[optional]*  
 do not log the execution   

**--no-detach** *[optional]*  
 do not add "-d" to docker run    

**--container-name $name**  *[optional]*  
 name of the container, default=image name without special chars (which are not allowed) 

# todo:
refresh public registry hub cache before deploy  
(docker pull $imagename )  
repristinate old-image purge section  
add caching control options (forcing no-cache)     
