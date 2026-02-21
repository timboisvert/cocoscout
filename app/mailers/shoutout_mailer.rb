# frozen_string_literal: true

class ShoutoutMailer < ApplicationMailer
  def shoutout_received(shoutout)
    @shoutout = shoutout
    @recipient = shoutout.shoutee
    @author = shoutout.author

    profile_url = Rails.application.routes.url_helpers.profile_url(
      @recipient,
      **default_url_options
    )

    rendered = ContentTemplateService.render("shoutout_notification", {
      recipient_name: @recipient.first_name || "there",
      author_name: @author.name,
      shoutout_text: shoutout.content,
      profile_url: profile_url
    })

    @subject = rendered[:subject]
    @body = rendered[:body]

    mail(to: @recipient.email, subject: @subject) do |format|
      format.html { render html: @body.html_safe, layout: "mailer" }
    end
  end
end
