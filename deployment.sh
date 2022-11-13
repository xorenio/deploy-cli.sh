#!/bin/bash

## author John@xoren.io
## For internal server auto deployment from github containner package
## https://docs.github.com/en/rest/packages










## START - Script setup and configs
# 
#
#
#

## DEFINE SCRIPT VAR AND HELPER FUNCTION 
NOWDATESTAMP=$(date "+%Y-%m-%d_%H-%M-%S")
SCRIPT="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
SCRIPT_DEBUG=false # true AKA echo to console | false echo to log file

DEPLOYMENT_ENV_LOCATION=true
DEPLOYMENT_ENV="production" 
ISOLOCATION="US" ## DEFAULT US


GITHUB_REPO_OWNER="xorenio"
GITHUB_REPO_NAME="twisted-project-zomboid"
GITHUB_REPO_URL="https://api.github.com/repos/$GITHUB_REPO_OWNER/$GITHUB_REPO_NAME/commits"


GITHUB_REPO_PACKAGE_CHECK=false
GITHUB_REPO_PACKAGE_NAME=""
GITHUB_REPO_PACKAGE_URL=https://api.github.com/orgs/$GITHUB_REPO_OWNER/packages/container/$GITHUB_PACKAGE_NAME

# 
#
#
#
## START - Script setup and configs










## START - SCRIPT FUNCTIONS
# 
#
#
#

## LOG FUNCTIONS
logError() {
     STR="[$NOWDATESTAMP][ERROR] $1"
     if [[ $SCRIPT_DEBUG ]]; then
          logConsole "$STR"
          return
     fi
     logToFile "$STR"
     return;
}

logInfo() {
     STR="[$NOWDATESTAMP][INFO] $1"
     if [[ $SCRIPT_DEBUG ]]; then
          logConsole "$STR"
          return
     fi
     logToFile "$STR"
     return;
}

logToFile() {
     if [[ ! -f ~/deployment.log ]]; then
          echo $1  > ~/deployment.log
          return
     fi
     echo $1 >> ~/deployment.log
}

logConsole() {
     echo $1
}


## DEFINE HELPER FUNCTIONS
function isPresent { command -v "$1" &> /dev/null && echo 1; }
function isFileOpen { lsof "$1" &> /dev/null && echo 1; }
function isCron { [ -z "$TERM" ] || [ "$TERM" = "dumb" ] && echo 1; }
# [ -z "$TERM" ] || [ "$TERM" = "dumb" ] && echo 'Crontab' || echo 'Interactive'


## DEFINE HELPER VARS 
SCREEN_IS_PRESENT="$(isPresent screen)"
JQ_IS_PRESENT="$(isPresent jq)"



## LOCATION FUNCTIONS
## ARGE #1 $IP ADDRESS
## EXMAPLE: $ echo valid_ip 192.168.1.1
function valid_ip() {

    local  ip=$1
    local  stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

function set_location_var() {
    
    ## GET PUBLIC IP
    ip=$(curl -s -X GET https://checkip.amazonaws.com)

    ## VAILDATE AND COPY ENV FILE
    if valid_ip ${ip}; then

        ISOLOCATION=$(whois $ip | grep -iE ^country:)
        ISOLOCATION=$( echo $ISOLOCATION | head -n 1 )
        ISOLOCATION=${ISOLOCATION:(-2)}

        DEPLOYMENT_ENV=$ISOLOCATION
    fi
}



## ENV FILE FUNCTIONS
function writeEnvVars() {

    cat > ~/.${GITHUB_REPO_NAME}_vars <<EOF
# This file requests two lines or its doesnt read 
APP_KEY=base64:KvkSbv7pbclGDLINSOlzok2dF4EuPJEamoPKcFPfo3c=
APP_URL=http://api.twisted.bar
CONTACT_EMAIL_TO="admin@twisted.cat"
EOF
    logInfo "Writen env vars file ~/.${GITHUB_REPO_NAME}_vars"
}

function replaceEnvVars() {

    logInfo "START: Replacing APP environment variables"

    ## CHECK IF FILE DOESNT EXIST AND CREATE IT
    if [[ ! -f ~/.${GITHUB_REPO_NAME}_vars ]]; then 
      writeEnvVars
    fi

    ## READ EACH LINE OF CONFIG FILE
    while read CONFIGLINE
    do
        ## GET FOR CHECK FIRST CHAR IN CONFIG LINE
        LINEF=${CONFIGLINE:0:1}

        ## CHECK FIRST LETTER ISN'T # & LINE LETTER LENGTH IS LONGER THEN 3
        if [[ $LINEF != " " && $LINEF != "#" && ${#CONFIGLINE} > 3 ]]; then

            ## CHECK FOR = IN CONFIG LINE SEPERATE IF STATMENT FORMATTED DIFFERENTLY TO WORK
            if echo $CONFIGLINE | grep -F = &>/dev/null;
            then
                CONFIGNAME=$(echo "$CONFIGLINE" | cut -d '=' -f 1)
                CONFIGVALUE=$(echo "$CONFIGLINE" | cut -d '=' -f 2-)
                # echo "CONFIGNAME: $CONFIGNAME"
                # echo "CONFIGVALUE: $CONFIGVALUE"
                # cat .env.production | grep "<$CONFIGNAME>"

                if cat .env.$DEPLOYMENT_ENV | grep "<$CONFIGNAME>" &>/dev/null; then
                    sed -i 's|<'$CONFIGNAME'>|'$CONFIGVALUE'|' .env.$DEPLOYMENT_ENV
                fi

            fi
        fi
    done < ~/.${GITHUB_REPO_NAME}_vars

    ## REPLACED DEPLOYMENT VARS
    sed -i 's|<APP_VERSION>|'$NEW_VERSION'|' .env.$DEPLOYMENT_ENV
    sed -i 's|<APP_UPDATED_AT>|'$NOWDATESTAMP'|' .env.$DEPLOYMENT_ENV

    logInfo "END: Replacing APP environment variables"
}


## PROJECT UPDATE CHECKS FUNCTIONS
function getProjectRemoteVersion() {

    logInfo "Getting remote version"

    if [[ $GITHUB_REPO_PACKAGE_CHECK == true ]]; then

      getProjectVersionViaRepoPackage
    else

      getProjectVersionViaRepo
    fi

    logInfo "Local version: $APP_VERSION"
    logInfo "Github version: $NEW_VERSION"
}

function getProjectVersionViaRepo() {

    ## SEND REQUEST TO GITHUB FOR REPOSOTORY REPO DATA
    logInfo "Sending request to github API for repo data"

    DATA=$( curl -s -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    $GITHUB_REPO_URL)

    logInfo "$(echo $DATA | jq -r .)"

    NEW_VERSION=$(echo $DATA | jq .[0].commit.tree.sha)
}

function getProjectVersionViaRepoPackage() {

    ## SEND REQUEST TO GITHUB FOR REPO PACKAGE DATA
    logInfo "Sending request to github API for package data"

    DATA=$( curl -s -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $GIHHUB_TOKEN" \
    $GITHUB_REPO_PACKAGE_URL)

    logInfo "$(echo $DATA | jq -r .)"

    ## Using {'version_count': 53} as the update indicator
    NEW_VERSION=$(echo $DATA | jq -r .version_count)
}


## APP FOLDER(S)/FILE(S)
function moveGameSaves() {

    logInfo "Moving vendor folder."

    ## IF SCREEN PROGRAM IS INSTALL
    if [[ $SCREEN_IS_PRESENT ]]; then
      
        ## CHECK IF BACKGROUND TASKS ARE STILL RUNNING
        if ! screen -list | grep -q "${GITHUB_REPO_NAME}_deployment_move_saves"; then

            logInfo "Running game saves files moving task in background."

            ## Create screen
            screen -dmS "${GITHUB_REPO_NAME}_deployment_move_saves"

            ## Pipe command to screen 
            screen -S "${GITHUB_REPO_NAME}_deployment_move_saves" -p 0 -X stuff 'cp ~/'${GITHUB_REPO_NAME}'_'${NOWDATESTAMP}'/data/{backups,db,Logs,messaging,Saves,Statistic}/ ~/'${GITHUB_REPO_NAME}'/data/ --update --recursive && exit'$(echo -ne '\015')
            ## Pipe in exit cmd separately to force terminate screen
            # screen -S "${GITHUB_REPO_NAME}_deployment_move_saves" -p 0 -X stuff 'exit '$(echo -ne '\015')

        else # IF SCREEN FOUND

            logError "Task of moving game saves folder in background already running."

            # echo "${BoldText}DEBUG:${NormalText} The $ composer install command to backend is already running" 
        fi
    else ## IF NO SCREEN PROGRAM

        ## Moving files in this process
        logInfo ""
        logInfo "Running game saves files moving task in foreground."
        mv -u -f ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}/valley_saves/ ~/${GITHUB_REPO_NAME}/
        logInfo "Finished moving vendor files."
        logInfo ""
    fi
}


## DOING UPDATE FUNCTION 
function doUpdate() {

    logInfo ""
    logInfo "Re-deployment Started"
    logInfo "====================="
    logInfo ""

    ## ENTER PROJECT REPO DIRECTORY
    cd ~/$GITHUB_REPO_NAME/

    ## STOP DOCKER APP 
    logInfo "Stopping docker containers"

    if [[ -f ~/${GITHUB_REPO_NAME}/docker-compose.$DEPLOYMENT_ENV.yml ]]; then
        docker-compose -f docker-compose.$DEPLOYMENT_ENV.yml down
    else
        docker-compose down
    fi

    ## DELETE PROJECT DOCKER IMAGES
    logInfo "Removing old docker images"
    if [[ -f ~/${GITHUB_REPO_NAME}/docker-compose.$DEPLOYMENT_ENV.yml ]]; then
        yes | docker-compose -f docker-compose.$DEPLOYMENT_ENV.yml rm #--all # dep
    else
        yes | docker-compose rm #--all # dep
    fi

    yes | docker image rm danixu86/project-zomboid-dedicated-server:latest


    ## LEAVE DIRECTORY
    logInfo "Moved old project folder to ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}"
    cd ~/
    ## MOVE AKA RENAME DIRECTORY
    mv ~/$GITHUB_REPO_NAME/ ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}

    ## GIT CLONE FROM GITHUB
    logInfo "Cloned fresh copy from github $GITHUB_REPO_OWNER/${GITHUB_REPO_NAME}"
    git clone git@github.com:$GITHUB_REPO_OWNER/$GITHUB_REPO_NAME.git

    ## FIX FOR INODE CHANGES
    logInfo "Inode sync"
    sync
    sleep 2s

    ## ENTER NEWLY CLONED LOCAL PROJECT REPO
    cd ~/${GITHUB_REPO_NAME}

    logInfo "Moving project secrets in to env file"
    replaceEnvVars
    
    logInfo "Moving game saves"
    moveGameSaves
    # cp ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}/data/{backups,db,Logs,messaging,Saves,Statistic,scripts}/ ~/${GITHUB_REPO_NAME}/data/ --update --recursive
    #cp ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}/data/db/ ~/${GITHUB_REPO_NAME}/data/ --update --recursive
    #cp ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}/data/Logs/ ~/${GITHUB_REPO_NAME}/data/ --update --recursive
    #cp ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}/data/messaging/ ~/${GITHUB_REPO_NAME}/data/ --update --recursive
    #cp ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}/data/Saves/ ~/${GITHUB_REPO_NAME}/data/ --update --recursive
    #cp ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}/data/Statistic/ ~/${GITHUB_REPO_NAME}/data/ --update --recursive
    #cp ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}/mods/ ~/${GITHUB_REPO_NAME}/mods/ --update --recursive
    #cp ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}/scripts/ ~/${GITHUB_REPO_NAME}/ --update --recursive
    #cp ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP}/workshop-mods/ ~/${GITHUB_REPO_NAME}/ --update --recursive

    if [[ $SCREEN_IS_PRESENT ]]; then
       while screen -list | grep -q "${GITHUB_REPO_NAME}_deployment_move_saves"; do
           sleep 3
       done
    fi
    if [[ -f ~/${GITHUB_REPO_NAME}/docker-compose.$DEPLOYMENT_ENV.yml ]]; then
        docker-compose -f docker-compose.$DEPLOYMENT_ENV.yml build
        docker-compose -f docker-compose.$DEPLOYMENT_ENV.yml up -d
    else
        docker-compose build
        docker-compose up -d
    fi
}


## AFTER RUN CLEANUP
function deleteOldProjectFiles() {

     OLD_PROJECT_BYTE_SIZE=$(du ~/${GITHUB_REPO_NAME}_${NOWDATESTAMP} -sc | grep total)

     SPACESTR=" "
     EMPTYSTR=""
     TOTALSTR="total"

     SIZE=${SIZE/$SPACESTR/$EMPTYSTR}

     SIZE=${SIZE/$TOTALSTR/$EMPTYSTR}

     if [[ $SIZE -le 1175400 ]]; then
          rm -R

     fi
}

## DELETE RUNNING FILE 
function deleteRunningFile() {
    ## DELETE THE RUNNING FILE
    if [[ -f ~/deployment_running.txt ]]; then
      rm ~/deployment_running.txt
    fi
}
# 
#
#
#
## END - SCRIPT FUNCTIONS









## START - SCRIPT PRE-CONFIGURE
# 
#
#
#

## SET LOGGING TO TTY OR TO deployment.log
if [[ isCron ]]; then
    SCRIPT_DEBUG=false
else
    SCRIPT_DEBUG=true
fi


## CHECK IF SCRIPT IS ALREADY RUNNING
if [[ -f ~/deployment_running.txt ]]; then
    logInfo "Script already running."
    exit
fi


## CHECK IF BACKGROUND TASKS ARE STILL RUNNING
if [[ $SCREEN_IS_PRESENT ]]; then
    if screen -list | grep -q "${GITHUB_REPO_NAME}_deployment_move_saves"; then
          logError "${GITHUB_REPO_NAME}_deployment_move_saves screen still running."
          exit;
    fi
fi


## SAYING SOMETHING
logInfo ""
logInfo "Starting deployment update check."


## ECHO STARTTIME TO DEPLOYMENT LOG FILE
echo ${NOWDATESTAMP} > ~/deployment_running.txt


## ENTER PROJECT DIRECTORY
cd ~/$GITHUB_REPO_NAME/


## CHECK FOR GITHUB TOKEN
if [[ ! -f ~/.github_token ]]; then

    logError ""
    logError "Failed deployment ${NOWDATESTAMP}"
    logError ""
    logError "Missing github token file .github_token"
    logError "GIHHUB_TOKEN=ghp_####################################"
    logError "public_repo, read:packages, repo:status, repo_deployment"
    exit 1;
fi


## CHECK FOR PROJECT VAR FILE
if [[ ! -f ~/.${GITHUB_REPO_NAME}_vars ]]; then

    logError ""
    logError "Failed deployment ${NOWDATESTAMP}"
    logError ""
    logError "Missing twisted var file ~/.${GITHUB_REPO_NAME}_vars"

    exit 1;
fi

## SET DEPLOY ENV VAR TO LOCATION
if [[ $DEPLOYMENT_ENV_LOCATION ]]; then
    set_location_var
    DEPLOYMENT_ENV=$ISOLOCATION
fi

## CHECK .env FILE
if [[ ! -f ~/$GITHUB_REPO_NAME/.env ]]; then

    cp ~/$GITHUB_REPO_NAME/.env.$DEPLOYMENT_ENV ~/$GITHUB_REPO_NAME/.env
fi

## LOAD .env VARS and GITHUB TOKEN AND SECRETS
logInfo "Loading .env & github var"
source ~/$GITHUB_REPO_NAME/.env
source ~/.github_token
## SECRETS
source ~/.${GITHUB_REPO_NAME}_vars

#
#
#
#
### END - SCRIPT PRE-CONFIGURE










### START - SCRIPT RUNTIME
# 
#
#
#

if [[ $# -eq 1 ]]; then
    logInfo ""
    logInfo "================================="
    logInfo "\/ Manually re-install started \/"
    logInfo "================================="
    doUpdate
    deleteRunningFile
    exit
fi

getProjectRemoteVersion

## CHECK FOR DEFAULT VARS
if [[ $APP_VERSION == "<APP_VERSION>" ]]; then

    ## replace with requested data version
    logError "Current version <APP_VERSION> AKA deployment failure somewhere"
    sed -i 's|<APP_VERSION>|'$NEW_VERSION'|' ~/$GITHUB_REPO_NAME/.env
else

    ## IF LOCAL VERSION AND REMOTE VERSION ARE THE SAME 
    if [[ $APP_VERSION == $NEW_VERSION ]]; then

        logInfo "VERSION MATCH"

        deleteRunningFile

        logInfo "Finished deployment update check."
        exit;
    fi
    doUpdate
fi


logInfo "Delete the running file"


deleteRunningFile


## TELL USER 
logInfo "Finished deployment update check."

exit 0;

# 
#
#
#
# END - SCRIPT RUNTIME
