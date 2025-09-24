require 'rails_helper'

RSpec.describe "locations/index", type: :view do
  before(:each) do
    assign(:locations, [
      Location.create!(
        address1: "Address1",
        address2: "Address2",
        city: "City",
        state: "State",
        postal_code: "Postal Code"
      ),
      Location.create!(
        address1: "Address1",
        address2: "Address2",
        city: "City",
        state: "State",
        postal_code: "Postal Code"
      )
    ])
  end

  it "renders a list of locations" do
    render
    cell_selector = 'div>p'
    assert_select cell_selector, text: Regexp.new("Address1".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("Address2".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("City".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("State".to_s), count: 2
    assert_select cell_selector, text: Regexp.new("Postal Code".to_s), count: 2
  end
end
