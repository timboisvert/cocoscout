FactoryBot.define do
  factory :team_invitation do
    sequence(:email) { |n| "invitee#{n}@example.com" }
    association :production_company
    token { SecureRandom.hex(10) }
  end
end
