# frozen_string_literal: true

namespace :productions do
  desc "Delete the production logo files left in storage (productions are pictured by their poster and wide image now)"
  task purge_logos: :environment do
    attachments = ActiveStorage::Attachment.where(record_type: "Production", name: "logo")
    count = attachments.count
    attachments.find_each(&:purge)
    puts "Purged #{count} production #{'logo'.pluralize(count)}."
  end
end
