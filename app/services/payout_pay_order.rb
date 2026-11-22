# frozen_string_literal: true

# Who a payout run pays first when the CocoScout balance can't cover everyone
# (Tim, 2026-11-22). Payees fall into groups: staff, performers, and
# contractors (anyone paid on a contract, and other organizations). The
# organization sets the default order of the groups in Money settings; a run
# can change it for itself, groups and people both, in its Pay order window.
# The default is staff, then contractors, then performers (Tim, 2026-11-22).
#
# Within a group, people the manager placed come first, in that order; anyone
# else goes smallest amount first, so the money pays as many people as it can.
# Someone with both staff and performer pay counts as staff.
class PayoutPayOrder
  GROUPS = %w[staffing contractor performer].freeze
  LABELS = { "staffing" => "Staff", "contractor" => "Contractors", "performer" => "Performers" }.freeze

  def self.group_for(item)
    contributions = item.payout_contributions.to_a
    return "staffing" if contributions.any? { |c| c.category == "staffing" }
    return "contractor" if item.payee_type == "Organization" || contributions.any? { |c| c.source_type == "ContractPayment" }

    "performer"
  end

  def self.payee_key(item)
    "#{item.payee_type}:#{item.payee_id}"
  end

  # The organization's default, always all three groups once each.
  def self.default_groups(organization)
    clean_groups(organization.payout_pay_order)
  end

  def self.groups_for(batch)
    saved = batch.pay_order.is_a?(Hash) ? batch.pay_order["groups"] : nil
    saved.present? ? clean_groups(saved) : default_groups(batch.organization)
  end

  def self.clean_groups(list)
    ordered = Array(list).map(&:to_s) & GROUPS
    ordered + (GROUPS - ordered)
  end

  # Items in the order this run pays them.
  def self.sort(batch, items)
    groups = groups_for(batch)
    placed = batch.pay_order.is_a?(Hash) ? Array(batch.pay_order["payees"]) : []
    items.sort_by do |item|
      [ groups.index(group_for(item)), placed.index(payee_key(item)) || placed.size, item.amount_cents.to_i, item.id ]
    end
  end

  # [[group, [items...]], ...] in pay order, groups with nobody left out.
  def self.grouped(batch, items)
    sorted = sort(batch, items)
    groups_for(batch).filter_map do |group|
      members = sorted.select { |item| group_for(item) == group }
      [ group, members ] if members.any?
    end
  end
end
