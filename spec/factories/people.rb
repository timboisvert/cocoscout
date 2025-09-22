FactoryBot.define do
  factory :person do
    sequence(:email) { |n| "person#{n}@example.com" }
    name { "Test Person" }
  end
end
