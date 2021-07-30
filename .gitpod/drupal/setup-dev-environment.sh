#!/usr/bin/env bash
if [ -n "$DEBUG_DRUPALPOD" ]; then
    set -x
fi

# Check if workspace already initiated, to avoid overriding existing work in progress
if [ ! -f /workspace/drupalpod_initiated.status ]; then
    # Add git.drupal.org to known_hosts
    mkdir -p ~/.ssh
    host=git.drupal.org
    SSHKey=$(ssh-keyscan $host 2> /dev/null)
    echo "$SSHKey" >> ~/.ssh/known_hosts

    # Default settings (latest drupal core)
    if [ -z "$DP_PROJECT_TYPE" ]; then
        DP_PROJECT_TYPE=project_core
    fi

    if [ -z "$DP_PROJECT_NAME" ]; then
        DP_PROJECT_NAME=drupal
    fi

    # Clone project (only if it's not core)
    if [ -n "$DP_PROJECT_NAME" ] && [ "$DP_PROJECT_TYPE" != "project_core" ]; then
        mkdir -p "${GITPOD_REPO_ROOT}"/repos
        cd "${GITPOD_REPO_ROOT}"/repos && git clone https://git.drupalcode.org/project/"$DP_PROJECT_NAME"
    fi

    WORK_DIR="${GITPOD_REPO_ROOT}"/repos/$DP_PROJECT_NAME

    # Dynamically generate .gitmodules file
cat <<GITMODULESEND > "${GITPOD_REPO_ROOT}"/.gitmodules
# This file was dynamically generated by a script
[submodule "$DP_PROJECT_NAME"]
    path = repos/$DP_PROJECT_NAME
    url = https://git.drupalcode.org/project/$DP_PROJECT_NAME.git
    ignore = dirty
GITMODULESEND

    # Ignore specific directories during Drupal core development
    cp "${GITPOD_REPO_ROOT}"/.gitpod/drupal/git-exclude.template "${GITPOD_REPO_ROOT}"/.git/info/exclude
    cp "${GITPOD_REPO_ROOT}"/.gitpod/drupal/git-exclude.template "${GITPOD_REPO_ROOT}"/repos/drupal/.git/info/exclude
    # Stop tracking local changes of composer.json
    cd "${GITPOD_REPO_ROOT}" && git update-index --skip-worktree composer.json

    # Checkout specific branch only if there's issue_fork
    if [ -n "$DP_ISSUE_FORK" ]; then
        # If branch already exist only run checkout,
        if cd "${WORK_DIR}" && git show-ref -q --heads "$DP_ISSUE_BRANCH"; then
            cd "${WORK_DIR}" && git checkout "$DP_ISSUE_BRANCH"
        else
            cd "${WORK_DIR}" && git remote add "$DP_ISSUE_FORK" https://git.drupalcode.org/issue/"$DP_ISSUE_FORK".git
            cd "${WORK_DIR}" && git fetch "$DP_ISSUE_FORK"
            cd "${WORK_DIR}" && git checkout -b "$DP_ISSUE_BRANCH" --track "$DP_ISSUE_FORK"/"$DP_ISSUE_BRANCH"
        fi
    elif [ -n "$DP_MODULE_VERSION" ]; then
        cd "${WORK_DIR}" && git checkout "$DP_MODULE_VERSION"
    fi

    # Start ddev
    ddev start

    # If project type is NOT core, change Drupal core version
    if [ "$DP_PROJECT_TYPE" != "project_core" ]; then
        # Add project source code as symlink (to repos/name_of_project)
        cd "${GITPOD_REPO_ROOT}" && composer config repositories."$DP_PROJECT_NAME" '{"type": "path", "url": "'"repos/$DP_PROJECT_NAME"'", "options": {"symlink": true}}'
        # Get all dependencies of the project
        cd "${GITPOD_REPO_ROOT}" && ddev composer require drupal/"$DP_PROJECT_NAME":\"*\"
    else
        cd "${GITPOD_REPO_ROOT}" && ddev composer install
    fi

    if [ -n "$DP_PATCH_FILE" ]; then
        echo Applying selected patch "$DP_PATCH_FILE"
        cd "${WORK_DIR}" && curl "$DP_PATCH_FILE" | patch -p1
    fi

    # Save a file to mark workspace already initiated
    touch /workspace/drupalpod_initiated.status

    # Run site install using a Drupal profile if one was defined
    if [ -n "$DP_INSTALL_PROFILE" ] && [ "$DP_INSTALL_PROFILE" != "''" ]; then
        ddev drush si -y --account-pass=admin --site-name="DrupalPod" "$DP_INSTALL_PROFILE"
        # Enable the module
        if [ "$DP_PROJECT_TYPE" != "project_core" ]; then
            ddev drush en -y "$DP_PROJECT_NAME"
        fi
    fi

    # Update HTTP repo to SSH repo
    "${GITPOD_REPO_ROOT}"/.gitpod/drupal/ssh/05-set-repo-as-ssh.sh
else
    ddev start
fi

#Open preview browser
gp preview "$(gp url 8080)"