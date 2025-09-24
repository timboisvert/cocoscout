require 'rails_helper'

RSpec.describe "locations/edit", type: :view do
  let(:location) {
    Location.create!(
      address1: "MyString",
      address2: "MyString",
      city: "MyString",
      state: "MyString",
      postal_code: "MyString"
    )
  }

  before(:each) do
    assign(:location, location)
  end

  it "renders the edit location form" do
    render

    assert_select "form[action=?][method=?]", location_path(location), "post" do

      assert_select "input[name=?]", "location[address1]"

      assert_select "input[name=?]", "location[address2]"

      assert_select "input[name=?]", "location[city]"

      assert_select "input[name=?]", "location[state]"

      assert_select "input[name=?]", "location[postal_code]"
    end
  end
end
