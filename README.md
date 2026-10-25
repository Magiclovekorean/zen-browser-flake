# Zen Browser for Nix

This is a flake for the Zen browser. Originally forked from
[youwen5/zen-browser-flake](https://github.com/youwen5/zen-browser-flake),
but with several fixes.
GitHub Actions is configured to automatically check for updates daily.

The primary difference between this flake and most of the other forks
available is it has more correct packaging that closely mirrors how Firefox is packaged in nixpkgs,
using `wrapFirefox`. For instance Zen's desktop file is extracted directly from the binary
instead of being provided manually.

The annoying update checks have been disabled by default through a Firefox policy. The browser cannot
update itself when installed with Nix anyways, so these are entirely useless.

## Configuration

The wrapped package exposes the wrapper options from `wrapFirefox` in `nixpkgs`
as `.override` arguments.

### Policies

Policies are merged in this order:

1. the default `DisableAppUpdate = true`;
2. `config.zen.policies`;
3. `extraPolicies`.

Later entries win. For example:

```nix
inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
  extraPolicies = {
    ExtensionSettings = {
      "uBlock0@raymondhill.net" = {
        installation_mode = "force_installed";
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
      };
    };
    Preferences = {
      "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
    };
    PasswordManagerEnabled = false;
  };
}
```

`Preferences` in a policy is different from `extraPrefs`: policies are applied
by Firefox's enterprise policy engine and are generally the better fit for
managed settings. `extraPrefs` is appended to the `mozilla.cfg` AutoConfig file
and uses `pref(...)` or `lockPref(...)`, not `user_pref(...)`:

```nix
extraPrefs = ''
  pref("browser.tabs.warnOnClose", false);
'';
```

Additional policy files can be supplied with `extraPoliciesFiles`; values in
the inline policy set take precedence over values from those files.
`extraPrefsFiles` are appended to `mozilla.cfg` before `extraPrefs`.

### Extensions

There are two ways to install extensions:

- `extraPolicies.ExtensionSettings` with an AMO `install_url`. This uses
  Firefox's policy engine and works with signing enabled. `force_installed`
  makes the extension non-removable; use `normal_installed` if users should be
  able to disable or remove it. AMO slugs are not always the add-on name; for
  example, Dark Reader is `darkreader`, not `dark-reader`.
- `nixExtensions`, which installs XPI files from the Nix store. This disables
  signature enforcement and enables sideloading for the wrapped package. Use
  `pkgs.fetchFirefoxAddon` to fetch and normalize an XPI.

```nix
nixExtensions = [
  (pkgs.fetchFirefoxAddon {
    name = "ublock-origin";
    url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
    sha256 = "...";
    fixedExtid = "uBlock0@raymondhill.net";
  })
];
```

`nixExtensions` can be combined with an `ExtensionSettings` policy in
`extraPolicies` or `config.zen.policies`. The generated nixExtensions settings
(the `*` block and one `allowed` entry per nix extension) are merged with the
policy settings; later entries win. This lets you use `nixExtensions` for some
add-ons and policy-managed installation for others.

`extraPoliciesFiles` are merged with lower precedence, so they can add entries
that are not already present but cannot replace generated or inline settings.

### Other wrapper options

The following options are forwarded to `wrapFirefox` and can be overridden:

- `extraPrefs`, `extraPrefsFiles`, `extraAutoConfig`
- `extraPolicies`, `extraPoliciesFiles`
- `nixExtensions`
- `nativeMessagingHosts` and `pkcs11Modules`
- `cfg` (for example `cfg.libsecretSupport` or `cfg.smartcardSupport`)
- `withGlvnd`
- `appDataDir`

`cfg` defaults to `nixpkgs.config.zen`, so wrapper settings can also be set
through your nixpkgs configuration:

```nix
nixpkgs.config.zen.libsecretSupport = true;
```

To use, add it to the relevant NixOS configuration flake inputs:

```nix
inputs = {
  # ...
  zen-browser.url = "github:youwen5/zen-browser-flake";

  # optional, but recommended if you closely follow NixOS unstable so it shares
  # system libraries, and improves startup time
  # NOTE: if you experience a build failure with Zen, the first thing to check is to remove this line!
  zen-browser.inputs.nixpkgs.follows = "nixpkgs";
  # ...
}
```

## Packages

This flake provides the `zen-browser` package, which is also its default
package, for both `x86_64-linux` and `aarch64-linux` systems.

Additionally, `zen-browser-unwrapped` is provided (similar to
`firefox-bin-unwrapped`). A tree of the provided packages is displayed below
for your convenience.

```
packages
├───aarch64-linux
│   ├───default: package
│   ├───zen-browser: package
│   └───zen-browser-unwrapped: package
└───x86_64-linux
    ├───default: package
    ├───zen-browser: package
    └───zen-browser-unwrapped: package
```

## Installation

The easiest way is to use the CLI imperatively:

`nix profile install github:youwen5/zen-browser-flake`

If you're on NixOS and/or home-manager, you should install it in your system or
home configuration.

For example, in `configuration.nix`, add something similar to:

```nix
environment.systemPackages = [
  inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
];
```

If you don't want to use flakes, you can add it like:

```nix
environment.systemPackages = 
  let
    zen-browser = import (builtins.fetchTarball "https://github.com/youwen5/zen-browser-flake/archive/master.tar.gz") {
      inherit pkgs;
    };
  in
  [
    zen-browser    
  ];
```

A binary called `zen` is provided as well as a desktop file that should show up
in app launchers.


## FAQ

> How to run the update script locally?

There's a workflow configured that runs every day at 8PM Pacific Time to
automatically check for any new releases from `zen-browser/desktop` and update
the flake. If you want to run the script manually, just enter the repo's
directory and run

```sh
nix run .#update
```

> Is there a Cachix (binary cache)?

Since we're not building from source and just wrapping upstream binaries we
don't really need a binary cache as the patching process should take just a
few seconds.

If you're experiencing abnormally long build times you probably aren't
overriding the `nixpkgs` input and it's duplicating a lot of system libraries.
Just set `inputs.zen-browser.inputs.nixpkgs.follows = "nixpkgs"` or something
similar.

## Caveats

As with all GPU accelerated programs, Zen may not be able to use GPU
acceleration if not installed on NixOS (and if you didn't override its nixpkgs
input to your system nixpkgs, if using NixOS).

This can be solved with
[nix-community/nixGL](https://github.com/nix-community/nixGL).

## 1Password

Zen has to be manually added to the list of browsers that 1Password will
communicate with. See [this wiki article](https://nixos.wiki/wiki/1Password)
for more information. To enable 1Password integration, you need to add the line
`zen` to the file `/etc/1password/custom_allowed_browsers`.

## License

The derivation in `./zen-browser-unwrapped.nix` is mostly based on
[firefox-bin-unwrapped](https://github.com/NixOS/nixpkgs/blob/nixos-24.11/pkgs/applications/networking/browsers/firefox-bin/default.nix#L119)
which is MIT licensed Copyright (c) 2003-2025 Eelco Dolstra and the
Nixpkgs/NixOS contributors.

The rest of the code is licensed under the Unlicense and is released
unencumbered into the public domain. Feel free to fork and use for whatever
purposes. 
