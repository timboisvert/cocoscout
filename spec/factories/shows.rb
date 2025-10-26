FactoryBot.define do
  factory :show do
    association :production
    association :location
    date_and_time { 1.week.from_now }
    event_type { :show }

    trait :recurring do
      recurrence_group_id { SecureRandom.uuid }
    end

    trait :rehearsal do
      event_type { :rehearsal }
    end

    trait :meeting do
      event_type { :meeting }
    end
  end
end
