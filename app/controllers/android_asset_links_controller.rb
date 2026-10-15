# frozen_string_literal: true

# Tells Android phones that the CocoScout app may open cocoscout.com links
# (App Links) and offer the passwords people saved for the site. Android
# fetches /.well-known/assetlinks.json when the app is installed: JSON, no
# redirect, no sign-in. Which paths open in the app is the app's own list
# (android/app/src/main/AndroidManifest.xml), the same pages the iPhone app
# claims (AppleAppSiteAssociationsController).
class AndroidAssetLinksController < ApplicationController
  allow_unauthenticated_access

  PACKAGE = "com.cocoscout.app"
  # Google Play's app signing key (Play Console → App signing), which signs
  # every copy people install; then CocoScout's upload key, for release
  # builds installed straight from this Mac. Neither is secret.
  CERTIFICATES = %w[
    58:B5:1D:2E:C2:E0:E8:92:0C:6F:8B:0F:73:84:8C:04:F2:B9:BC:F6:B0:99:B0:37:9B:BC:FA:DD:EC:5D:AD:3F
    AF:9D:75:76:6E:02:BD:96:10:D9:4C:45:2C:D4:DA:3A:67:6E:0F:B2:72:BE:53:9A:8B:32:1E:88:1D:29:9E:2E
  ].freeze

  def show
    expires_in 1.hour, public: true
    render json: [ {
      relation: %w[delegate_permission/common.handle_all_urls delegate_permission/common.get_login_creds],
      target: { namespace: "android_app", package_name: PACKAGE, sha256_cert_fingerprints: CERTIFICATES }
    } ]
  end
end
