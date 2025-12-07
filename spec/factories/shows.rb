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

    trait :class_event do
      event_type { :class }
    end

    trait :workshop do
      event_type { :workshop }
    end

    trait :online do
      location { nil }
      is_online { true }
      online_location_info { "https://zoom.us/j/1234567890" }
    end
  end
end
