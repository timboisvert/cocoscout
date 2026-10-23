# frozen_string_literal: true

# CocoScout's own notes about mailing lists, in CocoScout's look: a list was
# shared with you (My Followers), and the spreadsheet you asked for.
class FollowerNoticeMailer < ApplicationMailer
  def share_invitation(share)
    @organization = share.mailing_list.organization
    person = share.person
    count = share.mailing_list.subscribed_count
    rendered = FollowerTemplates.render("follower_share_invitation",
                                        first_name: person.name.to_s.split.first.presence || "there",
                                        organization_name: @organization.name, list_name: share.mailing_list.name,
                                        follower_count: ActionController::Base.helpers.pluralize(count, "follower"),
                                        followers_url: my_followers_url(**default_url_options))
    @body = rendered[:body]
    mail(to: person.email, subject: rendered[:subject]) { |format| format.html { render "follower_notice_mailer/words" } }
  end

  def export_ready(person, what:, count:, csv:, filename:)
    rendered = FollowerTemplates.render("followers_export_ready",
                                        first_name: person.name.to_s.split.first.presence || "there", what: what,
                                        follower_count: ActionController::Base.helpers.pluralize(count, "follower"))
    @body = rendered[:body]
    attachments[filename] = { mime_type: "text/csv", content: csv }
    mail(to: person.email, subject: rendered[:subject]) { |format| format.html { render "follower_notice_mailer/words" } }
  end
end
