# frozen_string_literal: true

# Email for Tell people (ShowChangeNotices): a show canceled, taken away or
# moved, to its cast or the staff on its shifts. Copy lives in
# ContentTemplates and arrives rendered. The signature is what
# ContentTemplateService's email channel calls:
#   mailer_class.send(method, person, production, body, subject, email_batch_id:)
# organization_id rides in params so the email log names the organization.
class ShowChangeMailer < ApplicationMailer
  include ActionView::Helpers::SanitizeHelper

  def notice(person, production, body, subject, email_batch_id: nil)
    @person = person
    @user = person.user
    @production = production
    @organization = Organization.find_by(id: params[:organization_id]) if params.is_a?(Hash) && params[:organization_id]
    @email_batch_id = email_batch_id
    return if person.email.blank?

    mail(to: person.email, subject: subject) do |format|
      format.html { render html: body.html_safe, layout: "mailer" }
      format.text { render plain: plain_text_from(body) }
    end
  end

  private

  # Block tags separate the sentences, so put the breaks back before
  # stripping them.
  def plain_text_from(html)
    with_breaks = html
      .gsub(%r{</(p|div|h[1-6]|li|tr)>}i, "\n\n")
      .gsub(%r{<br\s*/?>}i, "\n")
    strip_tags(with_breaks)
      .split("\n").map(&:strip).join("\n")
      .gsub(/\n{3,}/, "\n\n").strip
  end
end
