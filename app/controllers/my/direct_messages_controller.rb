class My::DirectMessagesController < ApplicationController
  before_action :require_authentication

  def create
    subject = params[:subject]
    body = params[:body]
    images = params[:images]&.reject(&:blank?)
    recipient = Person.find(params[:person_id])

    if subject.blank? || body.blank?
      redirect_back fallback_location: my_messages_path, alert: "Subject and message are required"
      return
    end

    message = MessageService.send_direct(
      sender: Current.user,
      recipient_person: recipient,
      subject: subject,
      body: body
    )

    # Attach images if provided
    message&.images&.attach(images) if images.present?

    redirect_to my_messages_path, notice: "Message sent to #{recipient.name}"
  end
end
