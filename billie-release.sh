#!/usr/bin/env bash

function verify_if_release_image_exists() {
    local release_image=$1
    if [ ! "$(podman manifest inspect ${release_image})" ]; then
        echo "Cannot download image ${release_image}"
    fi
}

function clone_agent_repo() {
    
    local commit=$1

    if [[ ! -d "installer" ]]; then 
        git clone https://github.com/openshift/installer.git
    fi
    
    if [[ ! -z "${commit}" ]]; then
        echo "Building from commit $commit"
    fi

    pushd installer
    git checkout $commit
    popd
}

function build_agent_installer() {
    pushd installer
    # Steve
    export GOCACHE=/tmp/.cache/go-build
    hack/build.sh
    cp bin/openshift-install ..
    popd
}

function patch_openshift_install_release_version() {
    local version=$1

    local res=$(grep -oba ._RELEASE_VERSION_LOCATION_.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX openshift-install)
    local location=${res%%:*}

    # If the release marker was found then it means that the version is missing
    if [[ ! -z ${location} ]]; then
        echo "Patching openshift-install with version ${version}"
        printf "${version}\0" | dd of=openshift-install bs=1 seek=${location} conv=notrunc &> /dev/null 
    else
        echo "Version already patched"
    fi
}

function patch_openshift_install_release_image() {
    local image=$1

    local res=$(grep -oba ._RELEASE_IMAGE_LOCATION_.XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX openshift-install)
    local location=${res%%:*}

    # If the release marker was found then it means that the image is missing
    if [[ ! -z ${location} ]]; then
        echo "Patching openshift-install with image ${image}"
        printf "${image}\0" | dd of=openshift-install bs=1 seek=${location} conv=notrunc &> /dev/null 
    else
    	local res=$(grep -oba bastion.lan:8443/steve openshift-install)
    	local location=${res%%:*}
    	if [[ ! -z ${location} ]]; then
        	echo "Patching openshift-install with image ${image}"
        	printf "${image}\0" | dd of=openshift-install bs=1 seek=${location} conv=notrunc &> /dev/null 
    	else
       		echo "Image already patched"
	fi
    fi
}

function complete_release() {
    echo 
    echo "BILLI installer release completed"
    echo 

    ./openshift-install version
}

if [ "$#" -ne 3 ]; then
    echo "Usage: billi-release2.sh <release image>"
    echo "[Arguments]"
    echo "      <commit>            Commit, e.g. 'agent-installer'"
    echo "      <release image>     The desired OpenShift release image location/url"
    echo "      <version>           The desired OpenShift version, e.g. 4.11.5"
    echo
    echo "example: ./billi-release.sh quay.io/openshift-release-dev/ocp-release@sha256:300bce8246cf880e792e106607925de0a404484637627edf5f517375517d54a4"

    exit 1
fi

commit=$1
release_image=$2
release_version=$3

verify_if_release_image_exists $release_image
clone_agent_repo $commit
build_agent_installer
patch_openshift_install_release_version $release_version
patch_openshift_install_release_image $release_image
complete_release

