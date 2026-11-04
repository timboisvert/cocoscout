# frozen_string_literal: true

# How an organization splits a day's tips when it lets the clock decide
# (plan §9.14): the switch, and a share per Staffing role. A role that is in
# shares equally what rang up while its people were on (Bartender), or takes
# a fixed cut off the top first (Bar back, 15%). Roles not listed are out:
# door and box office never see bar tips unless the organization says so.
# Tips rung up while nobody who shares was on go to the pool and split
# evenly among the night's sharers.
class TipRule < ApplicationRecord
  KINDS = %w[equal percent].freeze

  belongs_to :organization

  validates :nobody_on, inclusion: { in: %w[pool] }
  validate :role_shares_well_formed

  # { "12" => { "kind" => "equal" }, "15" => { "kind" => "percent", "percent" => 15 } }
  def share_for(house_role_id) = role_shares[house_role_id.to_s]
  def kind_for(house_role_id) = share_for(house_role_id)&.dig("kind")
  def percent_for(house_role_id) = share_for(house_role_id)&.dig("percent").to_f
  def shares?(house_role_id) = share_for(house_role_id).present?
  def sharing_role_ids = role_shares.keys.map(&:to_i)
  def percent_role_ids = role_shares.select { |_, v| v["kind"] == "percent" }.keys.map(&:to_i)
  def equal_role_ids = role_shares.select { |_, v| v["kind"] == "equal" }.keys.map(&:to_i)

  # The rule in the organization's words, for the worksheet.
  def summary(roles_by_id)
    equal = equal_role_ids.filter_map { |id| roles_by_id[id]&.name }
    cuts = percent_role_ids.filter_map { |id| roles_by_id[id] && "#{roles_by_id[id].name} #{percent_for(id).round(percent_for(id) % 1 == 0 ? 0 : 1)}% off the top" }
    parts = []
    parts << "#{equal.to_sentence} #{equal.size == 1 ? 'keeps' : 'split'} what rang up while on" if equal.any?
    parts.concat(cuts)
    parts.any? ? parts.join("; ") : "No role shares the tips yet."
  end

  # From the settings form: roles[<id>][share] = out | equal | percent, roles[<id>][percent].
  def self.role_shares_from(params, roles)
    roles.each_with_object({}) do |role, shares|
      attrs = params[role.id.to_s] || {}
      case attrs[:share]
      when "equal" then shares[role.id.to_s] = { "kind" => "equal" }
      when "percent" then shares[role.id.to_s] = { "kind" => "percent", "percent" => attrs[:percent].to_f.clamp(0.0, 100.0).round(1) }
      end
    end
  end

  private

  def role_shares_well_formed
    return if role_shares.is_a?(Hash) && role_shares.values.all? { |v| v.is_a?(Hash) && KINDS.include?(v["kind"]) && (v["kind"] != "percent" || v["percent"].to_f.between?(0, 100)) }

    errors.add(:role_shares, "must say equal or a percent for each role")
  end
end
