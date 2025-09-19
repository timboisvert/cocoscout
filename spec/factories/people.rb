FactoryBot.define do
  factory :person do
    sequence(:email) { |n| "person#{n}@example.com" }
    stage_name { "Test Person" }
  end
end
