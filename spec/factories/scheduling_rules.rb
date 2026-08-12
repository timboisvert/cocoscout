# frozen_string_literal: true

FactoryBot.define do
  factory :scheduling_rule do
    association :organization
    association :person
    house_role { association :house_role, organization: organization }
    rule_type { :production_anchored }
    production { association :production, organization: organization }

    # A rule is only valid for someone on staff, so quietly put the person on
    # staff unless the spec already did.
    after(:build) do |rule|
      next if rule.organization.blank? || rule.person.blank?
      next if OrganizationStaffMember.active.exists?(organization: rule.organization, person: rule.person)

      create(:organization_staff_member, organization: rule.organization, person: rule.person)
    end

    trait :weekday do
      rule_type { :weekday }
      production { nil }
      day_of_week { 4 } # Thursday
      starts_local_time { "18:00" }
      ends_local_time { "22:00" }
    end
  end
end
