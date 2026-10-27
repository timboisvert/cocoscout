# frozen_string_literal: true

# Email for a payout run: the manager notices (submitted, funded, everyone's
# paid, partly paid, the funding debit bounced, a payout came back) and the
# payee's "on its way". Copy lives in ContentTemplates; it arrives rendered.
class PayoutBatchMailer < ApplicationMailer
  include ActionView::Helpers::SanitizeHelper

  # One of the manager notices, to one of the people Money settings →
  # Notifications names. The signature is what ContentTemplateService's email
  # channel calls:
  #   mailer_class.send(method, person, production, body, subject, email_batch_id:)
  # organization_id rides in params (deliver_later keeps them) so the footer
  # and the email log name the organization.
  def manager_notice(person, production, body, subject, email_batch_id: nil)
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

  # Tells one payee their money is on its way. Copy (including the first-payment
  # variant and the connect-a-bank variant) is rendered by the caller from the
  # "payout_sent_to_payee" template and handed in already interpolated.
  def sent_to_payee(person:, batch:, rendered:)
    # For ApplicationMailer's tracking headers (email log attribution).
    @person = person
    @user = person.user
    @organization = batch.organization
    return if person.email.blank?

    mail(to: person.email, subject: rendered[:subject]) do |format|
      format.html { render html: rendered[:body].html_safe, layout: "mailer" }
      format.text { render plain: plain_text_from(rendered[:body]) }
    end
  end

  private

  # Block tags are what separate the sentences, so stripping them without
  # putting the breaks back runs the copy together ("Hi Allison,$150.00 is on
  # its way").
  def plain_text_from(html)
    with_breaks = html
      .gsub(%r{</(p|div|h[1-6]|li|tr)>}i, "\n\n")
      .gsub(%r{<br\s*/?>}i, "\n")
    strip_tags(with_breaks)
      .split("\n").map(&:strip).join("\n")
      .gsub(/\n{3,}/, "\n\n").strip
  end
end
