# frozen_string_literal: true

# CocoScout's own notes about mailing lists, in CocoScout's look: the
# spreadsheet you asked for.
class FollowerNoticeMailer < ApplicationMailer
  def export_ready(person, what:, count:, csv:, filename:)
    rendered = FollowerTemplates.render("followers_export_ready",
                                        first_name: person.name.to_s.split.first.presence || "there", what: what,
                                        follower_count: ActionController::Base.helpers.pluralize(count, "follower"))
    @body = rendered[:body]
    attachments[filename] = { mime_type: "text/csv", content: csv }
    mail(to: person.email, subject: rendered[:subject]) { |format| format.html { render "follower_notice_mailer/words" } }
  end
end
