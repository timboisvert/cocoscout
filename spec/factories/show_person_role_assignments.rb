# frozen_string_literal: true

FactoryBot.define do
  factory :show_person_role_assignment do
    transient do
      with_production { nil }
    end

    association :show
    association :assignable, factory: :person

    # Ensure role is eagerly built and linked
    role do
      prod = with_production || show&.production || association(:production)
      association(:role, production: prod)
    end
  end
end
