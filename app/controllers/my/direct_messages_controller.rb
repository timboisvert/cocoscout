class My::DirectMessagesController < ApplicationController
  before_action :require_authentication

  def create
    subject = params[:subject]
    body = params[:body]
    images = params[:images]&.reject(&:blank?)
    recipient = Person.find(params[:person_id])

    # Any authenticated user used to be able to DM any Person on the platform
    # by iterating ids (the flash confirming recipient.name doubled as a
    # name-disclosure oracle). Restrict to people the sender can legitimately
    # reach: a shared organization, a shared course, or an existing thread.
    unless can_direct_message?(recipient)
      redirect_back fallback_location: my_messages_path, alert: "You can't message this person"
      return
    end

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

  private

  def can_direct_message?(recipient)
    sender_people_ids = Current.user.people.pluck(:id)
    return true if recipient.user_id == Current.user.id || sender_people_ids.include?(recipient.id)

    # Shared organization (as member of either side, or as a manager).
    sender_org_ids = Organization.joins(:people).where(people: { id: sender_people_ids }).pluck(:id) |
                     Current.user.accessible_organizations.pluck(:id)
    return true if sender_org_ids.any? && recipient.organizations.where(id: sender_org_ids).exists?

    # Shared course: classmates, or student ↔ instructor (instructors don't
    # necessarily share an org with their students).
    sender_offering_ids = course_offering_ids_for(sender_people_ids)
    return true if sender_offering_ids.any? && course_offering_ids_for([ recipient.id ]).intersect?(sender_offering_ids)

    # An existing thread between the two (e.g. they messaged us first).
    they_messaged_us = Message.joins(:message_recipients)
      .where(message_recipients: { recipient_type: "Person", recipient_id: sender_people_ids })
      .where(sender_type: "Person", sender_id: recipient.id)
    if recipient.user_id
      they_messaged_us = they_messaged_us.or(
        Message.joins(:message_recipients)
               .where(message_recipients: { recipient_type: "Person", recipient_id: sender_people_ids })
               .where(sender_type: "User", sender_id: recipient.user_id)
      )
    end
    we_messaged_them = Message.joins(:message_recipients)
      .where(message_recipients: { recipient_type: "Person", recipient_id: recipient.id })
      .where(sender_type: "User", sender_id: Current.user.id)

    they_messaged_us.exists? || we_messaged_them.exists?
  end

  # Offerings a set of people belong to, as active registrants or instructors.
  def course_offering_ids_for(person_ids)
    return Set.new if person_ids.empty?

    registered = CourseRegistration.where(person_id: person_ids, status: %w[pending confirmed])
                                   .pluck(:course_offering_id)
    # No .distinct: the model's default order breaks SELECT DISTINCT; the Set dedupes.
    instructing = CourseOfferingInstructor.where(person_id: person_ids).pluck(:course_offering_id)
    (registered + instructing).to_set
  end
end
