# frozen_string_literal: true

require "csv"

# A spreadsheet of followers, emailed to whoever asked (FollowerMailer#export_ready):
#   list_id   a manager exporting one list: everyone on it, with their status
#   user_id   a producer exporting My Followers: everyone still following
#             them somewhere, one row per email, a column for where each
#             came from
class FollowersExportJob < ApplicationJob
  queue_as :default

  def perform(person_id, list_id: nil, user_id: nil)
    person = Person.find_by(id: person_id)
    return unless person&.email.present?

    if list_id
      list = MailingList.find_by(id: list_id)
      return unless list

      csv, count = list_csv(list)
      what = list.name
      filename = "#{list.name.parameterize}-followers-#{Date.current}.csv"
    else
      user = User.find_by(id: user_id)
      return unless user

      csv, count = my_csv(user)
      what = "everyone in My Followers"
      filename = "my-followers-#{Date.current}.csv"
    end
    FollowerNoticeMailer.export_ready(person, what: what, count: count, csv: csv, filename: filename).deliver_now
  end

  private

  def list_csv(list)
    followers = list.followers.includes(follower_sources: %i[production added_by_person]).order(:email).to_a
    csv = CSV.generate do |out|
      out << [ "Name", "Email", "Status", "Where they came from", "Since" ]
      followers.each do |follower|
        sources = follower.follower_sources.sort_by(&:occurred_at)
        out << [ follower.name, follower.email, follower.status, sources.map(&:label).join("; "), sources.first&.occurred_at&.to_date ]
      end
    end
    [ csv, followers.size ]
  end

  def my_csv(user)
    my = MyFollowers.new(user)
    rows = my.rows.select(&:following?)
    csv = CSV.generate do |out|
      out << [ "Name", "Email", "Organizations", "Where they came from", "Since" ]
      rows.each do |row|
        following = row.entries.select(&:following)
        out << [ row.name, row.email, following.map { |e| e.organization.name }.uniq.join("; "),
                 following.flat_map { |e| e.sources.map { |s| "#{e.organization.name}: #{s.label(viewer: my.viewer)}" } }.join("; "),
                 row.since&.to_date ]
      end
    end
    [ csv, rows.size ]
  end
end
