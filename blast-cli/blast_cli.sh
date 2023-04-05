#!/usr/bin/env bash

set -e -o noglob

if [ -z "$1" ]; then
    echo "Command not provided"
    exit 1
else
    command=$1
fi

if [ -z "$2" ]; then
    echo "Paths not provided"
    exit 1
else
    declare -a 'paths=('"$2"')'
fi

if [ ! -z "$3" ]; then
    npm_token=$3
fi

if [ ! -z "$4" ]; then
    extension_schema=$4
else
    extension_schema="https://www.raycast.com/schemas/extension.json"
fi

if [ ! -z "$5" ]; then
    SAVEIFS=$IFS
    IFS=$'\n'
    allow_owners_only_for_extensions=($5)
    IFS=$SAVEIFS
fi

function ray_command_from_string() {
    case $1 in
        build)
        ray_command="build . -o dist"
        ray_validate_options=""
        ;;

        publish)
        ray_command="publish . blast-extensions"
        ray_validate_options=""
        ;;

        *)
        echo "Unsupported command. 'build' | 'publish'"
        return 1
        ;;
    esac
}
ray_command_from_string $command

printf "🤖 %d extensions found\n" "${#paths[@]}"
printf '%s\n' "${paths[@]}"

printf "🤖 Downloading JSON scheme: $extension_schema"
scheme_path="/tmp/raycast/extensions.json"
curl "$extension_schema" --create-dirs -o $scheme_path

starting_dir=$PWD
# ray_validate="ray validate $ray_validate_options -s $scheme_path --non-interactive --emoji --exit-on-error"
ray_build_publish="blast $ray_command"
ray_ci_log_file="/tmp/raycast/ray_cli.log"

last_exit_code=0
exit_code=$last_exit_code

declare -a 'store_urls'

for dir in "${paths[@]}" ; do    
    extension_folder=`basename $dir`
    printf "\nEntering $dir\n"
    cd "$dir"

    ### Precheck package-lock existance for more readable errors
    if [ ! -f "./package-lock.json" ]; then
        echo "::error::Missing package-lock.json for $extension_folder"
        exit_code=1
        continue
    fi

    if [ -f "./yarn.lock" ]; then
        echo "::error::Remove yarn.lock for $extension_folder"
        exit_code=1
        continue
    fi

    ### Prevent 'owner' in package.json if needed
    # if [ ! -z "${allow_owners_only_for_extensions}" ]; then
    #     if !(printf '%s\n' "${allow_owners_only_for_extensions[@]}" | grep -xq "$extension_folder"); then
    #         has_owner=$(jq 'has("owner")' package.json)
    #         if [ "$has_owner" == "true" ]; then
    #             echo "::error::\"owner\" field is not allowed in package.json for $extension_folder"
    #             exit_code=1
    #             continue
    #         fi
    #     else
    #         printf "Skipping 'owner' check for $extension_folder\n"
    #     fi
    # fi

    ### Create .npmrc if needed
    cleanup_npmrc=false

    if [ -z "$npm_token" ]; then
        echo "::error::Private npm_token is required"
        exit_code=1
        continue
    else
        echo "//registry.npmjs.org/:_authToken=$npm_token" > .npmrc
        cleanup_npmrc=true
    fi

    # api_version=$(jq '.dependencies."@raycast/api"' package.json)
    # if [[ "$api_version" == *"alpha"* ]]; then
    #     if [ -z "$npm_token" ]; then
    #         echo "::error::Private npm used without npm_token parameter"
    #         exit_code=1
    #         continue
    #     else
    #         echo "//npm.pkg.github.com/:_authToken=$npm_token" > .npmrc
    #         echo "@raycast:registry=https://npm.pkg.github.com" >> .npmrc
    #         cleanup_npmrc=true
    #     fi
    # fi

    # npm ci doesn't allow us to silence output properly
    # run it silently first and if it fails run it without silencing
    set +e
    npm ci --silent
    last_exit_code=${?}
    set -e

    if [ $last_exit_code -ne 0 ]; then
        echo "::error::Npm ci failed for $extension_folder"
        set +e
        npm ci
        set -e
        exit_code=1
        continue
    fi

    ### Cleanup `.npmrc`
    if [ "$cleanup_npmrc" = true ] ; then
        rm .npmrc
    fi

    ### Validate
    # set +e
    # $ray_validate 2>&1 | tee $ray_ci_log_file ; test ${PIPESTATUS[0]} -eq 0
    # last_exit_code=${?}
    # set -e

    # Run command
    if [ $last_exit_code -eq 0 ]; then
        set +e
        $ray_build_publish 2>&1 | tee $ray_ci_log_file ; test ${PIPESTATUS[0]} -eq 0
        last_exit_code=${?}
        set -e
    fi

    #cleanup npm
    rm -rf ./node_modules

    if [ $exit_code -eq 0 ]; then
        exit_code=$last_exit_code
    fi
    if [ $last_exit_code -ne 0 ]; then
        error_message=`cat $ray_ci_log_file | tail -1`
        echo "::error title=$command failed for $extension_folder::$error_message"
    # else
        # if [ "$command" == "publish" ]; then
        #     author=`cat package.json | jq -r '.author | values'`
        #     owner=`cat package.json | jq -r '.owner | values'`
        #     name=`cat package.json | jq -r '.name | values'`
        #     if [ ! -z "$owner" ]
        #     then
        #         store_path="$owner/$name"
        #     else
        #         store_path="$author/$name"
        #     fi
        #     store_url="https://raycast.com/$store_path"
        #     store_urls+=("$store_url")
        # fi
    fi
    cd $starting_dir
done

# encode multiline output for github actions
# store_urls_string=$(printf "%s\n" "${store_urls[@]}")
# store_urls_string="${store_urls_string//'%'/'%25'}"
# store_urls_string="${store_urls_string//$'\n'/'%0A'}"
# store_urls_string="${store_urls_string//$'\r'/'%0D'}"
# echo "store_urls=${store_urls_string}" >> $GITHUB_OUTPUT
exit $exit_code
