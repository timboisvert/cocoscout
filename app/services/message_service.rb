class MessageService
  class << self
    # Send to cast of a specific show
    # Recipients are People assigned to the show
    def send_to_show_cast(show:, sender:, subject:, body:)
      # Get People (not Users) who are cast in this show
      people = show.role_assignments.includes(:entity).map do |ra|
        ra.entity.is_a?(Person) ? ra.entity : ra.entity.members
      end.flatten.uniq

      send_to_people(
        sender: sender,
        people: people,
        subject: subject,
        body: body,
        organization: show.production.organization,
        regarding: show,
        message_type: :cast_contact
      )
    end

    # Send to all cast of a production (all shows)
    def send_to_production_cast(production:, sender:, subject:, body:)
      people = production.cast_people.to_a

      send_to_people(
        sender: sender,
        people: people,
        subject: subject,
        body: body,
        organization: production.organization,
        regarding: production,
        message_type: :cast_contact
      )
    end

    # Send to talent pool members
    def send_to_talent_pool(production:, sender:, subject:, body:, person_ids: nil)
      pool = production.effective_talent_pool
      people = person_ids ? pool.people.where(id: person_ids).to_a : pool.people.to_a

      send_to_people(
        sender: sender,
        people: people,
        subject: subject,
        body: body,
        organization: production.organization,
        regarding: production,
        message_type: :talent_pool
      )
    end

    # Send direct message to a specific Person
    # No "regarding" object - just a direct conversation
    def send_direct(sender:, recipient_person:, subject:, body:, organization: nil)
      Message.create!(
        sender: sender,
        recipient: recipient_person,  # Person, not User!
        organization: organization,
        subject: subject,
        body: body,
        message_type: :direct
      )
    end

    # Send to a Group (all members receive individually, but message shows group context)
    def send_to_group(sender:, group:, subject:, body:, organization: nil, regarding: nil)
      send_to_people(
        sender: sender,
        people: group.members.to_a,
        subject: subject,
        body: body,
        organization: organization || group.production&.organization,
        regarding: regarding,
        message_type: :cast_contact
      )
    end

    private

    # Core method: send to array of People, creating a batch if multiple
    def send_to_people(sender:, people:, subject:, body:, message_type:,
                       organization: nil, regarding: nil)
      people = people.uniq.select { |p| p.user.present? }  # Only people with accounts
      return [] if people.empty?

      # Create batch if sending to multiple people
      batch = nil
      if people.size > 1
        batch = MessageBatch.create!(
          sender: sender,
          organization: organization,
          regarding: regarding,
          subject: subject,
          message_type: message_type,
          recipient_count: people.size
        )
      end

      # Create individual message for each person
      messages = people.map do |person|
        Message.create!(
          sender: sender,
          recipient: person,  # Person, not User!
          message_batch: batch,
          organization: organization,
          regarding: regarding,
          subject: subject,
          body: body,
          message_type: message_type
        )
      end

      messages
    end
  end
end
