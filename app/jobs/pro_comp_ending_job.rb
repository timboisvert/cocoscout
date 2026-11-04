# frozen_string_literal: true

# Daily: tell each organization whose complimentary Pro ends in two weeks,
# then three days, what Pro has done for it and how to keep it.
class ProCompEndingJob < ApplicationJob
  queue_as :background

  def perform(now: Time.current)
    Organization.where(comped_indefinitely: false).where(comped_until: now..(now + ProCompEnding::REMINDERS.values.max + 1.day)).find_each do |organization|
      ending = ProCompEnding.new(organization, now: now)
      ending.due_reminders.each do |stage|
        organization.billing_contacts.each do |contact|
          AppMailer.with(template_key: "pro_comp_ending", to: contact.email, variables: ending.email_variables(contact.first_name)).send_template.deliver_now
        end
        ending.mark_sent!(stage)
      end
    end
  end
end
