#!/usr/bin/env -S nix shell nixpkgs#nushell --command nu

use update.nu generate_sources

def commit_update []: nothing -> nothing {
  let zen_latest = generate_sources

  if not ($zen_latest.changed) {
    print $"Latest version is ($zen_latest.prev_tag), no updates found"
    return
  }

  let message = if ($zen_latest.hash_refresh? | default false) {
    $"auto-update: refresh hashes for ($zen_latest.new_tag)"
  } else {
    $"auto-update: ($zen_latest.prev_tag) -> ($zen_latest.new_tag)"
  }

  git add sources.json
  let commit = git commit -m $message | complete
  if ($commit.exit_code != 0) {
    print $"Failed to commit update: ($commit.stderr)"
    return
  }
  print $"Performed update: ($message)"

  print "Updating Flake lockfile"
  nix flake update --commit-lock-file

  let build = nix build | complete
  if ($build.exit_code == 0) {
    git push
  } else {
    print $"Update was successful, but there was a build failure! ($build.stderr). Not pushing update."
  }
}

commit_update
