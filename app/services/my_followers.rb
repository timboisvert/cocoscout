# frozen_string_literal: true

# What a producer sees in My Followers (Mailing lists, V1.1): everyone on the
# lists organizations share with them, one row per email, with where each
# came from at each organization. They see only how someone came to a list
# shared with them: tickets to that list's productions, or being added to it.
# Read-only for them, apart from adding people.
class MyFollowers
  Row = Struct.new(:email, :name, :entries, keyword_init: true) do
    # Following at any organization that shares them.
    def following? = entries.any? { |entry| entry.following }
    def since = entries.flat_map(&:sources).map(&:occurred_at).min || entries.map(&:joined_at).compact.min
    def organizations = entries.map(&:organization).uniq
  end
  Entry = Struct.new(:organization, :list, :follower, :sources, :following, :joined_at, keyword_init: true)

  def initialize(user)
    @user = user
  end

  def lists
    @lists ||= MailingListShare.lists_for(@user).includes(:organization, :productions).order(:name).to_a
  end

  def organizations
    lists.map(&:organization).uniq.sort_by(&:name)
  end

  # The person a list is shared with (for "added by you").
  def sharing_person(list)
    MailingListShare.where(mailing_list: list, person_id: @user.people.select(:id)).first&.person
  end

  def viewer
    @viewer ||= MailingListShare.where(mailing_list_id: lists.map(&:id), person_id: @user.people.select(:id)).first&.person || @user.person
  end

  def rows(organization_id: nil, kind: nil, q: nil)
    chosen = lists.select { |list| organization_id.blank? || list.organization_id == organization_id.to_i }
    return [] if chosen.empty?

    suppressed = Set.new
    memberships = MailingListMembership.where(mailing_list_id: chosen.map(&:id))
                                       .includes(follower: { follower_sources: :production })
    by_list = chosen.index_by(&:id)
    emails = memberships.map { |membership| membership.follower.email }.uniq
    suppressed = EmailSuppression.where(email: emails).pluck(:email).to_set

    rows = {}
    memberships.each do |membership|
      follower = membership.follower
      list = by_list[membership.mailing_list_id]
      sources = visible_sources(follower, list)
      next if kind.present? && sources.none? { |source| source.kind == kind }

      row = rows[follower.email] ||= Row.new(email: follower.email, name: follower.name, entries: [])
      row.name ||= follower.name
      row.entries << Entry.new(organization: list.organization, list: list, follower: follower, sources: sources,
                               following: follower.subscribed? && !suppressed.include?(follower.email), joined_at: membership.created_at)
    end
    result = rows.values
    if q.present?
      needle = q.downcase
      result.select! { |row| row.email.include?(needle) || row.name.to_s.downcase.include?(needle) }
    end
    result.sort_by { |row| row.since || Time.at(0) }.reverse
  end

  private

  # How someone came to this list: tickets to its productions (any, on the
  # main list) or being added to it.
  def visible_sources(follower, list)
    production_ids = list.productions.map(&:id)
    follower.follower_sources.select do |source|
      source.mailing_list_id == list.id ||
        (source.kind == "checkout" && (list.main? || production_ids.include?(source.production_id)))
    end.sort_by(&:occurred_at)
  end
end
