#!/bin/bash

# Get current branch (main) HEAD time
current_branch_head_time=$(git log -1 --pretty=format:"%ct")

# Query the first commit on upstream/main after that time
start_sha1=$(git log --pretty=format:"%h" --first-parent upstream/main --since=$current_branch_head_time | tail -n 1)

# Get upstream/main branch HEAD commit SHA1
upstream_main_head_sha1=$(git rev-parse upstream/main)

# Cherry-pick all commits on upstream/main while preserving original commit date
while read sha1; do
    commit_date=$(git log -1 --pretty=format:"%ct" $sha1)
    export GIT_AUTHOR_DATE=$commit_date
    export GIT_COMMITTER_DATE=$commit_date
    git cherry-pick $sha1
done < <(git rev-list --reverse $start_sha1..$upstream_main_head_sha1)
