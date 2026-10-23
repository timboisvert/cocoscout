# frozen_string_literal: true

# Adding people to a mailing list by hand: one at a time, or many pasted
# ("Name, email", "Name <email>", a spreadsheet's two columns, or just
# emails, one per line). It says what it found before anything's added: new,
# already on the list, unsubscribed (never re-added) and bounced or
# complained anywhere (never emailed).
class FollowerIntake
  EMAIL = /[A-Z0-9._%+'-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i
  STATUS_WORDS = { "new" => "New", "already" => "Already on it", "unsubscribed" => "Unsubscribed: won't be added",
                   "suppressed" => "Bounced before: won't be added", "invalid" => "Not an email address" }.freeze

  Entry = Struct.new(:name, :email, :status, keyword_init: true) do
    def addable? = status == "new"
    def words = STATUS_WORDS.fetch(status)
  end

  def initialize(list)
    @list = list
    @organization = list.organization
  end

  def self.parse(text)
    seen = Set.new
    text.to_s.each_line.filter_map do |line|
      line = line.strip
      next if line.blank?

      email = line[EMAIL]
      unless email
        next Entry.new(name: nil, email: line.first(80), status: "invalid")
      end
      email = email.downcase
      next if seen.include?(email)

      seen << email
      name = line.sub(/<?#{Regexp.escape(line[EMAIL])}>?/, "").gsub(/[,;\t"]+/, " ").squish.presence
      Entry.new(name: name, email: email, status: nil)
    end
  end

  # Fills in each entry's status.
  def check(entries)
    emails = entries.map(&:email).compact
    followers = @organization.followers.where(email: emails).index_by(&:email)
    on_list = @list.mailing_list_memberships.joins(:follower).where(followers: { email: emails }).pluck("followers.email").to_set
    suppressed = EmailSuppression.where(email: emails).pluck(:email).to_set
    entries.each do |entry|
      next if entry.status == "invalid"

      follower = followers[entry.email]
      entry.status = if suppressed.include?(entry.email) || follower&.status.in?(%w[bounced complained]) then "suppressed"
      elsif follower&.status == "unsubscribed" then "unsubscribed"
      elsif on_list.include?(entry.email) then "already"
      else "new"
      end
    end
    entries
  end

  # Adds the new ones; returns how many.
  def add!(entries, kind:, added_by_person: nil)
    added = 0
    check(entries).select(&:addable?).each do |entry|
      Follower.transaction do
        follower = Follower.for!(@organization, entry.email, name: entry.name)
        membership = @list.mailing_list_memberships.find_or_create_by!(follower: follower)
        next unless membership.previously_new_record?

        follower.follower_sources.create!(kind: kind, mailing_list: @list, added_by_person: added_by_person, occurred_at: Time.current)
        added += 1
      end
    end
    added
  end
end
