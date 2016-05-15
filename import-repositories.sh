#!/bin/bash
set -eux

domain=$(hostname --fqdn)

function psql {
    sudo -sHu gitlab-psql \
        /opt/gitlab/embedded/bin/psql \
        -h /var/opt/gitlab/postgresql \
        -d gitlabhq_production \
        "$@"
}

privateToken=$(psql -t -c 'select authentication_token from users where id=1')

function gitlab-api {
    local method=$1; shift
    local path=$1; shift
    http \
        --verbose \
        --check-status \
        --ignore-stdin \
        $method \
        "https://$domain/api/v3$path" \
        "PRIVATE-TOKEN:$privateToken" \
        "$@"
}

# creates a new GitLab project from an existing git repository.
# NB GitLab CE does not support mirroring a git repository.
function gitlab-create-project-and-import {
    local sourceGitUrl=$1
    local destinationProjectName=$2

    gitlab-api POST /projects name=$destinationProjectName public:=true

    /opt/gitlab/embedded/bin/git \
        clone --mirror \
        $sourceGitUrl \
        $destinationProjectName

    pushd $destinationProjectName
    /opt/gitlab/embedded/bin/git \
        push --mirror \
        git@$domain:root/$destinationProjectName.git
    popd

    rm -rf $destinationProjectName
}

# generate a new ssh key for the current user account and add it to gitlab.
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -f ~/.ssh/id_rsa -t rsa -b 2048 -C "$USER@$domain" -N ''
    gitlab-api POST /user/keys "title=$USER@$domain" key=@~/.ssh/id_rsa.pub
fi

# trust our own SSH server.
if [ -z "$(ssh-keygen -F $domain 2>/dev/null)" ]; then
    ssh-keyscan -H $domain >> ~/.ssh/known_hosts
fi

# import some existing git repositories.
gitlab-create-project-and-import https://github.com/rgl/gogs-vagrant.git gogs-vagrant
gitlab-create-project-and-import https://github.com/rgl/gitlab-vagrant.git gitlab-vagrant
gitlab-create-project-and-import https://github.com/rgl/ubuntu-vagrant.git ubuntu-vagrant
gitlab-create-project-and-import https://github.com/rgl/windows-domain-controller-vagrant.git windows-domain-controller-vagrant
gitlab-create-project-and-import https://github.com/rgl/selenium-server-windows-vagrant.git selenium-server-windows-vagrant
gitlab-create-project-and-import https://github.com/jkbrzt/httpie.git httpie
gitlab-create-project-and-import https://github.com/xenolf/lego lego
# NB we cannot import the certbot nor the boulder repository due to:
#   remote: GitLab: An unexpected error occurred (redis-cli returned 127).
# this seems to be a known problem (too many branches or tags).
# see https://gitlab.com/gitlab-org/gitlab-shell/issues/10
#gitlab-create-project-and-import https://github.com/certbot/certbot certbot
#gitlab-create-project-and-import https://github.com/letsencrypt/boulder.git boulder
# NB we cannot use the go repository, as it fails pushing to gitlab with things like:
#   ! [remote rejected] master -> master (pre-receive hook declined)
#   ! [remote rejected] weekly.2012-03-27 -> weekly.2012-03-27 (pre-receive hook declined)
#   ! [remote rejected] refs/users/00/5200/edit-1865/1 -> refs/users/00/5200/edit-1865/1 (pre-receive hook declined)
#gitlab-create-project-and-import https://github.com/golang/go.git go
# NB we cannot use the vagrant repository, as it fails pushing to gitlab with:
#   remote: error: object 3fb9bf325c24a1658261a6cf5e670d5b7d81119b: zeroPaddedFilemode: contains zero-padded file modes
#   remote: fatal: Error in object
#   error: pack-objects died of signal 13
#gitlab-create-project-and-import https://github.com/mitchellh/vagrant.git vagrant
