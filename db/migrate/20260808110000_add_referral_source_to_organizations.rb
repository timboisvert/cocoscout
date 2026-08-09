# frozen_string_literal: true

# Where an organization came from, when it came from a campaign we ran.
#
# Nothing used to survive the trip from a marketing page to a created
# Organization — /signup takes no params and org creation captures only name
# and logo — so we had no way to tell whether a sponsorship or a landing page
# actually produced signups. The value is captured into the session on the
# public side (see ReferralTracking) and stamped here when the org is created.
#
# Nil for organic signups, which is the overwhelming majority. Values are
# whitelisted at capture time, so this column only ever holds campaign slugs
# we chose ourselves — e.g. Organization.where(referral_source: "sketchfest").
class AddReferralSourceToOrganizations < ActiveRecord::Migration[8.1]
  def change
    add_column :organizations, :referral_source, :string
    add_index :organizations, :referral_source
  end
end
