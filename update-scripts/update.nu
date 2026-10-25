# to invoke generate_sources directly, enter nushell and run
# `use update.nu generate_sources`
# `generate_sources`

const X86_64_ASSET = "zen.linux-x86_64.tar.xz"
const AARCH64_ASSET = "zen.linux-aarch64.tar.xz"

def github_headers []: nothing -> record {
  # Authenticate when a token is available to avoid the low rate limit for
  # unauthenticated requests.
  let token = ($env.GITHUB_TOKEN? | default "")
  if ($token | is-empty) {
    {}
  } else {
    { Authorization: $"Bearer ($token)" }
  }
}

def get_releases [repo: string]: nothing -> list {
  let response = try {
    http get --headers (github_headers) --full $"https://api.github.com/repos/($repo)/releases?per_page=30"
  } catch { |err|
    error make { msg: $"Failed to fetch releases for ($repo), aborting: ($err.msg)" }
  }

  if $response.status != 200 {
    error make { msg: $"GitHub API returned status ($response.status) while fetching releases for ($repo)" }
  }

  $response.body
}

def linux_assets [release: record]: nothing -> list {
  $release.assets | where {|asset| $asset.name in [$X86_64_ASSET $AARCH64_ASSET]}
}

def linux_assets_ready [release: record]: nothing -> bool {
  let assets = linux_assets $release
  (($assets | length) == 2) and ($assets | all {|asset| $asset.state == "uploaded" and $asset.size > 0 })
}

def get_latest_release [repo: string]: nothing -> record {
  let releases = get_releases $repo
  let candidates = $releases
    | where {|release| not $release.draft}
    | where {|release| not $release.prerelease}
    | where {|release| $release.tag_name != "twilight"}
    | where {|release| linux_assets_ready $release}

  if ($candidates | is-empty) {
    error make { msg: $"No ($repo) release has both Linux assets fully uploaded, aborting" }
  }

  $candidates | first
}

def get_firefox_version [tag: string]: nothing -> string {
  let url = $"https://raw.githubusercontent.com/zen-browser/desktop/($tag)/surfer.json"
  let response = try {
    http get --full $url
  } catch { |err|
    error make { msg: $"Failed to fetch Firefox version for ($tag), aborting: ($err.msg)" }
  }

  if $response.status != 200 {
    error make { msg: $"Failed to fetch Firefox version for ($tag): HTTP ($response.status)" }
  }

  try {
    $response.body.version.version
  } catch {
    error make { msg: $"Could not find version.version in ($url)" }
  }
}

def get_nix_hash [url: string]: nothing -> string {
  try {
    nix store prefetch-file --hash-type sha256 --json $url | from json | get hash
  } catch { |err|
    error make { msg: $"Failed to prefetch ($url), aborting: ($err.msg)" }
  }
}

def get_asset_hash [asset: record]: nothing -> string {
  let digest = ($asset.digest? | default "")
  if ($digest | is-empty) or (not ($digest | str starts-with "sha256:")) {
    # Older releases do not expose a SHA-256 digest through the API.
    get_nix_hash $asset.browser_download_url
  } else {
    nix hash convert --hash-algo sha256 --to sri $digest | str trim
  }
}

def assert_asset_available [url: string]: nothing -> nothing {
  let response = try {
    http head --full --max-time 30sec $url
  } catch { |err|
    error make { msg: $"Failed to check ($url), aborting: ($err.msg)" }
  }

  if $response.status != 200 {
    error make { msg: $"Release asset does not resolve (HTTP ($response.status)): ($url)" }
  }
}

def select_asset [release: record, name: string]: nothing -> record {
  let assets = $release.assets | where {|asset| $asset.name == $name}
  if ($assets | is-empty) {
    error make { msg: $"Release ($release.tag_name) does not contain ($name), aborting" }
  }
  $assets | first
}

def build_sources [release: record, firefox_version: string]: nothing -> record {
  let x86_64 = select_asset $release $X86_64_ASSET
  let aarch64 = select_asset $release $AARCH64_ASSET

  # Make sure the assets actually resolve before pinning them. A release can
  # be visible through the API before (or without) its assets being uploaded.
  assert_asset_available $x86_64.browser_download_url
  assert_asset_available $aarch64.browser_download_url

  {
    version: $release.tag_name
    firefoxVersion: $firefox_version
    x86_64-linux: {
      url: $x86_64.browser_download_url
      hash: (get_asset_hash $x86_64)
    }
    aarch64-linux: {
      url: $aarch64.browser_download_url
      hash: (get_asset_hash $aarch64)
    }
  }
}

def refresh_pinned_sources [sources: record, release: record]: nothing -> record {
  let refreshed = build_sources $release $sources.firefoxVersion
  {
    changed: ([
      ($refreshed.x86_64-linux.hash != $sources.x86_64-linux.hash)
      ($refreshed.aarch64-linux.hash != $sources.aarch64-linux.hash)
      ($refreshed.x86_64-linux.url != $sources.x86_64-linux.url)
      ($refreshed.aarch64-linux.url != $sources.aarch64-linux.url)
    ] | any {|changed| $changed})
    sources: $refreshed
  }
}

export def generate_sources []: nothing -> record {
  let prev_sources: record = open ./sources.json
  let release = get_latest_release "zen-browser/desktop"
  let tag = $release.tag_name

  if $tag == $prev_sources.version {
    # Zen sometimes re-uploads the assets for an existing tag. The release is
    # still the same version, but the pinned hash is no longer valid, so check
    # the assets haven't changed and refresh sources.json when they have.
    let refreshed = refresh_pinned_sources $prev_sources $release
    if not ($refreshed.changed) {
      return {
        prev_tag: $tag
        new_tag: $tag
        changed: false
      }
    }

    echo $refreshed.sources | save --force "sources.json"
    return {
      prev_tag: $tag
      new_tag: $tag
      changed: true
      hash_refresh: true
    }
  }

  let firefox_version = get_firefox_version $tag
  let sources = build_sources $release $firefox_version

  echo $sources | save --force "sources.json"

  return {
    prev_tag: $prev_sources.version
    new_tag: $tag
    changed: true
  }
}
