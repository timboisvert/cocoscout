# frozen_string_literal: true

FactoryBot.define do
  factory :tax_form_1099 do
    association :organization
    association :person
    tax_year { Date.current.year }
    nec_box1_cents { 250_000 }
    federal_withheld_cents { 0 }
    adjustment_cents { 0 }
    status { "draft" }
    recipient_name { "Sam Staffer" }
    recipient_tin_type { "ssn" }
    recipient_tin_last4 { "6789" }
    recipient_address_line1 { "123 Main St" }
    recipient_city { "Springfield" }
    recipient_state { "IL" }
    recipient_zip { "62701" }
    payer_name { "Stars & Garters LLC" }
    payer_ein_last4 { "3789" }
    payer_address_line1 { "1 Stage Door" }
    payer_city { "Chicago" }
    payer_state { "IL" }
    payer_zip { "60601" }
  end
end
