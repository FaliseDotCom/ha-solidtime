#!/usr/bin/env bash
# Updates the app to a new Solidtime release: checks the upstream image, bumps
# the version everywhere it appears, adds a changelog entry and builds the
# image. It never commits or pushes; it prints the git commands to run afterwards.
#
# Usage: scripts/update-solidtime.sh [version]
#   version  Solidtime version such as 0.22.0. Defaults to the latest GitHub release.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly REPO_ROOT
readonly DOCKERFILE="$REPO_ROOT/solidtime/Dockerfile"
readonly CONFIG="$REPO_ROOT/solidtime/config.yaml"
readonly CHANGELOG="$REPO_ROOT/solidtime/CHANGELOG.md"
readonly README="$REPO_ROOT/README.md"
readonly IMAGE=solidtime/solidtime
readonly RELEASES_API=https://api.github.com/repos/solidtime-io/solidtime/releases/latest
readonly RELEASES_URL=https://github.com/solidtime-io/solidtime/releases/tag
readonly VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'

fatal()
{
  echo "ERROR: $*" >&2
  exit 1
}

# GitHub tags carry a "v" prefix; the Docker Hub tags do not.
latest_release()
{
  curl -fsSL "$RELEASES_API" | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1
}

current_version()
{
  sed -n "s|^FROM $IMAGE:\(.*\)$|\1|p" "$DOCKERFILE"
}

# The Supervisor architectures amd64 and aarch64 need linux/amd64 and linux/arm64.
check_image()
{
  local manifest
  manifest=$(docker buildx imagetools inspect "$IMAGE:$1") || fatal "Image $IMAGE:$1 not found on Docker Hub."

  local platform
  for platform in linux/amd64 linux/arm64
  do
    if ! grep -q "Platform: *$platform\$" <<< "$manifest"
    then
      fatal "Image $IMAGE:$1 has no $platform build."
    fi
  done
}

update_files()
{
  local old="$1"
  local new="$2"

  sed -i "s|^FROM $IMAGE:$old\$|FROM $IMAGE:$new|" "$DOCKERFILE"
  sed -i "s|^version: \".*\"\$|version: \"$new\"|" "$CONFIG"
  sed -i "s|Solidtime $old|Solidtime $new|; s|Solidtime-$old-|Solidtime-$new-|" "$README"
}

# Inserts the new entry above the first existing release heading.
add_changelog_entry()
{
  local new="$1"
  local entry="## $new\n\n- Solidtime $new. See the [Solidtime $new release notes]($RELEASES_URL/v$new).\n"

  awk -v entry="$entry" '!done && /^## / { printf "%s\n", entry; done = 1 } { print }' "$CHANGELOG" > "$CHANGELOG.tmp"
  mv "$CHANGELOG.tmp" "$CHANGELOG"
}

main()
{
  local new="${1:-}"
  new="${new#v}"

  if [ -z "$new" ]
  then
    new=$(latest_release)
  fi

  if ! [[ "$new" =~ $VERSION_PATTERN ]]
  then
    fatal "'$new' is not a Solidtime version such as 0.22.0."
  fi

  local old
  old=$(current_version)

  if [ "$old" = "$new" ]
  then
    echo "Already on Solidtime $new."
    exit 0
  fi

  # Solidtime migrates the database on start, so an older image cannot run on it.
  if [ "$(printf '%s\n' "$old" "$new" | sort -V | tail -n 1)" = "$old" ]
  then
    fatal "Solidtime $new is older than the current $old; downgrades are not supported."
  fi

  echo "Updating Solidtime $old -> $new"
  check_image "$new"
  update_files "$old" "$new"
  add_changelog_entry "$new"

  echo "Building the image to check it still builds..."
  docker build -t local/solidtime-app "$REPO_ROOT/solidtime"

  cat <<EOT

Solidtime $old -> $new prepared. Next:

  1. Read the release notes: $RELEASES_URL/v$new
  2. Test an upgrade on existing data (see .docs/development.md).
  3. Review the diff and release:

       git diff
       git commit -am "Update Solidtime to $new"
       git tag $new
       git push && git push --tags
EOT
}

main "$@"
