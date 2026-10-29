# frozen_string_literal: true

require "csv"

# A spreadsheet of one list's followers, with their status, emailed to the
# manager who asked (FollowerNoticeMailer#export_ready).
class FollowersExportJob < ApplicationJob
  queue_as :default

  def perform(person_id, list_id:)
    person = Person.find_by(id: person_id)
    return unless person&.email.present?

    list = MailingList.find_by(id: list_id)
    return unless list

    csv, count = list_csv(list)
    filename = "#{list.name.parameterize}-followers-#{Date.current}.csv"
    FollowerNoticeMailer.export_ready(person, what: list.name, count: count, csv: csv, filename: filename).deliver_now
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
end
