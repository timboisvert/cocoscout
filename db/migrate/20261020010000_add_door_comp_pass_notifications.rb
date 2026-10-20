# frozen_string_literal: true

# Ticketing notifications get a row for each way tickets go out (Tim,
# 2026-10-19): online sale, door sale, comp issued, pass redeemed, each with
# its own email. Whoever ticked "Each sale" expected door sales too, so they
# get the new door-sale row ticked the same way.
class AddDoorCompPassNotifications < ActiveRecord::Migration[8.1]
  def up
    TicketingTemplates.ensure!(keys: %w[ticketing_door_sale ticketing_comp_issued ticketing_pass_redeemed])
    ContentTemplate.where(key: "ticketing_sale").update_all(name: "Ticketing: each online sale")

    TicketingProfile.find_each do |profile|
      rules = profile.notification_rules
      next unless rules.is_a?(Hash) && rules["sale"].present? && !rules.key?("door_sale")

      profile.update_column(:notification_rules, rules.merge("door_sale" => rules["sale"]))
    end
  end

  def down; end
end
