# frozen_string_literal: true

# Evaluates a segment's rule (Segment) against an organization's followers and
# where they came from (FollowerSource). Each condition is a subquery of
# follower ids; "all" ands them, "any" ors them.
class SegmentQuery
  def initialize(organization, rule)
    @organization = organization
    @rule = rule.is_a?(Hash) ? rule.stringify_keys : {}
  end

  # Only people on one of the organization's lists: a buyer who ticked no
  # box is recorded for what they bought, but never emailed.
  def followers
    base = on_a_list
    scopes = Array(@rule["conditions"]).filter_map { |condition| condition_scope(condition.stringify_keys) if condition.is_a?(Hash) }
    return base if scopes.empty?

    if @rule["match"] == "any"
      scopes.drop(1).reduce(scopes.first) { |combined, scope| combined.or(scope) }
    else
      # and, not merge: merge lets a later where on the same column replace an earlier one.
      scopes.reduce(base) { |combined, scope| combined.and(scope) }
    end
  end

  # What a condition means, in words ("Bought tickets to Laugh-Along, Live!").
  def self.describe(organization, condition)
    condition = condition.stringify_keys
    case condition["type"]
    when "on_list"
      list = organization.mailing_lists.find_by(id: condition["list_id"])
      list && "On #{list.name}"
    when "bought" then "Bought tickets to #{target_words(organization, condition['target'])}"
    when "never_bought" then "Never bought tickets to #{target_words(organization, condition['target'])}"
    when "times_at_least" then "Came at least #{condition['count'].to_i} #{'time'.pluralize(condition['count'].to_i)}"
    when "last_bought"
      date = Date.parse(condition["date"].to_s) rescue nil
      date && "Last bought #{condition['when'] == 'after' ? 'after' : 'before'} #{date.strftime('%b %-d, %Y')}"
    when "joined_from" then "Joined from #{KIND_WORDS.fetch(condition['kind'].to_s, 'anywhere')}"
    end
  end

  KIND_WORDS = { "checkout" => "ticket checkout", "manual" => "being added by hand", "paste" => "a pasted list",
                 "contacts" => "Contacts", "added_by_share" => "a producer" }.freeze

  def self.target_words(organization, target)
    kind, id = target.to_s.split(":", 2)
    case kind
    when "production" then organization.productions.find_by(id: id)&.name || "a production"
    when "list"
      list = organization.mailing_lists.find_by(id: id)
      list ? "any of #{list.name}" : "a list's productions"
    when "type" then id == "third_party" ? "a contract production" : "an in-house production"
    else "anything"
    end
  end

  private

  def on_a_list
    @organization.followers.where(id: MailingListMembership.where(mailing_list_id: @organization.mailing_lists.active.select(:id)).select(:follower_id))
  end

  def condition_scope(condition)
    base = on_a_list
    case condition["type"]
    when "on_list"
      base.where(id: MailingListMembership.where(mailing_list_id: list_ids([ condition["list_id"] ])).select(:follower_id))
    when "bought"
      base.where(id: tickets_to(condition["target"]).select(:follower_id))
    when "never_bought"
      base.where.not(id: tickets_to(condition["target"]).select(:follower_id))
    when "times_at_least"
      count = [ condition["count"].to_i, 1 ].max
      base.where(id: tickets.group(:follower_id).having("COUNT(DISTINCT follower_sources.ticket_order_id) >= ?", count).select(:follower_id))
    when "last_bought"
      date = Date.parse(condition["date"].to_s) rescue nil
      return nil unless date

      op = condition["when"] == "after" ? ">=" : "<"
      base.where(id: tickets.group(:follower_id).having("MAX(follower_sources.occurred_at) #{op} ?", date.beginning_of_day).select(:follower_id))
    when "joined_from"
      base.where(id: sources.where(kind: condition["kind"].to_s).select(:follower_id))
    end
  end

  def sources
    FollowerSource.joins(:follower).where(followers: { organization_id: @organization.id })
  end

  def tickets
    sources.where(kind: "checkout")
  end

  def tickets_to(target)
    kind, id = target.to_s.split(":", 2)
    case kind
    when "production" then tickets.where(production_id: @organization.productions.where(id: id).select(:id))
    when "list" then tickets.where(production_id: MailingListProduction.where(mailing_list_id: list_ids([ id ])).select(:production_id))
    when "type" then tickets.where(production_id: @organization.productions.where(production_type: id.presence_in(%w[in_house third_party course]) || "in_house").select(:id))
    else tickets
    end
  end

  def list_ids(ids)
    @organization.mailing_lists.where(id: ids).select(:id)
  end
end
