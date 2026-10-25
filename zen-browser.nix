{
  config,
  wrapFirefox,
  zen-browser-unwrapped,
  extraPolicies ? { },
  extraPoliciesFiles ? [ ],
  extraPrefs ? "",
  extraPrefsFiles ? [ ],
  extraAutoConfig ? "",
  nixExtensions ? null,
  nativeMessagingHosts ? [ ],
  pkcs11Modules ? [ ],
  cfg ? (config.zen or { }),
  withGlvnd ? true,
  appDataDir ? null,
  ...
}:
let
  # wrapFirefox selects the FFmpeg ABI from browser.version. Zen's package
  # version is independent from the underlying Firefox version, so present the
  # Firefox base version to the wrapper while retaining Zen's version on the
  # resulting package.
  browserForWrapper = zen-browser-unwrapped // {
    version = zen-browser-unwrapped.firefoxVersion;

    # Required for declarative nixExtensions to work.
    enableAddonSigning = false;
    enableAddonSideload = true;
  };

  # wrapFirefox replaces the unwrapped package's distribution/policies.json, so
  # carry its policy set forward explicitly. Otherwise DisableAppUpdate and
  # config.zen.policies are silently discarded.
  basePolicies = zen-browser-unwrapped.policies or { };

  # wrapFirefox generates these ExtensionSettings for nixExtensions and then
  # shallow-merges extraPolicies over them. Recreate the generated settings so
  # user policies can be merged without discarding the nixExtensions entries.
  nixExtensionSettings =
    if nixExtensions == null then
      { }
    else
      {
        "*" = {
          blocked_install_message = "You can't have manual extension mixed with nix extensions";
          installation_mode = "blocked";
        };
      }
      // builtins.listToAttrs (
        map (extension: {
          name =
            extension.extid
              or (throw "nixExtensions has an invalid entry. Missing extid attribute. Please use fetchFirefoxAddon");
          value = {
            installation_mode = "allowed";
          };
        }) nixExtensions
      );

  policies =
    basePolicies
    // extraPolicies
    // (
      if nixExtensions == null then
        { }
      else
        {
          ExtensionSettings =
            nixExtensionSettings
            // (basePolicies.ExtensionSettings or { })
            // (extraPolicies.ExtensionSettings or { });
        }
    );

  wrapped = wrapFirefox browserForWrapper {
    pname = "zen-browser";
    version = zen-browser-unwrapped.version;

    inherit
      appDataDir
      cfg
      extraAutoConfig
      extraPoliciesFiles
      extraPrefs
      extraPrefsFiles
      nativeMessagingHosts
      nixExtensions
      pkcs11Modules
      withGlvnd
      ;

    extraPolicies = policies;
  };
in
wrapped
// {
  # Expose the policy set forwarded to wrapFirefox for inspection and tests.
  inherit policies;
  passthru = (wrapped.passthru or { }) // {
    inherit policies;
  };
}
