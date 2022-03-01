#!/bin/bash

cd $(dirname $0)

ROOT_DIR=${PWD}
GIT_DIR=${ROOT_DIR}/git
BACKEND_DIR=${GIT_DIR}/adc-broker-backend
FRONTEND_DIR=${GIT_DIR}/adc-broker-frontend

BACKEND_GIT_URL="https://github.com/eurocontrol-swim/adc-broker-backend.git"
BACKEND_GIT_BRANCH="develop"
FRONTEND_GIT_URL="https://github.com/eurocontrol-swim/adc-broker-frontend.git"
FRONTEND_GIT_BRANCH="develop"

CERTS_DIR=${BACKEND_DIR}/certificates/certs

function error
# $1 message
# $2 code
{
    local code=1

    if [[ -n "$2" ]]
    then
        local code=$2
    fi

    echo "Error : $1" 1>&2
    echo "Exiting($code)..." 1>&2
    exit $code
}

function install
{
    yum -y install docker || error "Failed to install docker"

    local error_message="Failed to configure docker access"

    sudo groupadd docker || error ${error_message}
    sudo usermod -aG docker $USER || error ${error_message}
    newgrp docker || error ${error_message}
}

function prepare_repos
{
    echo "Preparing Git repositories..."
    echo "============================="
    echo

    [[ -d ${GIT_DIR} ]] || mkdir ${GIT_DIR} || error "Failed to create dir ${GIT_DIR}"

    cd ${GIT_DIR}

    echo -n "Preparing backend..."

    if [[ -d ${BACKEND_DIR} ]]
    then
        cd "${BACKEND_DIR}" || exit
        git pull -q --rebase origin ${BACKEND_GIT_BRANCH} || exit
    else
        git clone -q --branch ${BACKEND_GIT_BRANCH} ${BACKEND_GIT_URL} "${BACKEND_DIR}"
    fi
    echo "OK"

    echo -n "Preparing frontend..."

    if [[ -d ${FRONTEND_DIR} ]]
    then
        cd "${FRONTEND_DIR}" || exit
        git pull -q --rebase origin ${FRONTEND_GIT_BRANCH} || exit
    else
        git clone -q --branch ${FRONTEND_GIT_BRANCH} ${FRONTEND_GIT_URL} "${FRONTEND_DIR}"
    fi
    echo "OK"

    echo -e "\n\n"
}

function status
{
    docker ps
}

function start_services
{
    echo "Starting up ADC BROKER..."
    echo "=========================="
    echo

    if [[ "$1" == "--detached" ]]
    then
        local options="-d"
    fi

    docker-compose up $options
    echo
}

function stop_services_with_clean
{
    echo "Stopping ADC BROKER..."
    echo "======================"
    echo
    docker-compose down
    echo
}

function stop_services_with_purge
{
    stop_services_with_clean &&
    docker volume ls -q | grep adc-broker | xargs -r docker volume rm

    echo
}

function stop_services
{
    echo "Stopping ADC BROKER..."
    echo "======================"
    echo
    docker-compose stop
    echo
}

function build
{   
    echo "Removing old data..."
    echo "===================="
    echo
    # Remove existing volumes
    docker volume ls -q | grep angular_build | xargs -r docker volume rm || error "Failed to remove old data"
    echo

    echo "Building images..."
    echo "=================="
    echo
    # Build the rest of the images
    docker-compose build --force-rm || error "Failed to build images"
    echo

    echo "Removing obsolete docker images..."
    echo "=================================="
    echo
    docker images | grep none | awk '{print $3}' | xargs -r docker rmi

    echo
}

function create_nginx_https_certificate
{
    echo "Creating self-signed certificate for NGINX..."
    echo "============================================="
    echo

    if [[ -f ${ROOT_DIR}/nginx/ssl/adc-broker-nginx-certificate.pem ]]
    then
        echo "Certificate is already present"
    else
        echo "Creating a certificate for HTTPS support (valid for 365 days)"
        mkdir -p ${ROOT_DIR}/nginx/ssl || error "Failed to create https certificates directory"
        openssl ecparam -genkey -name secp384r1 -out ${ROOT_DIR}/nginx/ssl/adc-broker-nginx-key.pem
        openssl req -new -sha256 -key ${ROOT_DIR}/nginx/ssl/adc-broker-nginx-key.pem -out ${ROOT_DIR}/nginx/ssl/adc-broker-nginx.csr -subj /CN=adc-frontend #-config adc-frontend-openssl.conf
        openssl req -x509 -sha256 -days 365 -key ${ROOT_DIR}/nginx/ssl/adc-broker-nginx-key.pem -in ${ROOT_DIR}/nginx/ssl/adc-broker-nginx.csr -out ${ROOT_DIR}/nginx/ssl/adc-broker-nginx-certificate.pem
        openssl req -in ${ROOT_DIR}/nginx/ssl/adc-broker-nginx.csr -text -noout | grep -i "Signature.*SHA256" && echo "All is well"
    fi

    if [[ -f ${ROOT_DIR}/nginx/ssl/dhparam.pem ]]
    then
        echo "Strong Diffie-Hellman group is already present"
    else
        echo "Creating a 4096 bits Diffie-Hellman group, which is used for https negotiation with clients." 
        mkdir -p ${ROOT_DIR}/nginx/ssl || error "Failed to create https certificates directory"
        openssl dhparam -out ${ROOT_DIR}/nginx/ssl/dhparam.pem 4096 || error "Failed to create Diffie-Hellman group"
    fi

    echo
}

function create_certificates
{
    echo "Creating certificates..."
    echo "========================"
    echo

    if [[ -d ${CERTS_DIR} ]]
    then
        echo "Nothing to do"
    else
        mkdir ${CERTS_DIR} || error "Failed to create certificates directory"
        ${BACKEND_DIR}/certificates/createCertificates.sh ${CERTS_DIR} || error "Failed to create certificates"
    fi

    echo
}

function usage
{
    echo "Usage: adc_broker.sh [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "    install                 Install all the needed packages for the ADC broker"
    echo "    build                   Clones/updates the necessary git repositories and builds the involved docker images"
    echo "    build --purge           Stops all the services and cleans up the containers and the volumes then clones/updates the necessary git repositories and builds the involved docker images"
    echo "    start                   Starts up all the services"
    echo "    start --detached        Starts up all the services detached"
    echo "    stop                    Stops all the services"
    echo "    stop --clean            Stops all the services and cleans up the containers"
    echo "    stop --purge            Stops all the services and cleans up the containers and the volumes"
    echo "    status                  Displays the status of the running containers"
    echo
}

ACTION=${1}

case ${ACTION} in
  install)
    install
    ;;
  build)
    if [[ "$2" == "--purge" ]]
    then
      stop_services_with_purge
    fi

    # update the repos if they exits othewise clone them
    prepare_repos

    # generate self-signed certificate for NGINX
    create_nginx_https_certificate

    create_certificates

    # build the images
    build
    ;;
  start)
    start_services ${2}
    ;;
  stop)
    if [[ -n ${2} ]]
    then
      EXTRA=${2}

      case ${EXTRA} in
          --clean)
            stop_services_with_clean
            ;;
          --purge)
            stop_services_with_purge
            ;;
          *)
            echo -e "Invalid argument\n"
            usage
            ;;
        esac
    else
      stop_services
    fi
    ;;
  status)
    status
    ;;
  help)
    usage
    ;;
  *)
    echo -e "Invalid action\n"
    usage
    ;;
esac
