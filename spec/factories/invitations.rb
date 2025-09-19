FactoryBot.define do
  factory :invitation do
    sequence(:email) { |n| "invitee#{n}@example.com" }
    association :production_company
    token { SecureRandom.hex(10) }
  end
end
