# frozen_string_literal: true

# Tap to Pay on iPhone's launch email (TapToPayTemplates, Apple's 6.1), sent
# by TapToPayLaunch to the people who can sell at a door that has it.
class TapToPayMailer < ApplicationMailer
  HERO = Rails.root.join("app", "assets", "images", "tap_to_pay_hero_email.jpg")

  def launch(user)
    attachments.inline["tap_to_pay.jpg"] = File.binread(HERO)
    rendered = ContentTemplateService.render("tap_to_pay_launch", {
      settings_url: Rails.application.routes.url_helpers.door_tap_to_pay_url(**default_url_options),
      hero_image_url: attachments["tap_to_pay.jpg"].url
    })
    mail(to: user.email_address, subject: rendered[:subject]) do |format|
      format.html { render html: rendered[:body].html_safe, layout: "mailer" }
    end
  end
end
