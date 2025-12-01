FactoryBot.define do
  factory :group do
    sequence(:name) { |n| "Test Group #{n}" }
    sequence(:email) { |n| "group#{n}@example.com" }
    sequence(:public_key) { |n| "testgroup#{n}" }
  end
end
