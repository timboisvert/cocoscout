# frozen_string_literal: true

# Ticketing notifications by plan (Tim, 2026-10-20): each person and address
# has a plan (everything, usual, money, custom, nothing) instead of each
# email keeping its own list of people. Every organization's choices so far
# become plans: the same emails to the same people. An organization that
# never saved its own choices stays on the defaults (managers on The usual).
# notification_rules stays for now, unread.
class AddNotificationPlansToTicketingProfiles < ActiveRecord::Migration[8.1]
  KEYS = %w[sale door_sale comp_issued pass_redeemed daily_summary show_day after_show sales_opened almost_sold_out sold_out
            refund_issued refund_problem dispute withdrawal cancellation_done].freeze
  USUAL = %w[daily_summary show_day after_show almost_sold_out sold_out refund_problem dispute withdrawal cancellation_done].freeze
  MONEY = %w[refund_issued refund_problem dispute withdrawal cancellation_done].freeze

  def up
    add_column :ticketing_profiles, :notification_plans, :jsonb, null: false, default: {}

    select_rows(<<~SQL).each do |id, organization_id, rules_json, emails_json|
      SELECT id, organization_id, notification_rules, notification_emails FROM ticketing_profiles
      WHERE notification_rules IS NOT NULL AND notification_rules <> '{}'::jsonb
    SQL
      rules = JSON.parse(rules_json.to_s.presence || "{}")
      emails = JSON.parse(emails_json.to_s.presence || "[]").map { |e| e.to_s.strip.downcase }.compact_blank
      managers = select_values(<<~SQL)
        SELECT user_id FROM organization_roles WHERE organization_id = #{organization_id.to_i} AND company_role = 'manager'
        UNION SELECT owner_id FROM organizations WHERE id = #{organization_id.to_i} AND owner_id IS NOT NULL
      SQL
      keys = managers.map { |uid| "user:#{uid}" } + emails.map { |e| "email:#{e}" }
      plans = keys.uniq.to_h do |key|
        ticked = KEYS.select { |kind| Array(rules[kind]).include?(key) }
        [ key, plan_for(ticked) ]
      end
      execute("UPDATE ticketing_profiles SET notification_plans = #{quote(plans.to_json)}::jsonb WHERE id = #{id.to_i}")
    end
  end

  def down
    remove_column :ticketing_profiles, :notification_plans
  end

  private

  def plan_for(ticked)
    set = ticked.sort
    return { "plan" => "everything" } if set == KEYS.sort
    return { "plan" => "usual" } if set == USUAL.sort
    return { "plan" => "money" } if set == MONEY.sort
    return { "plan" => "nothing" } if set.empty?

    { "plan" => "custom", "kinds" => ticked }
  end
end
