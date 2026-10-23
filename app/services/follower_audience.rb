# frozen_string_literal: true

# Who an email to followers goes to: everyone on its lists and in its
# segments, once each, minus anyone unsubscribed, bounced or complained
# (here or anywhere on CocoScout).
class FollowerAudience
  def initialize(follower_email)
    @email = follower_email
    @organization = follower_email.organization
  end

  # Everyone the lists and segments name, emailable or not.
  def named
    ids = MailingListMembership.where(mailing_list_id: @email.lists.active.select(:id)).pluck(:follower_id)
    @email.segments.each { |segment| ids.concat(segment.followers.pluck(:id)) }
    @organization.followers.where(id: ids.uniq)
  end

  def recipients
    named.emailable
  end

  def recipient_count
    recipients.count
  end

  def left_out_count
    named.count - recipient_count
  end

  # Per list and segment, for the send window: [[name, count], ...] where each
  # later row counts only people not already counted.
  def breakdown
    seen = Set.new
    rows = []
    @email.lists.active.main_first.each do |list|
      ids = list.followers.pluck(:id)
      rows << [ "#{list.name} list", (ids - seen.to_a).size ]
      seen.merge(ids)
    end
    @email.segments.order(:name).each do |segment|
      ids = segment.followers.pluck(:id)
      rows << [ "#{segment.name}#{', not already counted' if rows.any?}", (ids - seen.to_a).size ]
      seen.merge(ids)
    end
    rows
  end
end
