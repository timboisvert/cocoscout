class ApplicationMailer < ActionMailer::Base
  default from: "no-reply@cocoscout.com"
  layout "mailer"

  before_action :attach_logo

  private

  def attach_logo
    attachments.inline["cocoscout.png"] = File.read(Rails.root.join("app", "assets", "images", "cocoscout.png"))
  end
end
