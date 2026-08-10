#!/bin/bash

# Rebuilds Jacquard for the Web and publishes the result from this repository.
#
# Everything the publishing needs lives here rather than in Jacquard, which keeps the
# source repository free of scaffolding that only this one cares about. The build entry
# point is the one thing Unity insists on having inside the project, so it is written
# into the working clone on the way past — the clone is ours and disposable, so nothing
# is left anywhere that is kept.
#
# The clone is kept between runs, and that is the difference between minutes and tens
# of them: a fresh checkout has to import every asset and compile IL2CPP and Burst from
# nothing, where a warm Library only does the part that changed. It costs a gigabyte or
# two under .work, which is ignored.
#
# Running the editor in batch mode does not conflict with having Jacquard open in the
# editor. What Unity refuses is two instances on the same project directory, and the
# clone is a different one.
#
# Usage: ./publish.sh [--no-push]
#
#   JACQUARD_REPO  where to clone from       (default: the GitHub repository)
#   JACQUARD_REF   what to build             (default: main)
#   JACQUARD_WORK  where to keep the clone   (default: .work beside this script)

set -euo pipefail

repo="${JACQUARD_REPO:-git@github.com:keijiro/Jacquard.git}"
ref="${JACQUARD_REF:-main}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="${JACQUARD_WORK:-$here/.work}"
src="$work/Jacquard"
log="$work/build.log"

push=yes

case "${1:-}" in
  --no-push) push=no ;;
  "") ;;
  *) echo "usage: $(basename "$0") [--no-push]" >&2; exit 64 ;;
esac

say() { printf '\n== %s\n' "$1"; }

command -v unity > /dev/null ||
  { echo "The unity CLI is not on PATH." >&2; exit 69; }

# Anything already uncommitted here would end up inside the publishing commit, which is
# meant to carry a build and nothing else.
[ -z "$(git -C "$here" status --porcelain)" ] ||
  { echo "This repository has uncommitted changes; commit or stash them first." >&2
    exit 65; }

mkdir -p "$work"

# Fetch rather than re-clone, and take the ref detached: this checkout is only ever read
# from, so it has no business being on a branch that could drift.
if [ -d "$src/.git" ]; then
  say "Fetching $ref"
  git -C "$src" fetch --prune --quiet origin
else
  say "Cloning into $src"
  git clone --quiet "$repo" "$src"
fi

git -C "$src" checkout --quiet --detach --force "origin/$ref" 2> /dev/null ||
  git -C "$src" checkout --quiet --detach --force "$ref"

commit=$(git -C "$src" rev-parse --short HEAD)
subject=$(git -C "$src" log -1 --format=%s)
echo "   at $commit — $subject"

# The build entry point. Unity has no command line build of its own, so a static method
# is the only way in, and it has to be compiled into the project to be named.
say "Writing the build entry point"
mkdir -p "$src/Assets/Editor"
cat > "$src/Assets/Editor/PublishWebBuild.cs" <<'CSHARP'
using UnityEditor;
using UnityEngine;

namespace Jacquard.Editor {

// Written here by jacquard-web's publish.sh. Not part of the project.

static class PublishWebBuild
{
    public static void Perform()
    {
        var report = BuildPipeline.BuildPlayer(
          new BuildPlayerOptions
            { scenes = new[] { "Assets/Main.unity" },
              locationPathName = "Web",
              target = BuildTarget.WebGL,
              options = BuildOptions.None });

        var succeeded =
          report.summary.result == UnityEditor.Build.Reporting.BuildResult.Succeeded;

        Debug.Log("Build result: " + report.summary.result +
                  " errors=" + report.summary.totalErrors);

        EditorApplication.Exit(succeeded ? 0 : 1);
    }
}

} // namespace Jacquard.Editor
CSHARP

say "Building (this takes a while on a cold clone)"
rm -rf "$src/Web"

if ! unity build --target WebGL \
       --execute-method Jacquard.Editor.PublishWebBuild.Perform \
       --no-tail --log-file "$log" "$src"; then
  echo "The build failed. Its log is at $log" >&2
  exit 70
fi

# Believe the files rather than the exit code, and check them before anything that is
# already published is touched.
[ -f "$src/Web/index.html" ] && [ -d "$src/Web/Build" ] ||
  { echo "The build reported success but produced no page. Log: $log" >&2; exit 70; }

say "Replacing the published build"

# Everything in the root that is not one of these is build output, and is replaced
# wholesale rather than deleted by name: a build that renames or drops a file has to be
# able to take the old one with it. Anything of your own that belongs here belongs in
# this list too.
find "$here" -mindepth 1 -maxdepth 1 \
  ! -name .git ! -name .gitignore ! -name .nojekyll \
  ! -name README.md ! -name publish.sh ! -name "$(basename "$work")" \
  -exec rm -rf {} +

cp -R "$src/Web/." "$here/"

# Unity says which of what it just produced is not for shipping, in the one place it can
# be sure will survive being copied around: the folder's name.
find "$here" -mindepth 1 -maxdepth 1 \
  \( -name "*_DoNotShip" -o -name "*_BackUpThisFolder_ButDontShipItWithYourGame" \) \
  -exec rm -rf {} +

# The README names the commit it was built from, so it has to be told about this one or
# it starts lying immediately.
sed -i.bak -E "s#(Built from \[Jacquard\] at \`)[0-9a-f]+(\`)#\1$commit\2#" "$here/README.md"
rm -f "$here/README.md.bak"

git -C "$here" add -A

if git -C "$here" diff --cached --quiet; then
  say "The build is identical to what is already published; nothing to do"
  exit 0
fi

git -C "$here" commit --quiet -m "Rebuild from Jacquard at $commit

$subject"

say "Committed $(git -C "$here" rev-parse --short HEAD)"

if [ "$push" = yes ]; then
  git -C "$here" push --quiet origin HEAD
  echo "   pushed — https://www.keijiro.tokyo/jacquard-web/ updates in a minute or two"
else
  echo "   not pushed (--no-push)"
fi
