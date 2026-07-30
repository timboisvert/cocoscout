# frozen_string_literal: true

namespace :contract_templates do
  desc "Create/refresh the Stars & Garters Residency Agreement template for an org. Usage: bin/rails 'contract_templates:seed_residency[ORG_ID]'"
  task :seed_residency, [ :organization_id ] => :environment do |_t, args|
    org_id = args[:organization_id].presence || ENV["ORG_ID"]
    abort "Provide an organization id: bin/rails 'contract_templates:seed_residency[ORG_ID]'" if org_id.blank?

    organization = Organization.find(org_id)
    template = organization.contract_templates
                           .find_or_initialize_by(name: StarsAndGartersResidencyTemplate::TEMPLATE_NAME)
    was_new = template.new_record?

    template.description = "Standard 2026 residency rental agreement for the Mainstage / Rouge Room."
    template.active = true
    template.content = StarsAndGartersResidencyTemplate::CONTENT
    template.save!

    action = was_new ? "Created" : "Updated"
    puts "#{action} \"#{template.name}\" (v#{template.version}) for organization ##{organization.id} — #{organization.name}"
  end
end
