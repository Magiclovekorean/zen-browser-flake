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
  policies = (zen-browser-unwrapped.policies or { }) // extraPolicies;

  # wrapFirefox shallow-merges extraPolicies over the ExtensionSettings it
  # generates for nixExtensions. An ExtensionSettings policy would therefore
  # silently replace the generated allow/block rules.
  policiesConflict = nixExtensions != null && (policies ? ExtensionSettings);

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
if policiesConflict then
  throw ''
    zen-browser: nixExtensions cannot be combined with an ExtensionSettings
    policy in extraPolicies or config.zen.policies. wrapFirefox would replace
    the nixExtensions-generated ExtensionSettings with the supplied policy.
  ''
else
  wrapped
  // {
    # Expose the policy set forwarded to wrapFirefox for inspection and tests.
    inherit policies;
    passthru = (wrapped.passthru or { }) // {
      inherit policies;
    };
  }
