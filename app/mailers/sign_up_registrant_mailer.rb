# frozen_string_literal: true

class SignUpRegistrantMailer < ApplicationMailer
  # Sent when a registrant successfully signs up for a slot
  def confirmation(registration)
    @registration = registration
    setup_common_variables

    return if @recipient_email.blank?

    template = EmailTemplateService.render("sign_up_confirmation", template_variables)

    mail(
      to: @recipient_email,
      subject: template[:subject]
    ) do |format|
      format.html { render html: template[:body].html_safe, layout: "mailer" }
    end
  end

  # Sent when a registrant joins the queue (admin_assigns mode)
  def queued(registration)
    @registration = registration
    setup_common_variables

    return if @recipient_email.blank?

    template = EmailTemplateService.render("sign_up_queued", template_variables)

    mail(
      to: @recipient_email,
      subject: template[:subject]
    ) do |format|
      format.html { render html: template[:body].html_safe, layout: "mailer" }
    end
  end

  # Sent when a registrant is moved from queue to a slot
  def slot_assigned(registration)
    @registration = registration
    setup_common_variables

    return if @recipient_email.blank?

    template = EmailTemplateService.render("sign_up_slot_assigned", template_variables)

    mail(
      to: @recipient_email,
      subject: template[:subject]
    ) do |format|
      format.html { render html: template[:body].html_safe, layout: "mailer" }
    end
  end

  # Sent when a registrant changes their slot
  def slot_changed(registration)
    @registration = registration
    setup_common_variables

    return if @recipient_email.blank?

    template = EmailTemplateService.render("sign_up_slot_changed", template_variables)

    mail(
      to: @recipient_email,
      subject: template[:subject]
    ) do |format|
      format.html { render html: template[:body].html_safe, layout: "mailer" }
    end
  end

  # Sent when a registration is cancelled
  def cancelled(registration)
    @registration = registration
    setup_common_variables

    return if @recipient_email.blank?

    template = EmailTemplateService.render("sign_up_cancelled", template_variables)

    mail(
      to: @recipient_email,
      subject: template[:subject]
    ) do |format|
      format.html { render html: template[:body].html_safe, layout: "mailer" }
    end
  end

  private

  def setup_common_variables
    @slot = @registration.sign_up_slot
    @instance = @slot&.sign_up_form_instance || @registration.sign_up_form_instance
    @form = @slot&.sign_up_form || @instance&.sign_up_form
    @show = @instance&.show
    @production = @form&.production

    @registrant_name = @registration.display_name || "Guest"
    @recipient_email = @registration.display_email
  end

  def template_variables
    show_name = @show&.secondary_name.presence || @show&.event_type&.titleize || @instance&.show_name || "TBD"
    show_date = @show&.date_and_time&.strftime("%B %d, %Y at %l:%M %p") || @instance&.show_date&.strftime("%B %d, %Y") || "TBD"

    {
      registrant_name: @registrant_name,
      sign_up_form_name: @form&.name || "Sign-Up",
      slot_name: @slot&.display_name || "TBD",
      show_name: show_name,
      show_date: show_date,
      production_name: @production&.name || ""
    }
  end
end
