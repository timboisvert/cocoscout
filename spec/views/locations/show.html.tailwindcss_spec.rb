require 'rails_helper'

RSpec.describe "locations/show", type: :view do
  before(:each) do
    assign(:location, Location.create!(
      address1: "Address1",
      address2: "Address2",
      city: "City",
      state: "State",
      postal_code: "Postal Code"
    ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Address1/)
    expect(rendered).to match(/Address2/)
    expect(rendered).to match(/City/)
    expect(rendered).to match(/State/)
    expect(rendered).to match(/Postal Code/)
  end
end
