require "test_helper"

class AuditionRequestTest < ActiveSupport::TestCase
  test "Audition Request must have a Person and a Call to Audition" do
    production_company = ProductionCompany.create!(name: "Test Company")

    production = Production.create!(name: "Test Production", production_company: production_company, description: "A test production")

    audition_request = AuditionRequest.new
    assert_not audition_request.valid?
    assert_includes audition_request.errors[:person], "must exist"
    assert_includes audition_request.errors[:call_to_audition], "must exist"

    person = Person.create!(name: "Test Person", email: "test@example.com")
    call_to_audition = CallToAudition.create!(production: production, opens_at: 1.week.ago, closes_at: 1.week.from_now)
    audition_request.person = person
    audition_request.call_to_audition = call_to_audition
    assert audition_request.valid?
  end
end
