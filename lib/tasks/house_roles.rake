# frozen_string_literal: true

namespace :house_roles do
  desc "Add the standard flat-rate roles (Security, Videographer) to an org. Usage: rake house_roles:seed_flat_roles[ORG_ID]"
  task :seed_flat_roles, [ :organization_id ] => :environment do |_t, args|
    organization = Organization.find(args[:organization_id])

    # Paid for the night, not by the hour — the amounts are a starting point,
    # editable on the roles page like any other.
    roles = [
      { name: "Security", default_flat_rate_cents: 5_000 },
      { name: "Videographer", default_flat_rate_cents: 15_000 }
    ]

    roles.each do |attrs|
      role = organization.house_roles.find_or_initialize_by(name: attrs[:name])
      if role.persisted?
        puts "#{attrs[:name]} already exists for #{organization.name} — left as is"
        next
      end

      role.assign_attributes(
        role_type: :house,
        pay_type: "flat",
        default_flat_rate_cents: attrs[:default_flat_rate_cents],
        default_required_count: 1,
        position: (organization.house_roles.maximum(:position) || 0) + 1
      )
      role.save!
      puts "Created #{attrs[:name]} (#{role.rate_label}) for #{organization.name}"
    end
  end
end
